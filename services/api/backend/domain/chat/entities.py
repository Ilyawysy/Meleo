from __future__ import annotations

import enum
from datetime import datetime
from typing import Optional
import uuid

from sqlalchemy import String, Text, DateTime, ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID as PGUUID

from backend.infrastructure.database.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class ChatRole(str, enum.Enum):
    user = "user"
    assistant = "assistant"
    system = "system"


class ChatThread(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "chat_threads"

    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    # Optional metadata
    metadata_: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Relationship to messages
    messages: Mapped[list[ChatMessage]] = relationship(
        "ChatMessage",
        back_populates="thread",
        cascade="all, delete-orphan",
        order_by="ChatMessage.created_at"
    )


class ChatMessage(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "chat_messages"

    thread_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("chat_threads.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    role: Mapped[ChatRole] = mapped_column(String(20), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    # Optional metadata (e.g., token count, model used)
    metadata_: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    # Order of message in thread
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")

    # Relationship back to thread
    thread: Mapped[ChatThread] = relationship("ChatThread", back_populates="messages")
