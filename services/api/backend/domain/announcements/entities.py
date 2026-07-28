from __future__ import annotations

from datetime import datetime
from typing import Optional
import uuid

from sqlalchemy import String, Text, DateTime, Boolean, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID as PGUUID, ARRAY

from backend.infrastructure.database.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class DeveloperAnnouncement(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """Announcements from developers to users (e.g., new features, maintenance notices)."""

    __tablename__ = "developer_announcements"

    title: Mapped[str] = mapped_column(String(255), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    # NULL or empty array = show to all users (broadcast)
    # Non-empty array = show only to specified user_ids
    target_user_ids: Mapped[Optional[list[uuid.UUID]]] = mapped_column(
        ARRAY(PGUUID(as_uuid=True)), nullable=True
    )


class UserAnnouncementRead(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """Tracks which users have read which announcements."""

    __tablename__ = "user_announcement_reads"

    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, index=True)
    announcement_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("developer_announcements.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    read_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default="timezone('utc', now())"
    )
