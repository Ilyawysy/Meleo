from __future__ import annotations

from fastapi import HTTPException, Request

from backend.infrastructure.logging import get_logger
from backend.infrastructure.token_bucket import RateLimitBackendUnavailableError, token_bucket

logger = get_logger("rate_limit")


def get_rate_limit_key(
    request: Request,
    user_id: str | None = None,
    *,
    use_device_id: bool = True,
) -> str:
    """Build rate-limit key: prefer verified user_id, then optional device_id, then IP."""
    if user_id:
        return f"user:{user_id}"

    request_user_id = getattr(request.state, "user_id", None)
    if request_user_id:
        return f"user:{request_user_id}"

    if use_device_id:
        device_id = request.headers.get("X-Device-ID")
        if device_id:
            return f"device:{device_id}"

    host = request.client.host if request.client else "unknown"
    return f"ip:{host}"


async def rate_limit_default(request: Request, user_id: str | None = None) -> None:
    """
    Default rate limit for most endpoints.
    60 tokens capacity = 60 req/min max
    1.0 tokens/sec refill = 60 req/min sustained
    Burst: 15 req/10s (covers cold-start: sync + focus + cache refresh)
    """
    # For default limiter, never use client-controlled X-Device-ID as the primary key.
    # Prefer verified user_id when available, otherwise fallback to source IP.
    key = get_rate_limit_key(request, user_id=user_id, use_device_id=False)

    # Main limit: 60/min
    await token_bucket.check_or_raise(
        key=f"main:{key}",
        capacity=60,
        rate=1.0,
        retry_after=60,
    )

    # Burst: 15/10s
    await token_bucket.check_or_raise(
        key=f"burst:{key}",
        capacity=15,
        rate=1.5,
        retry_after=10,
    )


async def rate_limit_sync(request: Request, user_id: str | None = None) -> None:
    """
    Sync endpoint rate limit.
    30 tokens capacity = 30 req/min max
    0.5 tokens/sec refill = 30 req/min sustained
    Burst: 6 req/10s (for pagination)
    """
    key = get_rate_limit_key(request, user_id=user_id, use_device_id=False)

    try:
        # Main limit: 30/min
        await token_bucket.check_or_raise(
            key=f"sync:main:{key}",
            capacity=30,
            rate=0.5,
            retry_after=60,
        )

        # Burst: 6/10s
        await token_bucket.check_or_raise(
            key=f"sync:burst:{key}",
            capacity=6,
            rate=0.6,
            retry_after=10,
        )
    except HTTPException:
        raise
    except RateLimitBackendUnavailableError as exc:
        # /sync must fail-open on Redis outages.
        logger.warning(
            "sync_rate_limit_backend_unavailable",
            error=str(exc),
            key=key,
            path=request.url.path,
        )


async def rate_limit_auth(request: Request) -> None:
    """
    Strict rate limit for auth endpoints.
    5 tokens capacity = 5 req/min max
    ~0.083 tokens/sec refill = 5 req/min sustained
    """
    host = request.client.host if request.client else "unknown"
    key = f"ip:{host}"

    await token_bucket.check_or_raise(
        key=f"auth:{key}",
        capacity=5,
        rate=5.0 / 60.0,
        retry_after=60,
    )


async def rate_limit_agent(request: Request, current_user_id: str | None = None) -> None:
    """
    Strict rate limit for agent endpoints.
    1 token capacity = 1 req/10s max (LLM calls are expensive).
    0.1 tokens/sec refill = 6 req/min sustained.
    """
    key = get_rate_limit_key(request, user_id=current_user_id)

    await token_bucket.check_or_raise(
        key=f"agent:{key}",
        capacity=1,
        rate=0.1,
        retry_after=10,
    )


async def rate_limit_agent_poll(request: Request, user_id: str | None = None) -> None:
    """
    Polling rate limit for agent job status endpoint.
    Allows frequent checks without enabling aggressive flood traffic.
    """
    key = get_rate_limit_key(request, user_id=user_id, use_device_id=False)

    await token_bucket.check_or_raise(
        key=f"agent:poll:{key}",
        capacity=5,
        rate=1.0,
        retry_after=1,
    )
