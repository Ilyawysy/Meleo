from __future__ import annotations

import enum
import uuid
from datetime import date, datetime
from typing import Any, Optional

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from backend.infrastructure.database.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class GamificationEventType(str, enum.Enum):
    session_reward = "session_reward"
    streak_reset = "streak_reset"
    streak_increment = "streak_increment"
    recovery_activated = "recovery_activated"
    session_undo = "session_undo"
    shield_spend = "shield_spend"
    shield_recharge = "shield_recharge"


class UserGamificationProfile(Base, TimestampMixin):
    __tablename__ = "user_gamification_profile"

    user_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("users.id"), primary_key=True
    )
    xp: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    streak_current: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )

    # ── Deprecated (kept for backward compat, not used by v0.10.2) ──
    streak_updated_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    mmr: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    goal_minutes: Mapped[int] = mapped_column(
        Integer, nullable=False, default=60, server_default="60"
    )
    scheduled_days_mask: Mapped[int] = mapped_column(
        Integer, nullable=False, default=31, server_default="31"
    )
    fair_play_accepted: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    fair_play_accepted_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # ── v0.10.2 fields ──
    timezone: Mapped[str] = mapped_column(
        String(50), nullable=False, default="UTC", server_default="UTC"
    )
    home_tz: Mapped[str] = mapped_column(
        String(50), nullable=False, default="UTC", server_default="UTC"
    )
    home_tz_set_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    day_cutoff_hour: Mapped[int] = mapped_column(
        Integer, nullable=False, default=4, server_default="4"
    )
    day_cutoff_changed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    plan_minutes_json: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        default='{"1":30,"2":0,"3":30,"4":0,"5":30,"6":0,"7":0}',
        server_default='{"1":30,"2":0,"3":30,"4":0,"5":30,"6":0,"7":0}',
    )
    plan_changed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    recovery_days_remaining: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    consecutive_missed_focus_days: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    coin_remainder: Mapped[float] = mapped_column(
        Float, nullable=False, default=0.0, server_default="0.0"
    )
    minimal_mode: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    streak_finalized_through: Mapped[Optional[date]] = mapped_column(Date, nullable=True)

    # ── Shield (spec 7) ──
    shield_unlocked: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    shield_charges: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    shield_recharge_progress: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )

    # ── Adaptive Plan ──
    plan_hours_per_day: Mapped[Optional[list[int]]] = mapped_column(JSONB, nullable=True)
    plan_hours_changed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    growth_target_hours: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    growth_speed: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    growth_started_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # ── Statistics ──
    # TODO(phase-2): update longest_streak in GamificationService.roll_forward()
    # when streak_current increases. Currently populated only via migration backfill.
    longest_streak: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )

    # ── Appearance ──
    theme_mode: Mapped[str] = mapped_column(
        String(10), nullable=False, default="system", server_default="system"
    )

    # ── Active focus room ──
    active_focus_room_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("focus_rooms.id", ondelete="SET NULL"),
        nullable=True,
    )

    # ── Statistics widget config ──
    stat_widget_config: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # ── Session settings ──
    focus_duration_min: Mapped[int] = mapped_column(
        Integer, nullable=False, default=25, server_default="25"
    )
    short_break_min: Mapped[int] = mapped_column(
        Integer, nullable=False, default=5, server_default="5"
    )
    long_break_min: Mapped[int] = mapped_column(
        Integer, nullable=False, default=15, server_default="15"
    )
    sessions_before_long_break: Mapped[int] = mapped_column(
        Integer, nullable=False, default=4, server_default="4"
    )
    auto_start_break: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    auto_start_next_session: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    adjust_duration_after_session: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )


class DailyFocusAggregate(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "daily_focus_aggregate"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "focus_date", name="uq_daily_focus_aggregate_user_id_focus_date"
        ),
        Index("ix_daily_focus_aggregate_user_date", "user_id", "focus_date"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    focus_date: Mapped[date] = mapped_column(Date, nullable=False)
    total_credited_minutes: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    total_xp_earned: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    total_coins_earned: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    session_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    # v0.10.2
    coin_minutes_used: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    recovery_mode: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)


class GamificationEvent(Base, UUIDPrimaryKeyMixin):
    __tablename__ = "gamification_events"
    __table_args__ = (Index("ix_gamification_events_user_created", "user_id", "created_at"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    session_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("focus_sessions.id"), nullable=True
    )
    event_type: Mapped[GamificationEventType] = mapped_column(
        Enum(GamificationEventType, name="gamification_event_type"), nullable=False
    )
    credited_minutes: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    xp_earned: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    coins_earned: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    multiplier_breakdown: Mapped[Optional[dict[str, Any]]] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
