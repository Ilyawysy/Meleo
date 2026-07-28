from __future__ import annotations

import enum
import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.infrastructure.database.base import Base, TimestampMixin, UUIDPrimaryKeyMixin

if TYPE_CHECKING:
    from backend.domain.focus_rooms.entities import FocusRoom
    from backend.domain.focus_rooms.checklist_entities import ChecklistItem


class TaskStatus(str, enum.Enum):
    NOT_DONE = "not_done"
    DONE = "done"


class Task(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "tasks"
    __table_args__ = (
        Index("ix_tasks_room_sort", "room_id", "sort_order"),
        Index("ix_tasks_user_updated", "user_id", "updated_at", "id"),
    )

    room_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("focus_rooms.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[TaskStatus] = mapped_column(
        Enum(TaskStatus, name="task_status", values_callable=lambda e: [m.value for m in e]),
        nullable=False,
        default=TaskStatus.NOT_DONE,
        server_default="not_done",
    )
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    deleted: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )

    room: Mapped[FocusRoom] = relationship("FocusRoom", back_populates="tasks")
    checklist_items: Mapped[list[ChecklistItem]] = relationship(
        "ChecklistItem", back_populates="task", cascade="all, delete-orphan"
    )
