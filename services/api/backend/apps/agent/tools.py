from __future__ import annotations

import os
import uuid
from datetime import date as date_type, datetime, timedelta, timezone
from typing import Any, Optional

from langchain_core.tools import StructuredTool
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import selectinload

from backend.domain.focus.entities import FocusSession, FocusSessionStatus
from backend.domain.gamification.calculator import parse_plan_minutes
from backend.domain.gamification.entities import DailyFocusAggregate, UserGamificationProfile
from backend.domain.users.entities import User
from backend.infrastructure.database.asyncpg_ssl import build_asyncpg_ssl
from backend.infrastructure.database.session import get_database_url
from backend.infrastructure.logging import get_logger
from backend.infrastructure.repositories import (
    SqlAlchemyUserRepository,
)
from backend.infrastructure.security.auth import verify_user_token

log = get_logger("agent.tools")

# --- Worker DB engine ---


def _create_worker_engine():
    url = get_database_url()
    connect_args = {"statement_cache_size": 0}
    if url.startswith("postgresql+asyncpg://"):
        ssl_ctx = build_asyncpg_ssl()
        if ssl_ctx is not None:
            connect_args["ssl"] = ssl_ctx
        if "pooler.supabase" in url:
            connect_args.setdefault("server_settings", {})["raw_sql_session_mode"] = "true"
    return create_async_engine(
        url,
        echo=False,
        pool_size=int(os.environ.get("DB_WORKER_POOL_SIZE", "5")),
        max_overflow=int(os.environ.get("DB_WORKER_MAX_OVERFLOW", "10")),
        pool_pre_ping=True,
        connect_args=connect_args,
    )


_worker_engine = _create_worker_engine()
WorkerSessionLocal = async_sessionmaker(
    bind=_worker_engine,
    expire_on_commit=False,
    class_=AsyncSession,
)


# --- Core helpers ---


def _error_result(message: str, error_code: Optional[str] = None) -> dict:
    return {
        "status": "error",
        "ok": False,
        "error": message,
        "message": message,
        "error_code": error_code,
    }


def _set_success_envelope(result: dict) -> dict:
    result["status"] = "ok"
    result["ok"] = True
    result.setdefault("error", None)
    result.setdefault("error_code", None)
    return result


def _get_request_id() -> Optional[str]:
    try:
        import structlog.contextvars

        return structlog.contextvars.get_contextvars().get("request_id")
    except Exception:
        return None


def _parse_iso_date(value: str) -> Optional[date_type]:
    try:
        return date_type.fromisoformat(value)
    except (ValueError, AttributeError):
        return None


async def _resolve_user_id_from_token_async(token: str) -> Optional[uuid.UUID]:
    if not token:
        return None
    try:
        payload = verify_user_token(token)
    except Exception as e:
        log.warning("Supabase token verification failed: %s", e)
        return None

    supabase_user_id = payload.get("sub")
    if not supabase_user_id:
        return None
    try:
        supabase_user_uuid = uuid.UUID(str(supabase_user_id))
    except (TypeError, ValueError):
        return None

    async with WorkerSessionLocal() as session:
        user_repo = SqlAlchemyUserRepository(session)
        user = await user_repo.get_by_supabase_user_id(supabase_user_uuid)
        if user:
            return uuid.UUID(str(user.id))
        from sqlalchemy.exc import IntegrityError

        try:
            new_user = User(
                id=uuid.uuid4(),
                email=f"{supabase_user_uuid}@placeholder.invalid",
                supabase_user_id=supabase_user_uuid,
                password_hash=None,
            )
            new_user = await user_repo.create(new_user)
            await session.commit()
            return uuid.UUID(str(new_user.id))
        except IntegrityError:
            await session.rollback()
            user = await user_repo.get_by_supabase_user_id(supabase_user_uuid)
            if user:
                return uuid.UUID(str(user.id))
            raise


async def _require_user_id_async(user_token: str) -> tuple[uuid.UUID | None, dict | None]:
    if not user_token:
        return (None, _error_result("User token required", error_code="auth_required"))
    try:
        user_id = await _resolve_user_id_from_token_async(user_token)
    except Exception as e:
        log.warning("Failed to resolve user from token: %s", e)
        user_id = None
    if not user_id:
        return (None, _error_result("Invalid user token", error_code="auth_invalid"))
    return (user_id, None)


# --- Date helpers ---


def _today_utc() -> date_type:
    return datetime.now(timezone.utc).date()


