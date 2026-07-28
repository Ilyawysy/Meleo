from __future__ import annotations

import time
import uuid
from typing import Callable

import structlog.contextvars
from fastapi import HTTPException, Request, Response
from backend.infrastructure.logging import get_logger
from backend.infrastructure.token_bucket import RateLimitBackendUnavailableError


async def request_id_middleware(request: Request, call_next: Callable):
    request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())

    # Set request_id in contextvars FIRST, so it's available for all subsequent logs
    structlog.contextvars.clear_contextvars()
    structlog.contextvars.bind_contextvars(
        request_id=request_id,
        source="app",  # App-level logs (domain events/errors)
    )

    start = time.perf_counter()
    response: Response | None = None  # Инициализируем как None
    try:
        response = await call_next(request)
    finally:
        duration_ms = int((time.perf_counter() - start) * 1000)
        logger = get_logger("request").bind(source="access")
        status_code = getattr(response, "status_code", 500) if response else 500

        # Calculate request/response sizes
        bytes_in = request.headers.get("content-length")
        bytes_in = int(bytes_in) if bytes_in else 0

        # Get response size from Content-Length header if available
        bytes_out = 0
        if response:
            content_length = response.headers.get("content-length")
            bytes_out = int(content_length) if content_length else 0

        # Generate short request ID
        req_short = request_id[:8] if len(request_id) > 8 else request_id

        # Получаем user_id/supabase_user_id только из верифицированного auth-контекста
        context_vars = structlog.contextvars.get_contextvars()
        internal_user_id = context_vars.get("user_id")
        verified_supabase_user_id = context_vars.get("supabase_user_id")

        if request.url.path != "/metrics":
            logger.info(
                "request_completed",
                request_id=request_id,
                req_short=req_short,
                supabase_user_id=verified_supabase_user_id,
                user_id=str(internal_user_id) if internal_user_id else None,
                method=request.method,
                route=request.url.path,
                path=request.url.path,  # Оставляем для обратной совместимости
                status_code=status_code,
                status=status_code,  # Оставляем для обратной совместимости
                duration_ms=duration_ms,
                bytes_in=bytes_in,
                bytes_out=bytes_out,
            )
        # Clear context variables after request
        structlog.contextvars.clear_contextvars()

    # Устанавливаем X-Request-ID только если response существует
    if response:
        response.headers["X-Request-ID"] = request_id
        return response

    # Если response не существует (ошибка произошла), возвращаем пустой response
    # Это не должно происходить, но на всякий случай
    return Response(status_code=500)


_HEALTH_PATHS = frozenset({"/", "/health", "/metrics"})

_AUTH_PATHS = frozenset({"/api/v1/auth/register", "/api/v1/auth/logout"})
_ROUTE_LEVEL_RATE_LIMIT_PATHS = frozenset({"/api/v1/sync"})


async def rate_limit_middleware(request: Request, call_next: Callable):
    """
    Redis-based token bucket rate limiting.
    Falls back to allow request only if Redis backend is unavailable.
    """
    from backend.infrastructure.config import settings

    # LOADTEST_MODE: bypass rate limiting entirely (dev only)
    if settings.LOADTEST_MODE and settings.ENV == "dev":
        return await call_next(request)

    path = request.url.path

    # Skip middleware-level limits for health/metrics and route-level rate limited endpoints
    if path in _HEALTH_PATHS or path in _ROUTE_LEVEL_RATE_LIMIT_PATHS:
        return await call_next(request)

    try:
        from backend.infrastructure.rate_limit import rate_limit_auth, rate_limit_default

        if path in _AUTH_PATHS:
            await rate_limit_auth(request)
        else:
            await rate_limit_default(request)
    except HTTPException:
        raise
    except RateLimitBackendUnavailableError as exc:
        # Redis unavailable — fail open (allow request), log warning
        logger = get_logger("rate_limit")
        logger.warning("rate_limit_redis_unavailable", path=path, error=str(exc))

    return await call_next(request)


