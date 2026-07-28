from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from backend.infrastructure.database.base import Base, TimestampMixin


class UserSubscription(Base, TimestampMixin):
    __tablename__ = "user_subscriptions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("users.id"), primary_key=True
    )
    tier: Mapped[str] = mapped_column(String(20), default="free", server_default="free")
    activated_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    source: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    chat_messages_used: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    chat_messages_limit: Mapped[Optional[int]] = mapped_column(
        Integer, nullable=True, default=5, server_default="5"
    )
