from __future__ import annotations

import uuid

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql import func

from backend.domain.subscriptions.entities import UserSubscription


class SubscriptionRepository:
    def __init__(self, db: AsyncSession) -> None:
        self._db = db

    async def get_by_user_id(self, user_id: uuid.UUID) -> UserSubscription | None:
        result = await self._db.execute(
            select(UserSubscription).where(UserSubscription.user_id == user_id)
        )
        return result.scalar_one_or_none()

    async def upsert(self, user_id: uuid.UUID, **kwargs) -> UserSubscription:
        sub = await self.get_by_user_id(user_id)
        if sub is None:
            sub = UserSubscription(user_id=user_id, **kwargs)
            self._db.add(sub)
            await self._db.flush()
            await self._db.refresh(sub)
        else:
            for key, value in kwargs.items():
                setattr(sub, key, value)
            await self._db.flush()
            await self._db.refresh(sub)
        return sub

    async def increment_chat_counter(self, user_id: uuid.UUID) -> int:
        result = await self._db.execute(
            update(UserSubscription)
            .where(UserSubscription.user_id == user_id)
            .values(
                chat_messages_used=UserSubscription.chat_messages_used + 1,
                updated_at=func.now(),
            )
            .returning(UserSubscription.chat_messages_used)
        )
        row = result.scalar_one_or_none()
        if row is not None:
            await self._db.flush()
            return row
        # No subscription row yet — create one then increment
        await self.upsert(user_id)
        return await self.increment_chat_counter(user_id)
