from __future__ import annotations

import uuid
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.gamification.calculator import (
    compute_xp_level,
    parse_plan_minutes,
    subcoins_to_display,
    xp_to_next_level,
)
from backend.domain.gamification.service import GamificationService
from backend.infrastructure.database.session import get_session
from backend.infrastructure.repositories import SqlAlchemyFocusRepository
from backend.infrastructure.repositories.gamification_repository import (
    SqlAlchemyGamificationRepository,
)
from backend.infrastructure.security.auth import get_current_user_id

router = APIRouter(prefix="/api/v1/gamification", tags=["gamification"])


# ── DTOs ──


class GamificationProfileOut(BaseModel):
    xp: int
    level: int
    xp_to_next_level: int
    streak_current: int
    plan_minutes: dict[int, int]
    home_tz: str
    day_cutoff_hour: int
    recovery_days_remaining: int
    minimal_mode: bool
    coins: float  # display coins (subcoins / 10)
    recovery_mode: Optional[str] = None
    shield_unlocked: bool = False
    shield_charges: int = 0
    shield_recharge_progress: int = 0
    theme_mode: str = "system"
    stat_widget_config: Optional[str] = None
    focus_duration_min: int = 25
    short_break_min: int = 5
    long_break_min: int = 15
    sessions_before_long_break: int = 4
    auto_start_break: bool = True
    auto_start_next_session: bool = False
    adjust_duration_after_session: bool = False


class ProfileUpdateRequest(BaseModel):
    plan_minutes: Optional[dict[str, int]] = None
    home_tz: Optional[str] = Field(None, max_length=50)
    day_cutoff_hour: Optional[int] = Field(None, ge=0, le=12)
    minimal_mode: Optional[bool] = None
    theme_mode: Optional[Literal["light", "dark", "system"]] = None
    focus_duration_min: Optional[int] = Field(None, ge=1, le=120)
    short_break_min: Optional[int] = Field(None, ge=1, le=30)
    long_break_min: Optional[int] = Field(None, ge=1, le=60)
    sessions_before_long_break: Optional[int] = Field(None, ge=1, le=10)
    auto_start_break: Optional[bool] = None
    auto_start_next_session: Optional[bool] = None
    adjust_duration_after_session: Optional[bool] = None
    stat_widget_config: Optional[str] = Field(None, max_length=2000)

    @field_validator("plan_minutes")
    @classmethod
    def validate_plan_minutes(cls, v: dict[str, int] | None) -> dict[str, int] | None:
        if v is None:
            return v
        for k, val in v.items():
            if k not in {"1", "2", "3", "4", "5", "6", "7"}:
                raise ValueError("plan_minutes keys must be '1'-'7'")
            if not (0 <= val <= 480):
                raise ValueError("plan_minutes values must be 0-480")
            if val != 0 and val % 10 != 0:
                raise ValueError(f"plan_minutes values must be multiples of 10, got {val}")
        return v


class DailyStatOut(BaseModel):
    date: str
    credited_minutes: int
    xp_earned: int
    coins_earned: int
    session_count: int
    is_streak_day: bool
    recovery_mode: Optional[str] = None


# ── Dependency ──


def get_gamification_service(
    db_session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> GamificationService:
    gam_repo = SqlAlchemyGamificationRepository(db_session, current_user_id)
    focus_repo = SqlAlchemyFocusRepository(db_session, current_user_id)
    return GamificationService(gam_repo, focus_repo, db_session, current_user_id)


# ── Endpoints ──


async def _profile_to_out(
    service: GamificationService,
) -> GamificationProfileOut:
    profile = await service.roll_forward()
    balance = await service._focus_repo.get_balance()
    coins_subcoins = balance.coins if balance else 0

    level = compute_xp_level(profile.xp)
    plan_minutes = parse_plan_minutes(profile.plan_minutes_json)

    today = service._user_today(profile)
    agg = await service._gam_repo.get_aggregate(today)
    recovery_mode = agg.recovery_mode if agg else None

    return GamificationProfileOut(
        xp=profile.xp,
        level=level,
        xp_to_next_level=xp_to_next_level(profile.xp),
        streak_current=profile.streak_current,
        plan_minutes=plan_minutes,
        home_tz=profile.home_tz,
        day_cutoff_hour=profile.day_cutoff_hour,
        recovery_days_remaining=profile.recovery_days_remaining,
        minimal_mode=profile.minimal_mode,
        coins=subcoins_to_display(coins_subcoins),
        recovery_mode=recovery_mode,
        shield_unlocked=profile.shield_unlocked,
        shield_charges=profile.shield_charges,
        shield_recharge_progress=profile.shield_recharge_progress,
        theme_mode=profile.theme_mode,
        stat_widget_config=profile.stat_widget_config,
        focus_duration_min=profile.focus_duration_min,
        short_break_min=profile.short_break_min,
        long_break_min=profile.long_break_min,
        sessions_before_long_break=profile.sessions_before_long_break,
        auto_start_break=profile.auto_start_break,
        auto_start_next_session=profile.auto_start_next_session,
        adjust_duration_after_session=profile.adjust_duration_after_session,
    )


@router.get("/profile", response_model=GamificationProfileOut)
async def get_profile(
    service: GamificationService = Depends(get_gamification_service),
) -> GamificationProfileOut:
    return await _profile_to_out(service)


@router.patch("/profile", response_model=GamificationProfileOut)
async def update_profile(
    payload: ProfileUpdateRequest,
    service: GamificationService = Depends(get_gamification_service),
) -> GamificationProfileOut:
    try:
        plan_minutes_int: dict[int, int] | None = None
        if payload.plan_minutes is not None:
            plan_minutes_int = {int(k): v for k, v in payload.plan_minutes.items()}

        await service.update_settings(
            plan_minutes=plan_minutes_int,
            home_tz=payload.home_tz,
            day_cutoff_hour=payload.day_cutoff_hour,
            minimal_mode=payload.minimal_mode,
            theme_mode=payload.theme_mode,
            focus_duration_min=payload.focus_duration_min,
            short_break_min=payload.short_break_min,
            long_break_min=payload.long_break_min,
            sessions_before_long_break=payload.sessions_before_long_break,
            auto_start_break=payload.auto_start_break,
            auto_start_next_session=payload.auto_start_next_session,
            adjust_duration_after_session=payload.adjust_duration_after_session,
            stat_widget_config=payload.stat_widget_config,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))

    return await _profile_to_out(service)


@router.get("/daily-stats", response_model=list[DailyStatOut])
async def get_daily_stats(
    days: int = Query(default=7, ge=1, le=90),
    service: GamificationService = Depends(get_gamification_service),
) -> list[DailyStatOut]:
    stats = await service.get_daily_stats(days)
    return [DailyStatOut(**s) for s in stats]
