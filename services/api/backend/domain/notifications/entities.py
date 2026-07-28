from __future__ import annotations

from datetime import datetime
import uuid

from sqlalchemy import String, DateTime, Boolean, Enum
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID as PGUUID

import enum

from backend.infrastructure.database.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class NotificationRecurrence(str, enum.Enum):
    none = "none"
    daily = "daily"
    weekly = "weekly"


class Notification(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "notifications"

    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    recurrence: Mapped[NotificationRecurrence] = mapped_column(
        Enum(NotificationRecurrence, name="task_recurrence"),
        default=NotificationRecurrence.none,
        nullable=False,
    )
    # Soft delete flag
    deleted: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
