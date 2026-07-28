from __future__ import annotations

import uuid
from typing import Sequence
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.chat.entities import ChatThread, ChatMessage
from backend.domain.chat.repository import ChatRepository


class SQLAlchemyChatRepository(ChatRepository):
    def __init__(self, session: AsyncSession, user_id: uuid.UUID) -> None:
        self.session = session
        self._user_id = user_id

    async def create_thread(self, thread: ChatThread) -> ChatThread:
        self.session.add(thread)
        await self.session.flush()
        await self.session.refresh(thread)
        return thread

    async def get_thread(self, thread_id: uuid.UUID) -> ChatThread | None:
        stmt = select(ChatThread).where(
            ChatThread.id == thread_id, ChatThread.user_id == self._user_id
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_threads(
        self, user_id: uuid.UUID, *, limit: int = 20, offset: int = 0
    ) -> tuple[int | None, Sequence[ChatThread]]:
        # Stage 5: avoid COUNT(*) in hot list paths.
        total: int | None = None
        # Data query - используем self._user_id для user-scope
        stmt = (
            select(ChatThread)
            .where(ChatThread.user_id == self._user_id)
            .order_by(ChatThread.updated_at.desc())
            .limit(limit)
            .offset(offset)
        )
        result = await self.session.execute(stmt)
        threads = result.scalars().all()

        return total, threads

    async def update_thread(self, thread: ChatThread) -> ChatThread:
        await self.session.flush()
        await self.session.refresh(thread)
        return thread

    async def delete_thread(self, thread_id: uuid.UUID) -> None:
        # get_thread уже фильтрует по self._user_id, поэтому безопасно
        thread = await self.get_thread(thread_id)
        if thread:
            await self.session.delete(thread)
            await self.session.flush()

    async def create_message(self, message: ChatMessage) -> ChatMessage:
        self.session.add(message)
        await self.session.flush()
        await self.session.refresh(message)
        return message

    async def list_messages(
        self, thread_id: uuid.UUID, *, limit: int = 50, offset: int = 0
    ) -> tuple[int | None, Sequence[ChatMessage]]:
        # Stage 5: avoid COUNT(*) in hot list paths.
        total: int | None = None
        # Data query - JOIN с ChatThread для проверки user-scope
        stmt = (
            select(ChatMessage)
            .join(ChatThread, ChatMessage.thread_id == ChatThread.id)
            .where(ChatMessage.thread_id == thread_id, ChatThread.user_id == self._user_id)
            .order_by(ChatMessage.order.asc())
            .limit(limit)
            .offset(offset)
        )
        result = await self.session.execute(stmt)
        messages = result.scalars().all()

        return total, messages

    async def get_thread_messages(self, thread_id: uuid.UUID) -> Sequence[ChatMessage]:
        # JOIN с ChatThread для проверки user-scope
        stmt = (
            select(ChatMessage)
            .join(ChatThread, ChatMessage.thread_id == ChatThread.id)
            .where(ChatMessage.thread_id == thread_id, ChatThread.user_id == self._user_id)
            .order_by(ChatMessage.order.asc())
        )
        result = await self.session.execute(stmt)
        return result.scalars().all()