def _today_local(tz: str) -> date_type:
    from zoneinfo import ZoneInfo

    try:
        zone = ZoneInfo(tz)
    except Exception:
        zone = ZoneInfo("UTC")
    return datetime.now(zone).date()


def _resolve_period_preset(
    preset: str,
    from_str: Optional[str],
    to_str: Optional[str],
    tz: Optional[str] = None,
) -> tuple[date_type, date_type]:
    today = _today_local(tz) if tz else _today_utc()
    if preset == "today":
        return today, today
    if preset == "this_week":
        monday = today - timedelta(days=today.weekday())
        return monday, today
    if preset == "last_week":
        monday = today - timedelta(days=today.weekday() + 7)
        return monday, monday + timedelta(days=6)
    if preset == "this_month":
        return today.replace(day=1), today
    if preset == "custom" and from_str and to_str:
        d_from = _parse_iso_date(from_str)
        d_to = _parse_iso_date(to_str)
        if d_from and d_to:
            return d_from, d_to
    if from_str and to_str:
        d_from = _parse_iso_date(from_str)
        d_to = _parse_iso_date(to_str)
        if d_from and d_to:
            return d_from, d_to
    monday = today - timedelta(days=today.weekday())
    return monday, today


def _clamp_period(
    d_from: date_type, d_to: date_type, max_days_back: int = 28
) -> tuple[date_type, date_type, bool]:
    today = _today_utc()
    cutoff = today - timedelta(days=max_days_back)
    clamped = False
    if d_from < cutoff:
        d_from = cutoff
        clamped = True
    return d_from, d_to, clamped


# --- Aggregate query helpers ---


async def _load_aggregates(
    session: AsyncSession,
    user_id: uuid.UUID,
    d_from: date_type,
    d_to: date_type,
) -> list[DailyFocusAggregate]:
    result = await session.execute(
        select(DailyFocusAggregate)
        .where(
            DailyFocusAggregate.user_id == user_id,
            DailyFocusAggregate.focus_date >= d_from,
            DailyFocusAggregate.focus_date <= d_to,
        )
        .order_by(DailyFocusAggregate.focus_date.asc())
    )
    return list(result.scalars().all())


async def _load_sessions(
    session: AsyncSession,
    user_id: uuid.UUID,
    d_from: date_type,
    d_to: date_type,
    room_ids: Optional[list[str]] = None,
    min_minutes: Optional[int] = None,
    max_minutes: Optional[int] = None,
) -> list[FocusSession]:
    q = (
        select(FocusSession)
        .options(selectinload(FocusSession.room))
        .where(
            FocusSession.user_id == user_id,
            FocusSession.status == FocusSessionStatus.finished,
            FocusSession.session_day >= d_from,
            FocusSession.session_day <= d_to,
        )
    )
    if room_ids:
        room_uuids = [uuid.UUID(r) for r in room_ids if r]
        q = q.where(FocusSession.room_id.in_(room_uuids))
    if min_minutes is not None:
        q = q.where(FocusSession.credited_minutes >= min_minutes)
    if max_minutes is not None:
        q = q.where(FocusSession.credited_minutes <= max_minutes)
    result = await session.execute(q)
    return list(result.scalars().all())


# --- Tool implementations ---


async def _load_home_tz(session: AsyncSession, user_id: uuid.UUID) -> Optional[str]:
    profile_result = await session.execute(
        select(UserGamificationProfile).where(UserGamificationProfile.user_id == user_id)
    )
    profile = profile_result.scalar_one_or_none()
    return profile.home_tz if profile else None


