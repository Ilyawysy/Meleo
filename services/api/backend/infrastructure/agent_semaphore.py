from __future__ import annotations

import time
import uuid

import redis.exceptions
from fastapi import HTTPException

from backend.infrastructure.config import settings
from backend.infrastructure.logging import get_logger
from backend.infrastructure.redis_client import redis_coordination

logger = get_logger("agent.semaphore")

MAX_GLOBAL_JOBS = 200
MAX_USER_JOBS = 1
JOB_EXPIRY_SECONDS = 15 * 60  # 15 minutes (safety net for leaked slots)
JOB_POLL_TTL_SECONDS = 3600  # Keep owner mapping while job result is pollable

ACQUIRE_SLOT_SCRIPT = """
local global_zset = KEYS[1]
local user_zset = KEYS[2]
local job_key = KEYS[3]
local max_global = tonumber(ARGV[1])
local max_user = tonumber(ARGV[2])
local user_id = ARGV[3]
local job_id = ARGV[4]
local expire_at = tonumber(ARGV[5])
local now = tonumber(ARGV[6])

-- 1. Cleanup expired jobs
redis.call('ZREMRANGEBYSCORE', global_zset, '-inf', now)
redis.call('ZREMRANGEBYSCORE', user_zset, '-inf', now)

-- 2. Check capacity
local global_count = redis.call('ZCARD', global_zset)
if global_count >= max_global then
    return redis.error_reply('global_limit')
end

local user_count = redis.call('ZCARD', user_zset)
if user_count >= max_user then
    return redis.error_reply('user_limit')
end

-- 3. Acquire slot
redis.call('ZADD', global_zset, expire_at, job_id)
redis.call('ZADD', user_zset, expire_at, job_id)
redis.call('SETEX', job_key, 900, user_id)

return 'ok'
"""

RELEASE_SLOT_SCRIPT = """
local global_zset = KEYS[1]
local user_zset = KEYS[2]
local job_key = KEYS[3]
local job_id = ARGV[1]
local poll_ttl = tonumber(ARGV[2])

local user_id = redis.call('GET', job_key)
if not user_id then
    return 'not_found'
end

redis.call('ZREM', global_zset, job_id)
redis.call('ZREM', user_zset, job_id)
if poll_ttl and poll_ttl > 0 then
    redis.call('EXPIRE', job_key, poll_ttl)
else
    redis.call('DEL', job_key)
end

return 'ok'
"""


class AgentSemaphore:
    def __init__(self) -> None:
        self._acquire_script = None
        self._release_script = None

    async def _get_scripts(self):
        if not self._acquire_script:
            self._acquire_script = redis_coordination.register_script(ACQUIRE_SLOT_SCRIPT)
        if not self._release_script:
            self._release_script = redis_coordination.register_script(RELEASE_SLOT_SCRIPT)
        return self._acquire_script, self._release_script

    async def acquire(self, user_id: uuid.UUID, job_id: str) -> None:
        """Acquire a semaphore slot for the given user and job.

        Raises HTTPException 503 if global limit reached, 429 if user limit reached.
        """
        acquire_script, _ = await self._get_scripts()
        now = time.time()
        expire_at = now + JOB_EXPIRY_SECONDS

        try:
            result = await acquire_script(
                keys=[
                    "agent:global:jobs",
                    f"agent:user:{user_id}:jobs",
                    f"agent:job:{job_id}:user",
                ],
                args=[
                    MAX_GLOBAL_JOBS,
                    MAX_USER_JOBS,
                    str(user_id),
                    job_id,
                    expire_at,
                    now,
                ],
            )
            if result != "ok":
                raise RuntimeError(f"Unexpected acquire result: {result}")

        except redis.exceptions.ResponseError as e:
            err = str(e)
            if "global_limit" in err:
                logger.warning("agent_global_limit_reached")
                raise HTTPException(503, "Agent service overloaded, try again later")
            elif "user_limit" in err:
                logger.info("agent_user_limit_reached", user_id=str(user_id))
                raise HTTPException(429, "You already have an active agent job")
            else:
                raise

    async def get_job_user_id(self, job_id: str) -> str | None:
        """Return owner user_id for a job, if mapping is still available."""
        user_id_str = await redis_coordination.get(f"agent:job:{job_id}:user")
        if not user_id_str:
            return None
        return str(user_id_str)

    async def release(self, job_id: str, keep_owner_mapping: bool = True) -> None:
        """Release a semaphore slot (async version for FastAPI context)."""
        _, release_script = await self._get_scripts()

        user_id_str = await redis_coordination.get(f"agent:job:{job_id}:user")
        if not user_id_str:
            return

        poll_ttl = JOB_POLL_TTL_SECONDS if keep_owner_mapping else 0
        await release_script(
            keys=[
                "agent:global:jobs",
                f"agent:user:{user_id_str}:jobs",
                f"agent:job:{job_id}:user",
            ],
            args=[job_id, poll_ttl],
        )

    def release_sync(self, job_id: str) -> None:
        """Release a semaphore slot (sync version for Celery worker context)."""
        from redis import Redis as SyncRedis

        sync_redis = SyncRedis(
            host=settings.REDIS_COORDINATION_HOST,
            port=settings.REDIS_COORDINATION_PORT,
            db=0,
            decode_responses=True,
        )

        try:
            user_id_str = sync_redis.get(f"agent:job:{job_id}:user")
            if not user_id_str:
                return

            sync_redis.eval(
                RELEASE_SLOT_SCRIPT,
                3,
                "agent:global:jobs",
                f"agent:user:{user_id_str}:jobs",
                f"agent:job:{job_id}:user",
                job_id,
                JOB_POLL_TTL_SECONDS,
            )
        except Exception as e:
            logger.error("semaphore_release_sync_failed", job_id=job_id, error=str(e))
        finally:
            sync_redis.close()


semaphore = AgentSemaphore()
