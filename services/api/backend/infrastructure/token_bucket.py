from __future__ import annotations

import time

from fastapi import HTTPException

from backend.infrastructure.redis_client import redis_coordination

TOKEN_BUCKET_SCRIPT = """
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local rate = tonumber(ARGV[2])  -- tokens per second
local now = tonumber(ARGV[3])
local requested = tonumber(ARGV[4])

-- Get current state
local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
local tokens = tonumber(bucket[1])
local last_refill = tonumber(bucket[2])

-- First request or expired
if not tokens or not last_refill then
    tokens = capacity
    last_refill = now
end

-- Refill tokens based on elapsed time
local elapsed = now - last_refill
local refill = math.floor(elapsed * rate)
if refill > 0 then
    tokens = math.min(capacity, tokens + refill)
    last_refill = now
end

-- Try consume
if tokens >= requested then
    tokens = tokens - requested
    redis.call('HMSET', key, 'tokens', tokens, 'last_refill', last_refill)
    redis.call('EXPIRE', key, 120)
    return 1  -- allowed
else
    return 0  -- denied
end
"""


class RateLimitBackendUnavailableError(Exception):
    """Raised when Redis backend is unavailable for rate-limit checks."""


def _is_redis_backend_error(exc: Exception) -> bool:
    exc_type = type(exc)
    if exc_type.__module__.startswith("redis"):
        return True
    return exc_type.__name__ in {
        "RedisError",
        "ConnectionError",
        "TimeoutError",
        "BusyLoadingError",
    }


class TokenBucketLimiter:
    def __init__(self) -> None:
        self._script = None

    async def _get_script(self):
        if not self._script:
            self._script = redis_coordination.register_script(TOKEN_BUCKET_SCRIPT)
        return self._script

    async def check(self, key: str, capacity: int, rate: float, cost: int = 1) -> bool:
        try:
            script = await self._get_script()
            now = time.time()
            result = await script(
                keys=[f"ratelimit:tb:{key}"],
                args=[capacity, rate, now, cost],
            )
            return result == 1
        except Exception as exc:
            if _is_redis_backend_error(exc):
                raise RateLimitBackendUnavailableError("redis coordination unavailable") from exc
            raise

    async def check_or_raise(
        self,
        key: str,
        capacity: int,
        rate: float,
        cost: int = 1,
        retry_after: int = 10,
    ) -> None:
        allowed = await self.check(key, capacity, rate, cost)
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail="Rate limit exceeded",
                headers={"Retry-After": str(retry_after)},
            )


token_bucket = TokenBucketLimiter()
