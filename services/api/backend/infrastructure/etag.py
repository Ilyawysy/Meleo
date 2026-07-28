from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.users.state_version import UserStateVersion
from backend.infrastructure.logging import get_logger
from backend.infrastructure.redis_client import redis_cache

_ETAG_CACHE_TTL_SECONDS = 300
logger = get_logger("etag")


async def get_user_etag(
    session: AsyncSession,
    user_id: uuid.UUID,
) -> str:
    """Compute composite ETag from user state versions (O(1) PK lookup).

    Returns ETag string like: "5-12-7"
    (notifications - messages - focus)
    """
    user_row = await session.get(UserStateVersion, user_id)

    notifications_v = user_row.notifications_version if user_row else 0
    messages_v = user_row.messages_version if user_row else 0
    focus_v = user_row.focus_version if user_row else 0

    cache_key = f"sync:etag:{user_id}:{notifications_v}:{messages_v}:{focus_v}"
    try:
        cached = await redis_cache.get(cache_key)
        if cached:
            return cached
    except Exception as exc:
        logger.warning("etag_cache_read_failed", error=str(exc), user_id=str(user_id))

    etag = f'"{notifications_v}-{messages_v}-{focus_v}"'

    try:
        await redis_cache.set(cache_key, etag, ex=_ETAG_CACHE_TTL_SECONDS, nx=True)
    except Exception as exc:
        logger.warning("etag_cache_write_failed", error=str(exc), user_id=str(user_id))

    return etag


def etag_matches(request_etag: str | None, current_etag: str) -> bool:
    """Check if client's If-None-Match header matches current ETag."""
    if not request_etag:
        return False
    # If-None-Match may contain multiple ETags separated by commas
    client_etags = [e.strip() for e in request_etag.split(",")]
    return current_etag in client_etags or "*" in client_etags