async def _get_focus_stats_slice_async(
    period: Optional[dict],
    filters: Optional[dict],
    group_by: Optional[list[str]],
    metrics: Optional[list[str]],
    limit: Optional[int],
    _user_token: str,
) -> dict:
    user_id, err = await _require_user_id_async(_user_token or "")
    if err:
        return err
    assert user_id is not None

    period = period or {}
    preset = period.get("preset", "this_week")

    filters = filters or {}
    group_by = group_by or []
    metrics = metrics or ["focus_minutes", "session_count"]
    limit = limit or 50
    limits_out: list[str] = []

    if filters.get("app_ids"):
        limits_out.append("app_id_unavailable")

    if "screen_time_minutes" in metrics:
        limits_out.append("screen_time_unavailable")
        metrics = [m for m in metrics if m != "screen_time_minutes"]

    room_ids = filters.get("room_ids") or None
    min_minutes = filters.get("session_min_minutes")
    max_minutes = filters.get("session_max_minutes")
    days_of_week = filters.get("days_of_week")

    try:
        async with WorkerSessionLocal() as session:
            home_tz = await _load_home_tz(session, user_id)
            d_from, d_to = _resolve_period_preset(
                preset, period.get("from"), period.get("to"), tz=home_tz
            )
            aggregates = await _load_aggregates(session, user_id, d_from, d_to)
            finished_sessions = await _load_sessions(
                session, user_id, d_from, d_to, room_ids, min_minutes, max_minutes
            )
    except Exception as e:
        log.exception("get_focus_stats_slice DB error: %s", e)
        return _error_result(str(e))

    if days_of_week:
        dow_map = {"mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6, "sun": 7}
        allowed = {dow_map[d] for d in days_of_week if d in dow_map}
        aggregates = [a for a in aggregates if a.focus_date.isoweekday() in allowed]
        finished_sessions = [
            s for s in finished_sessions if s.session_day and s.session_day.isoweekday() in allowed
        ]

    total_focus_minutes = sum(a.total_credited_minutes for a in aggregates)
    total_sessions = sum(a.session_count for a in aggregates)
    days_with_focus = sum(1 for a in aggregates if a.total_credited_minutes > 0)
    avg_session = round(total_focus_minutes / total_sessions, 1) if total_sessions > 0 else 0

    summary_metrics: dict[str, Any] = {}
    if "focus_minutes" in metrics:
        summary_metrics["focus_minutes"] = total_focus_minutes
    if "session_count" in metrics:
        summary_metrics["session_count"] = total_sessions
    if "avg_session_minutes" in metrics:
        summary_metrics["avg_session_minutes"] = avg_session
    if "plan_minutes" in metrics or "plan_completion" in metrics:
        total_plan = sum(_day_plan_minutes(a.focus_date, {}) for a in aggregates)
        if "plan_minutes" in metrics:
            summary_metrics["plan_minutes"] = total_plan
        if "plan_completion" in metrics:
            summary_metrics["plan_completion"] = (
                round(total_focus_minutes / total_plan * 100) if total_plan > 0 else None
            )

    grouped: list[dict] = []
    if "day" in group_by:
        by_day: dict[str, dict] = {}
        for a in aggregates:
            key = a.focus_date.isoformat()
            by_day[key] = {
                "date": key,
                "focus_minutes": a.total_credited_minutes,
                "session_count": a.session_count,
            }
        grouped = sorted(by_day.values(), key=lambda x: x["date"])[:limit]
    elif "room" in group_by:
        from collections import defaultdict

        room_min: dict[str, int] = defaultdict(int)
        room_sess: dict[str, int] = defaultdict(int)
        room_title: dict[str, str] = {}
        for s in finished_sessions:
            rid = str(s.room_id)
            room_min[rid] += s.credited_minutes or 0
            room_sess[rid] += 1
            if s.room and s.room.title:
                room_title[rid] = s.room.title
        grouped = sorted(
            [
                {
                    "room_id": rid,
                    "title": room_title.get(rid, rid[:8]),
                    "focus_minutes": m,
                    "session_count": room_sess[rid],
                }
                for rid, m in room_min.items()
            ],
            key=lambda x: int(x["focus_minutes"]),
            reverse=True,
        )[:limit]

    evidence: list[str] = [
        f"Период: {d_from.isoformat()} — {d_to.isoformat()}",
        f"Дней с фокусом: {days_with_focus}",
        f"Итого: {total_focus_minutes} мин, {total_sessions} сессий",
    ]

    result: dict[str, Any] = {
        "summary": f"Период {d_from.isoformat()}–{d_to.isoformat()}: {total_focus_minutes} мин, {total_sessions} сессий",
        "metrics": summary_metrics,
        "grouped": grouped,
        "evidence": evidence,
        "limits": limits_out,
    }
    return _set_success_envelope(result)


def _day_plan_minutes(d: date_type, plan_minutes: dict[int, int]) -> int:
    return plan_minutes.get(d.isoweekday(), 0)


async def _compare_focus_periods_async(
    period_a: Optional[dict],
    period_b: Optional[dict],
    metrics: Optional[list[str]],
    include_interpretation: bool,
    _user_token: str,
) -> dict:
    user_id, err = await _require_user_id_async(_user_token or "")
    if err:
        return err
    assert user_id is not None

    period_a = period_a or {}
    period_b = period_b or {}
    metrics = metrics or ["focus_minutes", "session_count", "avg_session_minutes"]

    limits_out: list[str] = []
    if "screen_time_minutes" in metrics:
        limits_out.append("screen_time_unavailable")
        metrics = [m for m in metrics if m != "screen_time_minutes"]

    try:
        async with WorkerSessionLocal() as session:
            home_tz = await _load_home_tz(session, user_id)
            a_from, a_to = _resolve_period_preset(
                period_a.get("preset", "custom"),
                period_a.get("from"),
                period_a.get("to"),
                tz=home_tz,
            )
            b_from, b_to = _resolve_period_preset(
                period_b.get("preset", "custom"),
                period_b.get("from"),
                period_b.get("to"),
                tz=home_tz,
            )
            a_from, a_to, a_clamped = _clamp_period(a_from, a_to)
            b_from, b_to, b_clamped = _clamp_period(b_from, b_to)
            if a_clamped or b_clamped:
                limits_out.append("period_too_old")
            aggs_a = await _load_aggregates(session, user_id, a_from, a_to)
            aggs_b = await _load_aggregates(session, user_id, b_from, b_to)
            sessions_a = await _load_sessions(session, user_id, a_from, a_to)
            sessions_b = await _load_sessions(session, user_id, b_from, b_to)
    except Exception as e:
        log.exception("compare_focus_periods DB error: %s", e)
        return _error_result(str(e))

    def _agg_metrics(aggs: list[DailyFocusAggregate], sesses: list[FocusSession]) -> dict[str, Any]:
        total_min = sum(a.total_credited_minutes for a in aggs)
        total_sess = sum(a.session_count for a in aggs)
        avg_sess = round(total_min / total_sess, 1) if total_sess else 0
        days_with = sum(1 for a in aggs if a.total_credited_minutes > 0)
        return {
            "focus_minutes": total_min,
            "session_count": total_sess,
            "avg_session_minutes": avg_sess,
            "closed_focus_days": days_with,
        }

    vals_a = _agg_metrics(aggs_a, sessions_a)
    vals_b = _agg_metrics(aggs_b, sessions_b)

    label_a = period_a.get("label") or f"{a_from}–{a_to}"
    label_b = period_b.get("label") or f"{b_from}–{b_to}"

    changes: list[dict] = []
    for m in metrics:
        if m not in vals_a:
            continue
        a_val = vals_a[m]
        b_val = vals_b[m]
        if a_val and a_val != 0:
            delta_pct = round((b_val - a_val) / a_val * 100)
        else:
            delta_pct = None

        meaning = "стабильно"
        if delta_pct is not None:
            if delta_pct > 10:
                meaning = "выросло"
            elif delta_pct < -10:
                meaning = "просело"

        changes.append(
            {
                "metric": m,
                "a": a_val,
                "b": b_val,
                "delta_pct": delta_pct,
                "meaning": meaning,
            }
        )

    summary = f"Сравнение: {label_a} vs {label_b}"

    result: dict[str, Any] = {
        "summary": summary,
        "period_a": {"label": label_a, "from": a_from.isoformat(), "to": a_to.isoformat()},
        "period_b": {"label": label_b, "from": b_from.isoformat(), "to": b_to.isoformat()},
        "changes": changes,
        "limits": limits_out,
    }
    return _set_success_envelope(result)


def _round_to_15(minutes: int) -> int:
    return round(minutes / 15) * 15


async def _evaluate_focus_plan_async(
    current_plan: Optional[dict],
    proposed_plan: Optional[dict],
    basis_period: Optional[dict],
    goal: Optional[str],
    _user_token: str,
) -> dict:
    user_id, err = await _require_user_id_async(_user_token or "")
    if err:
        return err
    assert user_id is not None

    current_plan = current_plan or {}
    proposed_plan = proposed_plan or {}
    basis_period = basis_period or {}
    goal = goal or "maintain"

    try:
        async with WorkerSessionLocal() as session:
            home_tz = await _load_home_tz(session, user_id)
            today = _today_local(home_tz) if home_tz else _today_utc()
            preset = basis_period.get("preset", "last_4_weeks")
            if preset == "last_4_weeks":
                b_from = today - timedelta(days=28)
                b_to = today - timedelta(days=1)
            elif preset == "last_8_weeks":
                b_from = today - timedelta(days=56)
                b_to = today - timedelta(days=1)
            else:
                b_from, b_to = _resolve_period_preset(
                    "custom", basis_period.get("from"), basis_period.get("to"), tz=home_tz
                )
            aggs = await _load_aggregates(session, user_id, b_from, b_to)
            profile_result = await session.execute(
                select(UserGamificationProfile).where(UserGamificationProfile.user_id == user_id)
            )
            profile = profile_result.scalar_one_or_none()
    except Exception as e:
        log.exception("evaluate_focus_plan DB error: %s", e)
        return _error_result(str(e))

    plan_minutes_db = parse_plan_minutes(profile.plan_minutes_json) if profile else {}

    basis_days = (b_to - b_from).days + 1
    has_baseline = basis_days >= 14 and len(aggs) >= 7

    total_actual = sum(a.total_credited_minutes for a in aggs)
    weeks_in_window = max(1, basis_days / 7)
    avg_actual_per_week = total_actual / weeks_in_window if has_baseline else 0

    plan_source = proposed_plan if proposed_plan.get("days") else current_plan
    plan_days_list = plan_source.get("days", [])
    dow_map = {"mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6, "sun": 7}
    proposed_by_dow: dict[int, int] = {}
    for entry in plan_days_list:
        dow = dow_map.get(entry.get("day", ""), 0)
        if dow:
            proposed_by_dow[dow] = int(entry.get("minutes", 0))

    current_by_dow = plan_minutes_db if not plan_days_list else proposed_by_dow
    total_proposed = (
        sum(proposed_by_dow.values()) if proposed_by_dow else sum(plan_minutes_db.values())
    )

    goal_factors = {
        "maintain": 1.0,
        "increase": 1.15,
        "recover_week": 0.7,
        "reduce_overload": 0.85,
    }
    factor = goal_factors.get(goal, 1.0)

    if not has_baseline:
        realism = "too_high" if total_proposed > 0 else "realistic"
        risks = ["no_baseline"]
        reasoning = ["Недостаточно данных (менее 14 дней истории) для оценки реалистичности."]
        return _set_success_envelope(
            {
                "realism": realism,
                "recommended_plan": {},
                "reasoning": reasoning,
                "risks": risks,
            }
        )

    if avg_actual_per_week == 0:
        ratio = float("inf")
    else:
        ratio = total_proposed / avg_actual_per_week

    if ratio < 0.5:
        realism = "too_low"
    elif ratio <= 1.1:
        realism = "realistic"
    elif ratio <= 1.4:
        realism = "stretch"
    else:
        realism = "too_high"

    target_total = _round_to_15(round(avg_actual_per_week * factor))
    target_total = max(0, target_total)

    base_plan = current_by_dow if current_by_dow else plan_minutes_db
    focus_days = [dow for dow, mins in base_plan.items() if mins > 0]
    if not focus_days:
        focus_days = [1, 3, 5]

    total_base = sum(base_plan.get(d, 0) for d in focus_days)
    recommended_days: dict[int, int] = {}
    for dow in focus_days:
        if total_base > 0:
            share = base_plan.get(dow, 0) / total_base
            recommended_days[dow] = _round_to_15(round(target_total * share))
        else:
            recommended_days[dow] = _round_to_15(target_total // len(focus_days))

    recommended_plan = {
        "days": [
            {"day": ["", "mon", "tue", "wed", "thu", "fri", "sat", "sun"][dow], "minutes": mins}
            for dow, mins in sorted(recommended_days.items())
        ],
        "total_minutes": sum(recommended_days.values()),
    }

    effective_by_dow: dict[int, int] = proposed_by_dow if proposed_by_dow else current_by_dow

    risks: list[str] = []
    if aggs:
        max_day = max(a.total_credited_minutes for a in aggs)
        for dow, mins in effective_by_dow.items():
            if max_day > 0 and mins > max_day * 1.2:
                day_name = ["", "mon", "tue", "wed", "thu", "fri", "sat", "sun"][dow]
                risks.append(
                    f"День {day_name} превышает 120% от максимального дня в истории ({max_day} мин)."
                )

    consecutive = 0
    max_consecutive = 0
    for dow in range(1, 8):
        if effective_by_dow.get(dow, 0) > 0:
            consecutive += 1
            max_consecutive = max(max_consecutive, consecutive)
        else:
            consecutive = 0
    if max_consecutive >= 5:
        risks.append("5+ подряд фокус-дней без отдыха — риск перегрузки.")

    reasoning = [
        f"Средний факт за период: {round(avg_actual_per_week)} мин/нед.",
        f"Предложенный план: {total_proposed} мин/нед.",
        f"Коэффициент: {round(ratio, 2)}.",
        f"Цель: {goal} (множитель {factor}).",
        f"Рекомендуемый план: {target_total} мин/нед.",
    ]

    return _set_success_envelope(
        {
            "realism": realism,
            "recommended_plan": recommended_plan,
            "reasoning": reasoning,
            "risks": risks,
        }
    )


# --- Tool schemas (LangChain) ---


class _PeriodInput(BaseModel):
    preset: Optional[str] = "this_week"
    from_: Optional[str] = None
    to: Optional[str] = None

    model_config = {"populate_by_name": True}


class _FiltersInput(BaseModel):
    room_ids: Optional[list[str]] = None
    app_ids: Optional[list[str]] = None
    days_of_week: Optional[list[str]] = None
    session_min_minutes: Optional[int] = None
    session_max_minutes: Optional[int] = None


class GetFocusStatsSliceInput(BaseModel):
    period: Optional[dict] = None
    filters: Optional[dict] = None
    group_by: Optional[list[str]] = None
    metrics: Optional[list[str]] = None
    limit: Optional[int] = None


class CompareFocusPeriodsInput(BaseModel):
    period_a: Optional[dict] = None
    period_b: Optional[dict] = None
    metrics: Optional[list[str]] = None
    include_interpretation: bool = True


class EvaluateFocusPlanInput(BaseModel):
    current_plan: Optional[dict] = None
    proposed_plan: Optional[dict] = None
    basis_period: Optional[dict] = None
    goal: Optional[str] = None


def _get_focus_stats_slice_sync(
    period: Optional[dict] = None,
    filters: Optional[dict] = None,
    group_by: Optional[list[str]] = None,
    metrics: Optional[list[str]] = None,
    limit: Optional[int] = None,
) -> dict:
    raise NotImplementedError("Use async impl via ASYNC_TOOL_IMPLS_BY_VARIANT")


def _compare_focus_periods_sync(
    period_a: Optional[dict] = None,
    period_b: Optional[dict] = None,
    metrics: Optional[list[str]] = None,
    include_interpretation: bool = True,
) -> dict:
    raise NotImplementedError("Use async impl via ASYNC_TOOL_IMPLS_BY_VARIANT")


def _evaluate_focus_plan_sync(
    current_plan: Optional[dict] = None,
    proposed_plan: Optional[dict] = None,
    basis_period: Optional[dict] = None,
    goal: Optional[str] = None,
) -> dict:
    raise NotImplementedError("Use async impl via ASYNC_TOOL_IMPLS_BY_VARIANT")


_focus_stats_tools = [
    StructuredTool.from_function(
        func=_get_focus_stats_slice_sync,
        name="get_focus_stats_slice",
        description=(
            "Возвращает агрегированный срез фокус-статистики по периоду, комнате, дню, времени, "
            "приложению, типу сессии или другому фильтру. "
            "Используй когда нужна точная метрика, drill-down или фильтр по комнате/дню/слоту."
        ),
        args_schema=GetFocusStatsSliceInput,
    ),
    StructuredTool.from_function(
        func=_compare_focus_periods_sync,
        name="compare_focus_periods",
        description=(
            "Сравнивает два произвольных периода и возвращает главные изменения. "
            "Используй когда нужна динамика или сравнение нестандартных периодов."
        ),
        args_schema=CompareFocusPeriodsInput,
    ),
    StructuredTool.from_function(
        func=_evaluate_focus_plan_sync,
        name="evaluate_focus_plan",
        description=(
            "Оценивает реалистичность текущего или предложенного фокус-плана и предлагает "
            "корректировку. Используй когда пользователь хочет поднять цель или оценить план."
        ),
        args_schema=EvaluateFocusPlanInput,
    ),
]

# --- Tool registry ---

TOOLS_BY_VARIANT: dict[str, list] = {
    "focus_stats": _focus_stats_tools,
}

ASYNC_TOOL_IMPLS_BY_VARIANT: dict[str, dict[str, Any]] = {
    "focus_stats": {
        "get_focus_stats_slice": _get_focus_stats_slice_async,
        "compare_focus_periods": _compare_focus_periods_async,
        "evaluate_focus_plan": _evaluate_focus_plan_async,
    },
}
