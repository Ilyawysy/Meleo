from __future__ import annotations

import uuid
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.gamification.stats_service import StatsService
from backend.infrastructure.database.session import get_session
from backend.infrastructure.security.auth import get_current_user_id

router = APIRouter(prefix="/api/v1/profile", tags=["profile"])


# ── Schemas ──


class BestDay(BaseModel):
    date: date
    seconds: int
    session_count: int


class BestWeek(BaseModel):
    week_start: date
    total_seconds: int
    per_day: list[int]


class BestMonth(BaseModel):
    month: str
    total_seconds: int
    heatmap: list[list[int]]


class ProfileStats(BaseModel):
    all_focus_seconds: int
    days_in_app: int
    longest_streak: int
    best_day: Optional[BestDay]
    best_week: Optional[BestWeek]
    best_month: Optional[BestMonth]


# ── Endpoint ──


@router.get("/stats", response_model=ProfileStats)
async def get_profile_stats(
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> ProfileStats:
    service = StatsService(session, current_user_id)
    data = await service.get_profile_stats()
    return ProfileStats(
        all_focus_seconds=data["all_focus_seconds"],
        days_in_app=data["days_in_app"],
        longest_streak=data["longest_streak"],
        best_day=BestDay(**data["best_day"]) if data["best_day"] else None,
        best_week=BestWeek(**data["best_week"]) if data["best_week"] else None,
        best_month=BestMonth(**data["best_month"]) if data["best_month"] else None,
    )
