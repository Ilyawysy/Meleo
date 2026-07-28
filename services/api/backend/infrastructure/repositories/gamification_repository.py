from __future__ import annotations

import uuid
from datetime import date
from typing import Optional, Sequence

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.focus.entities import FocusSession
from backend.domain.gamification.entities import (
    DailyFocusAggregate,
    GamificationEvent,
    GamificationEventType,
    UserGamificationProfile,
)
from backend.domain.gamification.repository import GamificationRepository


class SqlAlchemyGamificationRepository(GamificationRepository):
    def __init__(self, session: AsyncSession, user_id: uuid.UUID) -> None:
        self._session = session
        self._user_id = user_id

    # ── Profile ──

    async def get_profile(self) -> UserGamificationProfile | None:
        result = await self._session.execute(
            select(UserGamificationProfile).where(UserGamificationProfile.user_id == self._user_id)
        )
        return result.scalar_one_or_none()

    async def create_profile(self) -> UserGamificationProfile:
        profile = UserGamificationProfile(user_id=self._user_id)
        self._session.add(profile)
        await self._session.flush()
        await self._session.refresh(profile)
        return profile

    async def lock_profile(self) -> UserGamificationProfile | None:
        result = await self._session.execute(
            select(UserGamificationProfile)
            .where(UserGamificationProfile.user_id == self._user_id)
            .with_for_update()
        )
        return result.scalar_one_or_none()

    async def update_profile(self, profile: UserGamificationProfile) -> UserGamificationProfile:
        await self._session.flush()
        await self._session.refresh(profile)
        return profile

    async def get_active_focus_room_id(self) -> Optional[uuid.UUID]:
        result = await self._session.execute(
            select(UserGamificationProfile.active_focus_room_id).where(
                UserGamificationProfile.user_id == self._user_id
            )
        )
        return result.scalar_one_or_none()

    async def set_active_focus_room_id(self, room_id: Optional[uuid.UUID]) -> None:
        profile = await self.get_profile()
        if profile is None:
            profile = await self.create_profile()
        profile.active_focus_room_id = room_id
        await self._session.flush()

    # ── Daily aggregate ──

    async def get_aggregate(self, focus_date: date) -> DailyFocusAggregate | None:
        result = await self._session.execute(
            select(DailyFocusAggregate).where(
                DailyFocusAggregate.user_id == self._user_id,
                DailyFocusAggregate.focus_date == focus_date,
            )
        )
        return result.scalar_one_or_none()

    async def lock_aggregate(self, focus_date: date) -> DailyFocusAggregate | None:
        result = await self._session.execute(
            select(DailyFocusAggregate)
            .where(
                DailyFocusAggregate.user_id == self._user_id,
                DailyFocusAggregate.focus_date == focus_date,
            )
            .with_for_update()
        )
        return result.scalar_one_or_none()

    async def create_aggregate(self, focus_date: date) -> DailyFocusAggregate:
        stmt = (
            pg_insert(DailyFocusAggregate)
            .values(id=uuid.uuid4(), user_id=self._user_id, focus_date=focus_date)
            .on_conflict_do_nothing(
                index_elements=["user_id", "focus_date"],
            )
        )
        await self._session.execute(stmt)
        # Always re-fetch to get the existing or just-inserted row
        result = await self._session.execute(
            select(DailyFocusAggregate).where(
                DailyFocusAggregate.user_id == self._user_id,
                DailyFocusAggregate.focus_date == focus_date,
            )
        )
        return result.scalar_one()

    async def update_aggregate(self, aggregate: DailyFocusAggregate) -> DailyFocusAggregate:
        await self._session.flush()
        await self._session.refresh(aggregate)
        return aggregate

    async def list_aggregates(self, since: date, until: date) -> Sequence[DailyFocusAggregate]:
        result = await self._session.execute(
            select(DailyFocusAggregate)
            .where(
                DailyFocusAggregate.user_id == self._user_id,
                DailyFocusAggregate.focus_date >= since,
                DailyFocusAggregate.focus_date <= until,
            )
            .order_by(DailyFocusAggregate.focus_date.desc())
        )
        return list(result.scalars().all())

    # ── Events ──

    async def create_event(self, event: GamificationEvent) -> GamificationEvent:
        event.user_id = self._user_id
        self._session.add(event)
        await self._session.flush()
        await self._session.refresh(event)
        return event

    async def get_session_reward_event(self, session_id: uuid.UUID) -> GamificationEvent | None:
        stmt = (
            select(GamificationEvent)
            .where(
                GamificationEvent.session_id == session_id,
                GamificationEvent.event_type == GamificationEventType.session_reward,
            )
            .order_by(GamificationEvent.created_at.desc())
            .limit(1)
        )
        result = await self._session.execute(stmt)
        return result.scalars().first()

    # ── Sessions by day ──

    async def get_sessions_by_day_and_statuses(
        self, day: date, statuses: list[str]
    ) -> Sequence[FocusSession]:
        result = await self._session.execute(
            select(FocusSession).where(
                FocusSession.user_id == self._user_id,
                FocusSession.session_day == day,
                FocusSession.status.in_(statuses),
            )
        )
        return list(result.scalars().all())
