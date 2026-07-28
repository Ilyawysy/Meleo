from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Optional

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from backend.domain.chat.entities import ChatMessage, ChatThread
from backend.domain.focus.entities import (
    FocusSession,
    FocusTaskSegment,
    UserBalance,
    UserShopItem,
)
from backend.domain.focus_rooms.checklist_entities import ChecklistItem
from backend.domain.focus_rooms.entities import FocusRoom
from backend.domain.focus_rooms.task_entities import Task
from backend.domain.gamification.calculator import (
    compute_xp_level,
    parse_plan_minutes,
    subcoins_to_display,
    xp_to_next_level,
)
from backend.domain.gamification.entities import UserGamificationProfile
from backend.domain.notifications.entities import Notification
from backend.domain.subscriptions.repository import SubscriptionRepository
from backend.domain.subscriptions.service import SubscriptionService
from backend.domain.sync.cursor import DomainCursor


async def get_notification_changes(
    session: AsyncSession,
    user_id: uuid.UUID,
    cursor: DomainCursor,
    limit: int,
) -> tuple[Sequence[Notification], DomainCursor | None]:
    """Fetch notification changes after cursor using (updated_at, id) tie-breaker."""
    stmt = (
        select(Notification)
        .where(
            Notification.user_id == user_id,
            or_(
                Notification.updated_at > cursor.updated_at,
                and_(
                    Notification.updated_at == cursor.updated_at,
                    Notification.id > cursor.last_id,
                ),
            ),
        )
        .order_by(Notification.updated_at, Notification.id)
        .limit(limit)
    )

    result = await session.execute(stmt)
    notifications = result.scalars().all()

    if not notifications:
        return [], None

    last = notifications[-1]
    new_cursor = DomainCursor(updated_at=last.updated_at, last_id=last.id)
    return notifications, new_cursor


async def get_message_changes(
    session: AsyncSession,
    user_id: uuid.UUID,
    cursor: DomainCursor,
    limit: int,
) -> tuple[Sequence[ChatMessage], DomainCursor | None]:
    """Fetch message changes after cursor, scoped to user's threads."""
    # Subquery: thread IDs belonging to user
    user_thread_ids = select(ChatThread.id).where(ChatThread.user_id == user_id).scalar_subquery()

    stmt = (
        select(ChatMessage)
        .where(
            ChatMessage.thread_id.in_(user_thread_ids),
            or_(
                ChatMessage.updated_at > cursor.updated_at,
                and_(
                    ChatMessage.updated_at == cursor.updated_at,
                    ChatMessage.id > cursor.last_id,
                ),
            ),
        )
        .order_by(ChatMessage.updated_at, ChatMessage.id)
        .limit(limit)
    )

    result = await session.execute(stmt)
    messages = result.scalars().all()

    if not messages:
        return [], None

    last = messages[-1]
    new_cursor = DomainCursor(updated_at=last.updated_at, last_id=last.id)
    return messages, new_cursor


async def get_focus_session_changes(
    session: AsyncSession,
    user_id: uuid.UUID,
    cursor: DomainCursor,
    limit: int,
) -> tuple[Sequence[FocusSession], DomainCursor | None]:
    """Fetch focus session changes after cursor using (updated_at, id) tie-breaker."""
    stmt = (
        select(FocusSession)
        .where(
            FocusSession.user_id == user_id,
            or_(
                FocusSession.updated_at > cursor.updated_at,
                and_(
                    FocusSession.updated_at == cursor.updated_at,
                    FocusSession.id > cursor.last_id,
                ),
            ),
        )
        .order_by(FocusSession.updated_at, FocusSession.id)
        .limit(limit)
    )

    result = await session.execute(stmt)
    sessions = result.scalars().all()

    if not sessions:
        return [], None

    last = sessions[-1]
    new_cursor = DomainCursor(updated_at=last.updated_at, last_id=last.id)
    return sessions, new_cursor


async def get_all_focus_task_segments(
    session: AsyncSession,
    user_id: uuid.UUID,
) -> Sequence[FocusTaskSegment]:
    """Fetch all focus task segments for the user (full snapshot, like checklist_items)."""
    stmt = (
        select(FocusTaskSegment)
        .where(FocusTaskSegment.user_id == user_id)
        .order_by(FocusTaskSegment.started_at)
    )
    result = await session.execute(stmt)
    return result.scalars().all()


# TODO(focus-rooms-refactor Phase 2): get_all_checklist_items removed.
# Will be rewritten in Phase 2 sync router against new FocusRoom model.


@dataclass
class FocusSnapshotData:
    """Read-only focus snapshot (no side-effects like evaluate_pending_days)."""

    balance_coins: float  # display coins
    owned_item_ids: list[str]  # UUIDs of purchased shop items
    shop_items: list[dict]  # deprecated, kept empty for backward compat
    profile: Optional[dict]  # gamification profile fields or None


