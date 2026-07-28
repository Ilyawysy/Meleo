from __future__ import annotations

import uuid

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


async def delete_user_data(session: AsyncSession, user_id: uuid.UUID) -> None:
    uid = str(user_id)

    await session.execute(
        text(
            "DELETE FROM focus_task_segments "
            "WHERE session_id IN (SELECT id FROM focus_sessions WHERE user_id = :uid)"
        ),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM gamification_events WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM daily_focus_aggregate WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM user_gamification_profile WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM user_shop_items WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM user_balance WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM focus_sessions WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text(
            "DELETE FROM checklist_items "
            "WHERE task_id IN (SELECT id FROM tasks WHERE user_id = :uid)"
        ),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM tasks WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text(
            "DELETE FROM chat_messages "
            "WHERE thread_id IN (SELECT id FROM chat_threads WHERE user_id = :uid)"
        ),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM chat_threads WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM notifications WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM user_announcement_reads WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM user_state_version WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM idempotency_keys WHERE user_id = :uid"),
        {"uid": uid},
    )
    await session.execute(
        text("DELETE FROM users WHERE id = :uid"),
        {"uid": uid},
    )
