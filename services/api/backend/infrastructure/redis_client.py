from __future__ import annotations

from redis.asyncio import Redis

from backend.infrastructure.config import settings
from backend.infrastructure.logging import get_logger

logger = get_logger("redis")

# Coordination Redis: noeviction (rate limit, semaphore — never evicts keys)
redis_coordination = Redis(
    host=settings.REDIS_COORDINATION_HOST,
    port=settings.REDIS_COORDINATION_PORT,
    db=0,
    decode_responses=True,
    socket_timeout=5.0,
    socket_connect_timeout=5.0,
)

# Cache Redis: allkeys-lru (ETag, cursor, gamification — safe to evict)
redis_cache = Redis(
    host=settings.REDIS_CACHE_HOST,
    port=settings.REDIS_CACHE_PORT,
    db=0,
    decode_responses=True,
    socket_timeout=5.0,
    socket_connect_timeout=5.0,
)


async def check_redis_health() -> dict[str, bool]:
    """Check connectivity of both Redis instances."""
    result: dict[str, bool] = {}
    try:
        await redis_coordination.ping()
        result["coordination"] = True
    except Exception as e:
        logger.error("redis_coordination_health_failed", error=str(e))
        result["coordination"] = False

    try:
        await redis_cache.ping()
        result["cache"] = True
    except Exception as e:
        logger.error("redis_cache_health_failed", error=str(e))
        result["cache"] = False

    return result
