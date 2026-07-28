from __future__ import annotations

import enum
import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import Date, DateTime, Enum, Integer, String, ForeignKey, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.infrastructure.database.base import Base, TimestampMixin, UUIDPrimaryKeyMixin

# FocusRoom imported for relationships (lazy to avoid circular import at module load)
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from backend.domain.focus_rooms.entities import FocusRoom

from backend.domain.focus_rooms import entities as _focus_rooms_entities  # noqa: F401  # register FocusRoom in mapper registry
from backend.domain.focus_rooms import task_entities as _focus_rooms_task_entities  # noqa: F401  # register Task in mapper registry
from backend.domain.focus_rooms import checklist_entities as _focus_rooms_checklist_entities  # noqa: F401  # register ChecklistItem in mapper registry


class ShopItemCategory(str, enum.Enum):
    hat = "hat"
    top = "top"
    bottom = "bottom"
    shoes = "shoes"
    accessory = "accessory"
    theme = "theme"
    freeze = "freeze"
    aura = "aura"
    skin = "skin"
    environment = "environment"


class FocusSessionStatus(str, enum.Enum):
    created = "created"
    running = "running"
    finished = "finished"
    cancelled = "cancelled"


class ShopItem(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "shop_items"

    name: Mapped[str] = mapped_column(String(255), nullable=False)
    category: Mapped[ShopItemCategory] = mapped_column(
        Enum(ShopItemCategory, name="shop_item_category"), nullable=False
    )
    price: Mapped[int] = mapped_column(Integer, nullable=False)
    required_level: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )


class UserShopItem(Base, UUIDPrimaryKeyMixin):
    __tablename__ = "user_shop_items"
    __table_args__ = (
        UniqueConstraint("user_id", "item_id", name="uq_user_shop_items_user_id_item_id"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, index=True)
    item_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("shop_items.id"), nullable=False, index=True
    )
    purchased_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    item: Mapped[ShopItem] = relationship("ShopItem")


class UserBalance(Base, TimestampMixin):
    __tablename__ = "user_balance"

    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True)
    coins: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")


class FocusSession(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "focus_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, index=True)
    planned_duration_sec: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[FocusSessionStatus] = mapped_column(
        Enum(FocusSessionStatus, name="focus_session_status"),
        nullable=False,
        default=FocusSessionStatus.created,
        server_default="created",
    )
    active_elapsed_sec: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    last_state_change_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    room_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("focus_rooms.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    task_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True
    )
    earned_coins: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    credited_minutes: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    earned_xp: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    # v0.10.2
    session_day: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    undo_deadline_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    room: Mapped["FocusRoom"] = relationship("FocusRoom", back_populates="sessions")
    segments: Mapped[list["FocusTaskSegment"]] = relationship(
        "FocusTaskSegment", back_populates="session", cascade="all, delete-orphan"
    )


class FocusTaskSegment(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "focus_task_segments"

    session_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("focus_sessions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    task_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        nullable=False,
        index=True,
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    session: Mapped["FocusSession"] = relationship("FocusSession", back_populates="segments")


class UserActiveItem(Base, TimestampMixin):
    __tablename__ = "user_active_items"
    __table_args__ = (
        UniqueConstraint("user_id", "category", name="uq_user_active_items_user_category"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, index=True)
    category: Mapped[str] = mapped_column(String(50), nullable=False)
    item_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("shop_items.id"), nullable=False
    )

    item: Mapped[ShopItem] = relationship("ShopItem")
