from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Optional

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from backend.infrastructure.config import settings
from backend.infrastructure.database.session import get_session
from backend.infrastructure.logging import get_logger
from backend.infrastructure.security.auth import is_token_revoked, verify_user_token

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])
logger = get_logger("admin")


async def admin_required(request: Request) -> dict:
    auth = request.headers.get("Authorization") or request.headers.get("authorization")
    if not auth or not auth.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    token = auth.split(" ", 1)[1].strip()

    if is_token_revoked(token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked"
        )

    payload = verify_user_token(token)

    roles: list[str] = payload.get("app_metadata", {}).get("roles", [])
    if "admin" not in roles:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")

    return payload


class PostHogQueryRequest(BaseModel):
    query: str


@router.get("/analytics/overview")
async def analytics_overview(
    _: dict = Depends(admin_required),
    session: AsyncSession = Depends(get_session),
) -> dict[str, Any]:
    try:
        total_users = (await session.execute(text("SELECT COUNT(*) FROM users"))).scalar()

        active_today = (
            await session.execute(
                text(
                    "SELECT COUNT(DISTINCT user_id) FROM focus_sessions"
                    " WHERE session_day = CURRENT_DATE"
                )
            )
        ).scalar()

        active_week = (
            await session.execute(
                text(
                    "SELECT COUNT(DISTINCT user_id) FROM focus_sessions"
                    " WHERE session_day >= CURRENT_DATE - INTERVAL '7 days'"
                )
            )
        ).scalar()

        active_month = (
            await session.execute(
                text(
                    "SELECT COUNT(DISTINCT user_id) FROM focus_sessions"
                    " WHERE session_day >= CURRENT_DATE - INTERVAL '30 days'"
                )
            )
        ).scalar()

        new_today = (
            await session.execute(
                text("SELECT COUNT(*) FROM users WHERE created_at >= CURRENT_DATE")
            )
        ).scalar()

        new_week = (
            await session.execute(
                text(
                    "SELECT COUNT(*) FROM users"
                    " WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'"
                )
            )
        ).scalar()

        return {
            "total_users": total_users,
            "active_today": active_today,
            "active_week": active_week,
            "active_month": active_month,
            "new_today": new_today,
            "new_week": new_week,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error("analytics_overview_error", error=str(e), error_type=type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error"
        )


@router.get("/analytics/tasks")
async def analytics_tasks(
    _: dict = Depends(admin_required),
    session: AsyncSession = Depends(get_session),
    days: int = Query(default=30, ge=1, le=365),
) -> dict[str, Any]:
    try:
        created = (
            await session.execute(
                text(
                    "SELECT COUNT(*) FROM tasks"
                    " WHERE created_at >= CURRENT_DATE - make_interval(days => :days)"
                ).bindparams(days=days)
            )
        ).scalar()

        completed = (
            await session.execute(
                text(
                    "SELECT COUNT(*) FROM tasks"
                    " WHERE status = 'done'"
                    " AND updated_at >= CURRENT_DATE - make_interval(days => :days)"
                ).bindparams(days=days)
            )
        ).scalar()

        rate_row = (
            await session.execute(
                text(
                    "SELECT"
                    " COUNT(*) FILTER (WHERE status = 'done') AS completed,"
                    " COUNT(*) AS total"
                    " FROM tasks WHERE status != 'archived' AND deleted = false"
                )
            )
        ).fetchone()

        completion_rate: float | None = None
        if rate_row and rate_row.total:
            completion_rate = round(rate_row.completed / rate_row.total * 100, 2)

        return {
            "days": days,
            "created_in_period": created,
            "completed_in_period": completed,
            "overall_completion_rate_pct": completion_rate,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error("analytics_tasks_error", error=str(e), error_type=type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error"
        )


@router.get("/analytics/focus")
async def analytics_focus(
    _: dict = Depends(admin_required),
    session: AsyncSession = Depends(get_session),
    days: int = Query(default=30, ge=1, le=365),
) -> dict[str, Any]:
    try:
        row = (
            await session.execute(
                text(
                    "SELECT"
                    " COUNT(*) AS total_sessions,"
                    " AVG(active_elapsed_sec) AS avg_duration_sec,"
                    " COUNT(*) FILTER (WHERE status = 'finished') * 100.0"
                    " / NULLIF(COUNT(*), 0) AS completion_pct,"
                    " SUM(active_elapsed_sec) / 60 AS total_minutes"
                    " FROM focus_sessions"
                    " WHERE created_at >= CURRENT_DATE - make_interval(days => :days)"
                ).bindparams(days=days)
            )
        ).fetchone()

        return {
            "days": days,
            "total_sessions": row.total_sessions if row else 0,
            "avg_duration_sec": round(float(row.avg_duration_sec), 2)
            if row and row.avg_duration_sec is not None
            else None,
            "completion_pct": round(float(row.completion_pct), 2)
            if row and row.completion_pct is not None
            else None,
            "total_minutes": int(row.total_minutes) if row and row.total_minutes is not None else 0,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error("analytics_focus_error", error=str(e), error_type=type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error"
        )


@router.get("/analytics/gamification")
async def analytics_gamification(
    _: dict = Depends(admin_required),
    session: AsyncSession = Depends(get_session),
) -> dict[str, Any]:
    try:
        xp_row = (
            await session.execute(
                text(
                    "SELECT"
                    " AVG(xp) AS avg_xp,"
                    " MAX(xp) AS max_xp,"
                    " PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY xp) AS median_xp"
                    " FROM user_gamification_profile"
                )
            )
        ).fetchone()

        streak_row = (
            await session.execute(
                text(
                    "SELECT"
                    " AVG(streak_current) AS avg_streak,"
                    " MAX(streak_current) AS max_streak"
                    " FROM user_gamification_profile"
                )
            )
        ).fetchone()

        coins_row = (
            await session.execute(
                text("SELECT AVG(coins) AS avg_coins, SUM(coins) AS total_coins FROM user_balance")
            )
        ).fetchone()

        return {
            "xp": {
                "avg": round(float(xp_row.avg_xp), 2)
                if xp_row and xp_row.avg_xp is not None
                else None,
                "max": int(xp_row.max_xp) if xp_row and xp_row.max_xp is not None else None,
                "median": round(float(xp_row.median_xp), 2)
                if xp_row and xp_row.median_xp is not None
                else None,
            },
            "streaks": {
                "avg": round(float(streak_row.avg_streak), 2)
                if streak_row and streak_row.avg_streak is not None
                else None,
                "max": int(streak_row.max_streak)
                if streak_row and streak_row.max_streak is not None
                else None,
            },
            "coins": {
                "avg": round(float(coins_row.avg_coins), 2)
                if coins_row and coins_row.avg_coins is not None
                else None,
                "total": int(coins_row.total_coins)
                if coins_row and coins_row.total_coins is not None
                else None,
            },
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error("analytics_gamification_error", error=str(e), error_type=type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error"
        )


@router.get("/analytics/retention")
async def analytics_retention(
    _: dict = Depends(admin_required),
    session: AsyncSession = Depends(get_session),
) -> list[dict[str, Any]]:
    try:
        rows = (
            await session.execute(
                text(
                    "WITH cohorts AS ("
                    "  SELECT id AS user_id, DATE(created_at) AS signup_date FROM users"
                    "),"
                    "activity AS ("
                    "  SELECT DISTINCT user_id, session_day AS active_date"
                    "  FROM focus_sessions WHERE session_day IS NOT NULL"
                    ")"
                    "SELECT"
                    "  c.signup_date,"
                    "  COUNT(DISTINCT c.user_id) AS cohort_size,"
                    "  COUNT(DISTINCT CASE WHEN a.active_date = c.signup_date + 1"
                    "    THEN c.user_id END) AS day_1,"
                    "  COUNT(DISTINCT CASE WHEN a.active_date = c.signup_date + 7"
                    "    THEN c.user_id END) AS day_7,"
                    "  COUNT(DISTINCT CASE WHEN a.active_date = c.signup_date + 30"
                    "    THEN c.user_id END) AS day_30"
                    " FROM cohorts c"
                    " LEFT JOIN activity a ON c.user_id = a.user_id"
                    " WHERE c.signup_date >= CURRENT_DATE - INTERVAL '60 days'"
                    " GROUP BY c.signup_date"
                    " ORDER BY c.signup_date DESC"
                )
            )
        ).fetchall()

        return [
            {
                "signup_date": str(row.signup_date),
                "cohort_size": row.cohort_size,
                "day_1": row.day_1,
                "day_7": row.day_7,
                "day_30": row.day_30,
            }
            for row in rows
        ]
    except HTTPException:
        raise
    except Exception as e:
        logger.error("analytics_retention_error", error=str(e), error_type=type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error"
        )


@router.post("/posthog/query")
async def posthog_query(
    body: PostHogQueryRequest,
    _: dict = Depends(admin_required),
) -> Any:
    if not settings.POSTHOG_PROJECT_ID or not settings.POSTHOG_PERSONAL_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="PostHog not configured"
        )

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                f"{settings.POSTHOG_HOST}/api/projects/{settings.POSTHOG_PROJECT_ID}/query/",
                headers={"Authorization": f"Bearer {settings.POSTHOG_PERSONAL_API_KEY}"},
                json={"query": {"kind": "HogQLQuery", "query": body.query}},
            )
            resp.raise_for_status()
            return resp.json()
    except HTTPException:
        raise
    except Exception as e:
        logger.error("posthog_query_error", error=str(e), error_type=type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error"
        )


class SubscriptionOut(BaseModel):
    tier: str
    activated_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    source: Optional[str] = None
    chat_messages_used: int
    chat_messages_limit: Optional[int] = None

    model_config = {"from_attributes": True}


class SubscriptionUpdate(BaseModel):
    tier: Optional[str] = None
    source: Optional[str] = None
    chat_messages_limit: Optional[int] = None
    chat_messages_used: Optional[int] = None


@router.get("/users/{user_id}/subscription", response_model=SubscriptionOut)
async def get_user_subscription(
    user_id: uuid.UUID,
    _: dict = Depends(admin_required),
    session: AsyncSession = Depends(get_session),
) -> SubscriptionOut:
    from backend.domain.subscriptions.repository import SubscriptionRepository
    from backend.domain.subscriptions.service import SubscriptionService

    repo = SubscriptionRepository(session)
    service = SubscriptionService(repo)
    sub = await service.get_subscription(user_id)
    return SubscriptionOut.model_validate(sub)


@router.put("/users/{user_id}/subscription", response_model=SubscriptionOut)
async def update_user_subscription(
    user_id: uuid.UUID,
    payload: SubscriptionUpdate,
    _: dict = Depends(admin_required),
    session: AsyncSession = Depends(get_session),
) -> SubscriptionOut:
    from backend.domain.subscriptions.repository import SubscriptionRepository
    from backend.domain.subscriptions.service import SubscriptionService

    repo = SubscriptionRepository(session)
    service = SubscriptionService(repo)

    update_fields = payload.model_dump(exclude_none=True)
    if "tier" in update_fields:
        sub = await service.set_tier(
            user_id, update_fields.pop("tier"), update_fields.pop("source", None)
        )
    else:
        sub = await service.get_subscription(user_id)

    if update_fields:
        sub = await repo.upsert(user_id, **update_fields)

    return SubscriptionOut.model_validate(sub)
