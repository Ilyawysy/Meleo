from __future__ import annotations

import uuid
from datetime import datetime
from typing import Sequence

from backend.domain.chat.entities import ChatThread, ChatMessage, ChatRole
from backend.domain.chat.repository import ChatRepository


class ChatService:
    def __init__(self, repository: ChatRepository) -> None:
        self.repository = repository

    async def create_thread(
        self, user_id: uuid.UUID, title: str, metadata: str | None = None
    ) -> ChatThread:
        """Create a new chat thread for a user."""
        thread = ChatThread(user_id=user_id, title=title, metadata_=metadata)
        return await self.repository.create_thread(thread)

    async def get_thread(self, thread_id: uuid.UUID) -> ChatThread | None:
        """Get a chat thread by ID."""
        return await self.repository.get_thread(thread_id)

    async def list_user_threads(
        self, user_id: uuid.UUID, limit: int = 20, offset: int = 0
    ) -> tuple[int | None, Sequence[ChatThread]]:
        """List chat threads for a user."""
        return await self.repository.list_threads(user_id, limit=limit, offset=offset)

    async def delete_thread(self, thread_id: uuid.UUID) -> None:
        """Delete a chat thread and all its messages."""
        await self.repository.delete_thread(thread_id)

    async def add_message(
        self, thread_id: uuid.UUID, role: ChatRole, content: str, metadata: str | None = None
    ) -> ChatMessage:
        """Add a message to a chat thread."""
        # Verify thread exists
        thread = await self.repository.get_thread(thread_id)
        if not thread:
            raise ValueError(f"Thread {thread_id} not found")

        # Get current max order
        existing_messages = await self.repository.get_thread_messages(thread_id)
        order = max((msg.order for msg in existing_messages), default=0) + 1

        message = ChatMessage(
            thread_id=thread_id, role=role, content=content, metadata_=metadata, order=order
        )

        # Update thread's updated_at
        thread.updated_at = datetime.utcnow()
        await self.repository.update_thread(thread)

        return await self.repository.create_message(message)

    async def get_thread_messages(
        self, thread_id: uuid.UUID, limit: int = 50, offset: int = 0
    ) -> tuple[int | None, Sequence[ChatMessage]]:
        """Get messages for a thread."""
        return await self.repository.list_messages(thread_id, limit=limit, offset=offset)

