from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.gamification.calculator import parse_plan_minutes
from backend.domain.gamification.entities import UserGamificationProfile
from backend.infrastructure.database.session import get_session
from backend.infrastructure.repositories.gamification_repository import (
    SqlAlchemyGamificationRepository,
)
from backend.infrastructure.security.auth import get_current_user_id

router = APIRouter(prefix="/api/v1/plan", tags=["plan"])


# ── Schemas ──


class PlanRead(BaseModel):
    hours_per_day: list[int] | None
    growth_target_hours: int | None
    growth_speed: Literal["steady", "faster", "push"] | None
    growth_started_at: datetime | None


class PlanUpdate(BaseModel):
    hours_per_day: list[Annotated[int, Field(ge=0, le=24)]] | None = Field(
        None, min_length=7, max_length=7
    )
    growth_target_hours: Annotated[int, Field(ge=0, le=10000)] | None = None
    growth_speed: Literal["steady", "faster", "push"] | None = None
    growth_started_at: datetime | None = None


# ── Helpers ──


def _hours_from_legacy_minutes_json(json_str: str | None) -> list[int] | None:
    """Fallback: convert legacy `plan_minutes_json` (keyed "1".."7", Mon..Sun)
    into the 7-int hours list used by the Adaptive Plan feature.

    Onboarding writes minutes into `plan_minutes_json` (streak/recovery logic),
    but the Adaptive Plan UI reads the newer `plan_hours_per_day`. Until
    onboarding populates both, synthesize hours from minutes on read.
    Returns None if the legacy field is missing, empty, or parse-fails.
    """
    if not json_str:
        return None
    try:
        minutes_by_weekday = parse_plan_minutes(json_str)
    except (ValueError, TypeError):
        return None
    if not minutes_by_weekday:
        return None
    hours: list[int] = []
    for weekday in range(1, 8):  # 1=Mon ... 7=Sun
        mins = minutes_by_weekday.get(weekday, 0)
        hours.append(round(mins / 60))
    if not any(h > 0 for h in hours):
        return None
    return hours


def _profile_to_plan_read(profile: UserGamificationProfile) -> PlanRead:
    hours_per_day = profile.plan_hours_per_day
    if hours_per_day is None:
        hours_per_day = _hours_from_legacy_minutes_json(profile.plan_minutes_json)
    return PlanRead(
        hours_per_day=hours_per_day,
        growth_target_hours=profile.growth_target_hours,
        growth_speed=profile.growth_speed,  # type: ignore[arg-type]
        growth_started_at=profile.growth_started_at,
    )


# ── Endpoints ──


@router.get("/", response_model=PlanRead)
async def get_plan(
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> PlanRead:
    repo = SqlAlchemyGamificationRepository(session, current_user_id)
    profile = await repo.get_profile()
    if profile is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")
    return _profile_to_plan_read(profile)


@router.patch("/", response_model=PlanRead)
async def update_plan(
    payload: PlanUpdate,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> PlanRead:
    # PATCH semantics: omitted fields untouched, explicit null clears.
    repo = SqlAlchemyGamificationRepository(session, current_user_id)
    profile = await repo.get_profile()
    if profile is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    now = datetime.now(timezone.utc)

    if "hours_per_day" in payload.model_fields_set:
        profile.plan_hours_per_day = payload.hours_per_day
        profile.plan_hours_changed_at = now

    if "growth_target_hours" in payload.model_fields_set:
        profile.growth_target_hours = payload.growth_target_hours

    if "growth_speed" in payload.model_fields_set:
        profile.growth_speed = payload.growth_speed

    if "growth_started_at" in payload.model_fields_set:
        profile.growth_started_at = payload.growth_started_at

    profile = await repo.update_profile(profile)
    await session.commit()
    return _profile_to_plan_read(profile)
