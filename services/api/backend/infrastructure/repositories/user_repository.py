from __future__ import annotations

from typing import Optional
import uuid

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.users.entities import User
from backend.domain.users.repository import UserRepository


class SqlAlchemyUserRepository(UserRepository):
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(self, user: User) -> User:
        self._session.add(user)
        await self._session.flush()
        await self._session.refresh(user)
        return user

    async def get_by_id(self, user_id: uuid.UUID) -> Optional[User]:
        result = await self._session.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()

    async def get_by_supabase_user_id(self, supabase_user_id: uuid.UUID) -> Optional[User]:
        result = await self._session.execute(
            select(User).where(User.supabase_user_id == supabase_user_id)
        )
        return result.scalar_one_or_none()

    async def update(self, user: User) -> User:
        await self._session.flush()
        await self._session.refresh(user)
        return user

    async def mark_onboarding_completed(self, user_id: uuid.UUID) -> bool:
        stmt = (
            update(User)
            .where(User.id == user_id, User.onboarding_completed_at.is_(None))
            .values(onboarding_completed_at=func.now())
            .execution_options(synchronize_session="fetch")
        )
        result = await self._session.execute(stmt)
        await self._session.flush()
        return result.rowcount > 0
