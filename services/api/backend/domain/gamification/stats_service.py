from __future__ import annotations

import calendar
import uuid
from datetime import date, datetime, timedelta
from typing import Optional

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.gamification.entities import DailyFocusAggregate, UserGamificationProfile
from backend.domain.users.entities import User


class StatsService:
    def __init__(self, session: AsyncSession, user_id: uuid.UUID) -> None:
        self._session = session
        self._user_id = user_id

    async def get_profile_stats(self) -> dict:
        profile = await self._get_profile()
        all_focus_seconds = await self._all_focus_seconds()
        days_in_app = await self._days_in_app()
        longest_streak = profile.longest_streak if profile else 0
        best_day = await self._best_day()
        best_week = await self._best_week()
        best_month = await self._best_month()

        return {
            "all_focus_seconds": all_focus_seconds,
            "days_in_app": days_in_app,
            "longest_streak": longest_streak,
            "best_day": best_day,
            "best_week": best_week,
            "best_month": best_month,
        }

    async def _get_profile(self) -> Optional[UserGamificationProfile]:
        result = await self._session.execute(
            select(UserGamificationProfile).where(UserGamificationProfile.user_id == self._user_id)
        )
        return result.scalar_one_or_none()

    async def _all_focus_seconds(self) -> int:
        result = await self._session.execute(
            select(func.coalesce(func.sum(DailyFocusAggregate.total_credited_minutes), 0)).where(
                DailyFocusAggregate.user_id == self._user_id
            )
        )
        minutes = result.scalar_one()
        return int(minutes) * 60

    async def _days_in_app(self) -> int:
        result = await self._session.execute(
            select(User.created_at).where(User.id == self._user_id)
        )
        created_at: Optional[datetime] = result.scalar_one_or_none()
        if created_at is None:
            result2 = await self._session.execute(
                select(func.count(func.distinct(DailyFocusAggregate.focus_date))).where(
                    DailyFocusAggregate.user_id == self._user_id
                )
            )
            return int(result2.scalar_one())
        today = date.today()
        created_date = created_at.date()
        return max(1, (today - created_date).days + 1)

    async def _best_day(self) -> Optional[dict]:
        result = await self._session.execute(
            select(
                DailyFocusAggregate.focus_date,
                DailyFocusAggregate.total_credited_minutes,
                DailyFocusAggregate.session_count,
            )
            .where(DailyFocusAggregate.user_id == self._user_id)
            .order_by(
                DailyFocusAggregate.total_credited_minutes.desc(),
                DailyFocusAggregate.focus_date.desc(),
            )
            .limit(1)
        )
        row = result.first()
        if row is None or row.total_credited_minutes == 0:
            return None
        return {
            "date": row.focus_date,
            "seconds": row.total_credited_minutes * 60,
            "session_count": row.session_count,
        }

    async def _best_week(self) -> Optional[dict]:
        week_start_expr = func.date_trunc("week", DailyFocusAggregate.focus_date).cast(
            DailyFocusAggregate.focus_date.type
        )
        result = await self._session.execute(
            select(
                week_start_expr.label("week_start"),
                func.sum(DailyFocusAggregate.total_credited_minutes).label("total_minutes"),
            )
            .where(DailyFocusAggregate.user_id == self._user_id)
            .group_by(week_start_expr)
            .order_by(func.sum(DailyFocusAggregate.total_credited_minutes).desc())
            .limit(1)
        )
        row = result.first()
        if row is None or row.total_minutes == 0:
            return None

        week_start: date = row.week_start
        total_seconds = int(row.total_minutes) * 60

        # Fetch per-day breakdown for that week
        week_end = week_start + timedelta(days=6)

        days_result = await self._session.execute(
            select(
                DailyFocusAggregate.focus_date,
                DailyFocusAggregate.total_credited_minutes,
            ).where(
                DailyFocusAggregate.user_id == self._user_id,
                DailyFocusAggregate.focus_date >= week_start,
                DailyFocusAggregate.focus_date <= week_end,
            )
        )
        day_map: dict[int, int] = {}
        for drow in days_result.all():
            iso_weekday = drow.focus_date.isoweekday()
            day_map[iso_weekday] = drow.total_credited_minutes * 60

        per_day = [day_map.get(i, 0) for i in range(1, 8)]

        return {
            "week_start": week_start,
            "total_seconds": total_seconds,
            "per_day": per_day,
        }

    async def _best_month(self) -> Optional[dict]:
        month_start_expr = func.date_trunc("month", DailyFocusAggregate.focus_date).cast(
            DailyFocusAggregate.focus_date.type
        )
        result = await self._session.execute(
            select(
                month_start_expr.label("month_start"),
                func.sum(DailyFocusAggregate.total_credited_minutes).label("total_minutes"),
            )
            .where(DailyFocusAggregate.user_id == self._user_id)
            .group_by(month_start_expr)
            .order_by(func.sum(DailyFocusAggregate.total_credited_minutes).desc())
            .limit(1)
        )
        row = result.first()
        if row is None or row.total_minutes == 0:
            return None

        month_start: date = row.month_start
        total_seconds = int(row.total_minutes) * 60
        month_str = month_start.strftime("%Y-%m")

        last_day = calendar.monthrange(month_start.year, month_start.month)[1]
        month_end = date(month_start.year, month_start.month, last_day)

        days_result = await self._session.execute(
            select(
                DailyFocusAggregate.focus_date,
                DailyFocusAggregate.total_credited_minutes,
            ).where(
                DailyFocusAggregate.user_id == self._user_id,
                DailyFocusAggregate.focus_date >= month_start,
                DailyFocusAggregate.focus_date <= month_end,
            )
        )
        day_map: dict[date, int] = {}
        for drow in days_result.all():
            day_map[drow.focus_date] = drow.total_credited_minutes * 60

        heatmap = [[0] * 7 for _ in range(5)]
        grid_start = month_start - timedelta(days=month_start.isoweekday() - 1)
        current = month_start
        while current <= month_end:
            week_index = min(4, (current - grid_start).days // 7)
            day_index = current.isoweekday() - 1
            heatmap[week_index][day_index] = day_map.get(current, 0)
            current += timedelta(days=1)

        return {
            "month": month_str,
            "total_seconds": total_seconds,
            "heatmap": heatmap,
        }