async def get_focus_snapshot(
    session: AsyncSession,
    user_id: uuid.UUID,
) -> FocusSnapshotData:
    """Return current focus state (balance, shop, profile) without side-effects."""
    # Balance
    balance_row = await session.get(UserBalance, user_id)
    balance_coins = subcoins_to_display(balance_row.coins) if balance_row else 0.0

    # Owned shop item IDs only (catalog fetched separately via GET /shop/catalog)
    owned_stmt = select(UserShopItem.item_id).where(UserShopItem.user_id == user_id)
    owned_result = await session.execute(owned_stmt)
    owned_item_ids = [str(row[0]) for row in owned_result.all()]

    # Gamification profile (raw read, no evaluate_pending_days)
    profile_row = await session.get(UserGamificationProfile, user_id)
    profile = None
    if profile_row:
        level = compute_xp_level(profile_row.xp)
        profile = {
            "xp": profile_row.xp,
            "level": level,
            "xp_to_next_level": xp_to_next_level(profile_row.xp),
            "streak_current": profile_row.streak_current,
            "home_tz": profile_row.home_tz,
            "day_cutoff_hour": profile_row.day_cutoff_hour,
            "plan_minutes": parse_plan_minutes(profile_row.plan_minutes_json),
            "recovery_days_remaining": profile_row.recovery_days_remaining,
            "minimal_mode": profile_row.minimal_mode,
            "streak_finalized_through": (
                profile_row.streak_finalized_through.isoformat()
                if profile_row.streak_finalized_through
                else None
            ),
            "fair_play_accepted": profile_row.fair_play_accepted,
            "coins": balance_coins,
            "shield_unlocked": profile_row.shield_unlocked,
            "shield_charges": profile_row.shield_charges,
            "shield_recharge_progress": profile_row.shield_recharge_progress,
            "recovery_mode": "recovery" if profile_row.recovery_days_remaining > 0 else None,
            "focus_duration_min": profile_row.focus_duration_min,
            "short_break_min": profile_row.short_break_min,
            "long_break_min": profile_row.long_break_min,
            "sessions_before_long_break": profile_row.sessions_before_long_break,
            "auto_start_break": profile_row.auto_start_break,
            "auto_start_next_session": profile_row.auto_start_next_session,
            "adjust_duration_after_session": profile_row.adjust_duration_after_session,
            "stat_widget_config": profile_row.stat_widget_config,
            "active_focus_room_id": (
                str(profile_row.active_focus_room_id) if profile_row.active_focus_room_id else None
            ),
        }

    return FocusSnapshotData(
        balance_coins=balance_coins,
        owned_item_ids=owned_item_ids,
        shop_items=[],  # deprecated
        profile=profile,
    )


async def get_subscription_snapshot(
    session: AsyncSession,
    user_id: uuid.UUID,
) -> dict:
    repo = SubscriptionRepository(session)
    service = SubscriptionService(repo)
    sub = await service.get_subscription(user_id)
    return {
        "tier": sub.tier,
        "chat_messages_used": sub.chat_messages_used,
        "chat_messages_limit": sub.chat_messages_limit,
    }


async def get_focus_room_changes(
    session: AsyncSession,
    user_id: uuid.UUID,
    cursor: DomainCursor,
    limit: int,
) -> tuple[Sequence[FocusRoom], DomainCursor | None]:
    stmt = (
        select(FocusRoom)
        .where(
            FocusRoom.user_id == user_id,
            or_(
                FocusRoom.updated_at > cursor.updated_at,
                and_(
                    FocusRoom.updated_at == cursor.updated_at,
                    FocusRoom.id > cursor.last_id,
                ),
            ),
        )
        .order_by(FocusRoom.updated_at, FocusRoom.id)
        .limit(limit)
    )
    result = await session.execute(stmt)
    rooms = result.scalars().all()
    if not rooms:
        return [], None
    last = rooms[-1]
    new_cursor = DomainCursor(updated_at=last.updated_at, last_id=last.id)
    return rooms, new_cursor


async def get_task_changes(
    session: AsyncSession,
    user_id: uuid.UUID,
    cursor: DomainCursor,
    limit: int,
) -> tuple[Sequence[Task], DomainCursor | None]:
    stmt = (
        select(Task)
        .where(
            Task.user_id == user_id,
            or_(
                Task.updated_at > cursor.updated_at,
                and_(
                    Task.updated_at == cursor.updated_at,
                    Task.id > cursor.last_id,
                ),
            ),
        )
        .order_by(Task.updated_at, Task.id)
        .limit(limit)
    )
    result = await session.execute(stmt)
    tasks = result.scalars().all()
    if not tasks:
        return [], None
    last = tasks[-1]
    new_cursor = DomainCursor(updated_at=last.updated_at, last_id=last.id)
    return tasks, new_cursor


async def get_checklist_item_changes(
    session: AsyncSession,
    user_id: uuid.UUID,
    cursor: DomainCursor,
    limit: int,
) -> tuple[Sequence[ChecklistItem], DomainCursor | None]:
    stmt = (
        select(ChecklistItem)
        .join(Task, ChecklistItem.task_id == Task.id)
        .where(
            Task.user_id == user_id,
            or_(
                ChecklistItem.updated_at > cursor.updated_at,
                and_(
                    ChecklistItem.updated_at == cursor.updated_at,
                    ChecklistItem.id > cursor.last_id,
                ),
            ),
        )
        .order_by(ChecklistItem.updated_at, ChecklistItem.id)
        .limit(limit)
    )
    result = await session.execute(stmt)
    items = result.scalars().all()
    if not items:
        return [], None
    last = items[-1]
    new_cursor = DomainCursor(updated_at=last.updated_at, last_id=last.id)
    return items, new_cursor
