from __future__ import annotations

import enum
import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, Enum, Index, Integer, String
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.infrastructure.database.base import Base, TimestampMixin, UUIDPrimaryKeyMixin

if TYPE_CHECKING:
    from backend.domain.focus_rooms.task_entities import Task
    from backend.domain.focus.entities import FocusSession


class FocusRoomType(str, enum.Enum):
    REGULAR = "regular"
    SPRINT = "sprint"


class FocusRoom(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "focus_rooms"
    __table_args__ = (
        Index("ix_focus_rooms_user_active", "user_id", "archived", "sort_order"),
        Index("ix_focus_rooms_user_updated", "user_id", "updated_at", "id"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    color: Mapped[str] = mapped_column(String(16), nullable=False)
    type: Mapped[FocusRoomType] = mapped_column(
        Enum(FocusRoomType, name="focus_room_type", values_callable=lambda e: [m.value for m in e]),
        nullable=False,
        default=FocusRoomType.REGULAR,
        server_default="regular",
    )
    archived: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    sprint_goal: Mapped[str | None] = mapped_column(String(255), nullable=True)
    sprint_deadline: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    sprint_total_hours: Mapped[int | None] = mapped_column(Integer, nullable=True)
    focus_duration_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    break_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    deleted: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )

    tasks: Mapped[list[Task]] = relationship(
        "Task", back_populates="room", cascade="all, delete-orphan"
    )
    sessions: Mapped[list[FocusSession]] = relationship(
        "FocusSession", back_populates="room", cascade="all, delete-orphan"
    )
