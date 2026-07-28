from __future__ import annotations

import uuid
from datetime import datetime
from typing import Sequence

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.notifications.entities import Notification
from backend.domain.notifications.repository import NotificationRepository


class SqlAlchemyNotificationRepository(NotificationRepository):
    def __init__(self, session: AsyncSession, user_id: uuid.UUID) -> None:
        self._session = session
        self._user_id = user_id

    async def create(self, notification: Notification) -> Notification:
        notification.user_id = self._user_id
        self._session.add(notification)
        await self._session.flush()
        return notification

    async def get(self, notification_id: uuid.UUID) -> Notification | None:
        result = await self._session.execute(
            select(Notification).where(
                Notification.id == notification_id,
                Notification.user_id == self._user_id,
                Notification.deleted.is_(False),
            )
        )
        return result.scalar_one_or_none()

    async def list(self, *, limit: int = 20, offset: int = 0) -> Sequence[Notification]:
        result = await self._session.execute(
            select(Notification)
            .where(Notification.user_id == self._user_id, Notification.deleted.is_(False))
            .order_by(Notification.time.asc())
            .limit(limit)
            .offset(offset)
        )
        return list(result.scalars().all())

    async def list_paginated(
        self,
        *,
        limit: int = 20,
        offset: int = 0,
        time_before: datetime | None = None,
        time_after: datetime | None = None,
        sort_by: str | None = None,
        sort_dir: str | None = None,
    ) -> tuple[int | None, Sequence[Notification]]:
        conditions = [Notification.deleted.is_(False), Notification.user_id == self._user_id]
        if time_before is not None:
            conditions.append(Notification.time <= time_before)
        if time_after is not None:
            conditions.append(Notification.time >= time_after)

        where_clause = and_(*conditions) if conditions else None

        # Stage 5: avoid COUNT(*) in hot list paths.
        total: int | None = None

        order_col = Notification.time
        if sort_by == "created_at":
            order_col = Notification.created_at
        if (sort_dir or "asc").lower() == "desc":
            order = order_col.desc()
        else:
            order = order_col.asc()

        stmt = select(Notification)
        if where_clause is not None:
            stmt = stmt.where(where_clause)
        stmt = stmt.order_by(order).limit(limit).offset(offset)

        rows = await self._session.execute(stmt)
        items = list(rows.scalars().all())

        return total, items

    async def update(self, notification: Notification) -> Notification:
        await self._session.flush()
        await self._session.refresh(notification)
        return notification

    async def delete(self, notification_id: uuid.UUID) -> None:
        # Soft delete
        result = await self._session.execute(
            select(Notification).where(
                Notification.id == notification_id, Notification.user_id == self._user_id
            )
        )
        n = result.scalar_one_or_none()
        if n is not None:
            n.deleted = True
            await self._session.flush()
