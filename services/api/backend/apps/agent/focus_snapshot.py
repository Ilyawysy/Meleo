from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from backend.domain.focus.entities import FocusSession, FocusSessionStatus
from backend.domain.focus_rooms.task_entities import Task, TaskStatus
from backend.domain.gamification.calculator import (
    STREAK_ABS_MIN_MINUTES,
    STREAK_PERCENT,
    parse_plan_minutes,
)
from backend.domain.gamification.entities import DailyFocusAggregate, UserGamificationProfile
from backend.infrastructure.logging import get_logger

log = get_logger("agent.focus_snapshot")

_LOCALE = "ru-RU"
_WINDOW_DAYS = 28
_MIN_HISTORY_DAYS = 14


def _safe_tz(tz_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(tz_name)
    except Exception:
        return ZoneInfo("UTC")


def _now_local(tz: ZoneInfo) -> datetime:
    return datetime.now(tz)


def _today_local(tz: ZoneInfo) -> date:
    return _now_local(tz).date()


def _compute_form_score(
    aggregates: list[DailyFocusAggregate],
    plan_minutes: dict[int, int],
) -> int:
    if not aggregates:
        return 0
    days = len(aggregates)
    days_with_focus = sum(1 for a in aggregates if a.total_credited_minutes > 0)
    days_goal_met = sum(1 for a in aggregates if a.recovery_mode or _is_streak_day(a, plan_minutes))
    total_minutes = sum(a.total_credited_minutes for a in aggregates)

    focus_consistency = days_with_focus / days
    goal_ratio = days_goal_met / days

    enabled_mins = [v for v in plan_minutes.values() if v > 0]
    avg_plan = sum(enabled_mins) // len(enabled_mins) if enabled_mins else 0
    plan_total = avg_plan * days
    volume_ratio = min(total_minutes / plan_total, 1.0) if plan_total > 0 else 0.0

    score = round(focus_consistency * 40 + goal_ratio * 30 + volume_ratio * 30)
    return max(0, min(100, score))


def _is_streak_day(agg: DailyFocusAggregate, plan_minutes: dict[int, int]) -> bool:
    wd = agg.focus_date.isoweekday()
    plan = plan_minutes.get(wd, 0)
    if plan == 0:
        return False
    threshold = max(round(plan * STREAK_PERCENT), STREAK_ABS_MIN_MINUTES)
    return agg.total_credited_minutes >= threshold


def _build_today(
    today: date,
    agg_by_date: dict[date, DailyFocusAggregate],
    plan_minutes: dict[int, int],
    tz: ZoneInfo,
) -> dict:
    now_local = _now_local(tz)
    wd = today.isoweekday()
    plan_today = plan_minutes.get(wd, 0)
    agg = agg_by_date.get(today)
    credited = agg.total_credited_minutes if agg else 0
    sessions_today = agg.session_count if agg else 0
    recovery = agg.recovery_mode if agg else None
    goal_reached = credited >= plan_today if plan_today > 0 else False
    pct = round(credited / plan_today * 100) if plan_today > 0 else None

    return {
        "date": today.isoformat(),
        "weekday": wd,
        "is_focus_day": plan_today > 0,
        "plan_minutes": plan_today,
        "credited_minutes": credited,
        "session_count": sessions_today,
        "goal_reached": goal_reached,
        "pct_to_plan": pct,
        "recovery_mode": recovery,
        "local_hour": now_local.hour,
    }


def _week_monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _build_week_plan(
    today: date,
    agg_by_date: dict[date, DailyFocusAggregate],
    plan_minutes: dict[int, int],
) -> dict:
    monday = _week_monday(today)
    week_days = [monday + timedelta(days=i) for i in range(7)]

    plan_total = sum(plan_minutes.get(d.isoweekday(), 0) for d in week_days)
    fact_total = sum(agg_by_date[d].total_credited_minutes for d in week_days if d in agg_by_date)
    days_passed = (today - monday).days + 1
    plan_to_today = sum(plan_minutes.get(d.isoweekday(), 0) for d in week_days[:days_passed])
    days_remaining = 7 - days_passed
    pct_to_today = round(fact_total / plan_to_today * 100) if plan_to_today > 0 else None

    by_day = []
    for d in week_days:
        wd = d.isoweekday()
        agg = agg_by_date.get(d)
        by_day.append(
            {
                "date": d.isoformat(),
                "weekday": wd,
                "plan": plan_minutes.get(wd, 0),
                "fact": agg.total_credited_minutes if agg else 0,
                "is_past": d <= today,
            }
        )

    return {
        "week_start": monday.isoformat(),
        "plan_total": plan_total,
        "fact_total": fact_total,
        "plan_to_today": plan_to_today,
        "pct_to_today": pct_to_today,
        "days_remaining": days_remaining,
        "by_day": by_day,
    }


def _build_week_extremes(
    today: date,
    agg_by_date: dict[date, DailyFocusAggregate],
) -> dict:
    monday = _week_monday(today)
    week_aggs = [
        agg_by_date[monday + timedelta(days=i)]
        for i in range(7)
        if (monday + timedelta(days=i)) in agg_by_date and (monday + timedelta(days=i)) <= today
    ]
    if not week_aggs:
        return {"best_day": None, "worst_day": None}
    best = max(week_aggs, key=lambda a: a.total_credited_minutes)
    worst = min(week_aggs, key=lambda a: a.total_credited_minutes)
    return {
        "best_day": {"date": best.focus_date.isoformat(), "minutes": best.total_credited_minutes},
        "worst_day": {
            "date": worst.focus_date.isoformat(),
            "minutes": worst.total_credited_minutes,
        },
    }


def _build_load_realism(
    aggregates: list[DailyFocusAggregate],
    plan_minutes: dict[int, int],
    window_weeks: int,
) -> dict:
    if not aggregates:
        return {"status": "no_data", "avg_actual_per_week": 0, "week_plan_total": 0, "ratio": None}
    avg_actual_per_week = sum(a.total_credited_minutes for a in aggregates) / max(window_weeks, 1)
    week_plan_total = sum(plan_minutes.values())
    if avg_actual_per_week == 0:
        ratio = None
        status = "no_baseline"
    else:
        ratio = round(week_plan_total / avg_actual_per_week, 2)
        if ratio < 0.5:
            status = "too_low"
        elif ratio <= 1.1:
            status = "realistic"
        elif ratio <= 1.4:
            status = "stretch"
        else:
            status = "too_high"

    return {
        "status": status,
        "avg_actual_per_week": round(avg_actual_per_week),
        "week_plan_total": week_plan_total,
        "ratio": ratio,
    }


def _build_focus_state(
    aggregates_28d: list[DailyFocusAggregate],
    aggregates_7d: list[DailyFocusAggregate],
    aggregates_prev_7d: list[DailyFocusAggregate],
    plan_minutes: dict[int, int],
    profile: UserGamificationProfile,
) -> dict:
    form = _compute_form_score(aggregates_7d, plan_minutes)
    prev_form = _compute_form_score(aggregates_prev_7d, plan_minutes)
    form_trend = "unknown"
    if aggregates_prev_7d:
        delta = form - prev_form
        if delta > 5:
            form_trend = "up"
        elif delta < -5:
            form_trend = "down"
        else:
            form_trend = "stable"

    return {
        "streak_current": profile.streak_current,
        "streak_longest": profile.longest_streak,
        "recovery_days_remaining": profile.recovery_days_remaining,
        "consecutive_missed": profile.consecutive_missed_focus_days,
        "minimal_mode": profile.minimal_mode,
        "form": form,
        "form_prev_week": prev_form if aggregates_prev_7d else None,
        "form_trend": form_trend,
    }


def _build_sessions(
    sessions: list[FocusSession],
    today: date,
    tz: ZoneInfo,
) -> dict:
    if not sessions:
        return {
            "count_28d": 0,
            "avg_duration_min": None,
            "median_duration_min": None,
            "best_window": None,
            "longest_session_min": None,
        }
    durations = [s.credited_minutes for s in sessions if s.credited_minutes]
    avg_dur = round(sum(durations) / len(durations)) if durations else None
    sorted_dur = sorted(durations)
    n = len(sorted_dur)
    median_dur = sorted_dur[n // 2] if n else None

    window_buckets: dict[str, int] = {"morning": 0, "day": 0, "evening": 0, "night": 0}
    for s in sessions:
        if not s.started_at:
            continue
        local_dt = s.started_at.astimezone(tz)
        h = local_dt.hour
        credited = s.credited_minutes or 0
        if h >= 6 and h < 12:
            window_buckets["morning"] += credited
        elif h >= 12 and h < 18:
            window_buckets["day"] += credited
        elif h >= 18:
            window_buckets["evening"] += credited
        else:
            window_buckets["night"] += credited

    best_window: Optional[str] = max(window_buckets, key=lambda k: window_buckets[k])
    if window_buckets[best_window] == 0:
        best_window = None

    longest = max(durations) if durations else None

    return {
        "count_28d": len(sessions),
        "avg_duration_min": avg_dur,
        "median_duration_min": median_dur,
        "best_window": best_window,
        "longest_session_min": longest,
    }


def _build_time_patterns(
    aggregates: list[DailyFocusAggregate],
    sessions: list[FocusSession],
    tz: ZoneInfo,
) -> dict:
    weekday_totals: dict[int, int] = defaultdict(int)
    for agg in aggregates:
        wd = agg.focus_date.isoweekday()
        weekday_totals[wd] += agg.total_credited_minutes

    best_wd = max(weekday_totals, key=lambda k: weekday_totals[k]) if weekday_totals else None
    worst_wd = min(weekday_totals, key=lambda k: weekday_totals[k]) if weekday_totals else None

    total_min = sum(weekday_totals.values())
    best_wd_pct = (
        round(weekday_totals[best_wd] / total_min * 100) if total_min and best_wd else None
    )

    return {
        "best_weekday": best_wd,
        "worst_weekday": worst_wd,
        "best_weekday_pct": best_wd_pct,
        "weekday_totals": dict(weekday_totals),
        "drilldowns_available": ["get_focus_stats_slice with group_by=day"],
    }


def _build_rooms(sessions: list[FocusSession]) -> dict:
    room_minutes: dict[str, int] = defaultdict(int)
    room_sessions: dict[str, int] = defaultdict(int)
    room_titles: dict[str, str] = {}

    for s in sessions:
        rid = str(s.room_id)
        credited = s.credited_minutes or 0
        room_minutes[rid] += credited
        room_sessions[rid] += 1
        if s.room and s.room.title and rid not in room_titles:
            room_titles[rid] = s.room.title

    total = sum(room_minutes.values())
    rooms_sorted = sorted(room_minutes.items(), key=lambda x: x[1], reverse=True)

    top_rooms = []
    for rid, mins in rooms_sorted[:5]:
        top_rooms.append(
            {
                "room_id": rid,
                "title": room_titles.get(rid, rid[:8]),
                "minutes": mins,
                "sessions": room_sessions[rid],
                "pct": round(mins / total * 100) if total else 0,
            }
        )

    top_pct = top_rooms[0]["pct"] if top_rooms else 0

    return {
        "top_rooms": top_rooms,
        "top_room_pct": top_pct,
        "total_rooms_active": len(room_minutes),
        "drilldowns_available": ["get_focus_stats_slice with filters.room_ids"],
    }


def _build_month(
    aggregates: list[DailyFocusAggregate],
    today: date,
) -> dict:
    current_month = today.replace(day=1)
    prev_month = (current_month - timedelta(days=1)).replace(day=1)

    current_total = sum(
        a.total_credited_minutes for a in aggregates if a.focus_date >= current_month
    )
    prev_total = sum(
        a.total_credited_minutes for a in aggregates if prev_month <= a.focus_date < current_month
    )

    delta = None
    if prev_total > 0:
        delta = round((current_total - prev_total) / prev_total * 100)

    return {
        "current_month_minutes": current_total,
        "prev_month_minutes": prev_total,
        "mom_delta_pct": delta,
    }


def _build_comparisons(
    aggregates: list[DailyFocusAggregate],
    today: date,
    plan_minutes: dict[int, int],
) -> dict:
    monday = _week_monday(today)
    prev_monday = monday - timedelta(days=7)

    this_week_aggs = [a for a in aggregates if monday <= a.focus_date <= today]
    prev_week_aggs = [a for a in aggregates if prev_monday <= a.focus_date < monday]

    this_week_min = sum(a.total_credited_minutes for a in this_week_aggs)
    prev_week_min = sum(a.total_credited_minutes for a in prev_week_aggs)

    this_form = _compute_form_score(this_week_aggs, plan_minutes)
    prev_form = _compute_form_score(prev_week_aggs, plan_minutes)

    wow_delta = None
    if prev_week_min > 0:
        wow_delta = round((this_week_min - prev_week_min) / prev_week_min * 100)

    return {
        "this_week_minutes": this_week_min,
        "prev_week_minutes": prev_week_min,
        "wow_delta_pct": wow_delta,
        "this_week_form": this_form,
        "prev_week_form": prev_form,
        "drilldowns_available": ["compare_focus_periods"],
    }


def _build_intentions_results(tasks_done_7d: int) -> dict:
    return {
        "tasks_done_7d": tasks_done_7d,
        "limits": ["intentions_not_tracked"],
    }


def _build_top_signals(
    today_block: dict,
    week_plan: dict,
    focus_state: dict,
    rooms: dict,
    time_patterns: dict,
    aggregates: list[DailyFocusAggregate],
    today: date,
) -> list[dict]:
    signals = []

    pct_to_today = week_plan.get("pct_to_today")
    days_remaining = week_plan.get("days_remaining", 7)
    if pct_to_today is not None and pct_to_today < 60 and days_remaining < 3:
        signals.append(
            {
                "id": "plan_gap",
                "severity": "watch",
                "message": "Неделя почти закончилась, а план выполнен меньше чем на 60%.",
                "evidence": [
                    f"{week_plan.get('fact_total', 0)}/{week_plan.get('plan_to_today', 0)} мин к сегодня",
                    f"Осталось дней: {days_remaining}",
                ],
                "confidence": "high",
                "related_blocks": ["week_plan"],
            }
        )

    if today_block.get("is_focus_day") and not today_block.get("goal_reached"):
        local_hour = today_block.get("local_hour", 0)
        if local_hour >= 18:
            signals.append(
                {
                    "id": "streak_at_risk",
                    "severity": "risk",
                    "message": "Сегодня фокус-день, но план ещё не выполнен, а день почти закончился.",
                    "evidence": [
                        f"Накоплено: {today_block.get('credited_minutes', 0)} мин",
                        f"Нужно: {today_block.get('plan_minutes', 0)} мин",
                    ],
                    "confidence": "high",
                    "related_blocks": ["today", "week_plan"],
                }
            )

    form = focus_state.get("form", 0)
    prev_form = focus_state.get("form_prev_week")
    if prev_form is not None and form < prev_form - 10:
        signals.append(
            {
                "id": "form_drop",
                "severity": "watch",
                "message": "Form за эту неделю ниже прошлой на 10+ пунктов.",
                "evidence": [
                    f"Текущий Form: {form}",
                    f"Прошлая неделя: {prev_form}",
                ],
                "confidence": "medium",
                "related_blocks": ["focus_state"],
            }
        )

    week_actual = week_plan.get("fact_total", 0)
    week_planned = week_plan.get("plan_total", 0)
    if week_planned > 0 and week_actual > 1.3 * week_planned:
        signals.append(
            {
                "id": "load_overshoot",
                "severity": "watch",
                "message": "Фактическая нагрузка за неделю превышает план более чем на 30%.",
                "evidence": [
                    f"Факт: {week_actual} мин",
                    f"План: {week_planned} мин",
                ],
                "confidence": "high",
                "related_blocks": ["week_plan", "load_realism"],
            }
        )

    top_room_pct = rooms.get("top_room_pct", 0)
    if top_room_pct > 70 and rooms.get("total_rooms_active", 0) > 1:
        top_rooms = rooms.get("top_rooms", [])
        room_title = top_rooms[0]["title"] if top_rooms else "Одна комната"
        signals.append(
            {
                "id": "room_concentration",
                "severity": "info",
                "message": f"Более 70% времени сосредоточено в одной комнате: {room_title}.",
                "evidence": [f"{top_room_pct}% времени в комнате «{room_title}»"],
                "confidence": "high",
                "related_blocks": ["rooms"],
            }
        )

    if aggregates:
        total_by_wd: dict[int, int] = defaultdict(int)
        for agg in aggregates:
            total_by_wd[agg.focus_date.isoweekday()] += agg.total_credited_minutes
        grand = sum(total_by_wd.values())
        if grand > 0:
            best_wd = max(total_by_wd, key=lambda k: total_by_wd[k])
            best_pct = round(total_by_wd[best_wd] / grand * 100)
            if best_pct > 40:
                day_names = {1: "Пн", 2: "Вт", 3: "Ср", 4: "Чт", 5: "Пт", 6: "Сб", 7: "Вс"}
                signals.append(
                    {
                        "id": "weekday_pattern",
                        "severity": "info",
                        "message": f"Один день ({day_names.get(best_wd, best_wd)}) даёт более 40% времени за 4 недели.",
                        "evidence": [
                            f"{best_pct}% фокус-времени за 28 дней в {day_names.get(best_wd, best_wd)}"
                        ],
                        "confidence": "medium",
                        "related_blocks": ["time_patterns"],
                    }
                )

    return signals[:6]


def _build_data_limits(
    has_profile: bool,
    history_days: int,
    sessions_count: int,
) -> list[str]:
    limits = ["screen_time_unavailable", "intentions_not_tracked"]
    if not has_profile:
        limits.append("no_profile")
    if history_days < _MIN_HISTORY_DAYS:
        limits.append("new_user")
    if sessions_count == 0:
        limits.append("no_finished_sessions")
    return limits


async def build_focus_snapshot(session: AsyncSession, user_id: uuid.UUID) -> dict:
    now_utc = datetime.now(timezone.utc)
    cutoff = (now_utc - timedelta(days=_WINDOW_DAYS)).date()

    profile_result = await session.execute(
        select(UserGamificationProfile).where(UserGamificationProfile.user_id == user_id)
    )
    profile = profile_result.scalar_one_or_none()

    if profile is None:
        generated_at = now_utc.isoformat()
        return {
            "snapshot_version": "focus_snapshot_v1",
            "generated_at": generated_at,
            "locale": _LOCALE,
            "timezone": "UTC",
            "app_description": {
                "name": "FocusFlow",
                "description": "Приложение для фокус-сессий и трекинга продуктивности",
            },
            "scope": {"window_days": _WINDOW_DAYS, "cutoff_date": cutoff.isoformat()},
            "top_signals": [
                {
                    "id": "new_user",
                    "severity": "info",
                    "message": "Первый день — установи план или начни первую сессию.",
                    "evidence": [],
                    "confidence": "high",
                    "related_blocks": [],
                }
            ],
            "today": {},
            "week_plan": {},
            "week_extremes": {},
            "load_realism": {},
            "focus_state": {},
            "sessions": {},
            "time_patterns": {},
            "rooms": {},
            "month": {},
            "comparisons": {},
            "intentions_results": {},
            "data_limits": [
                "new_user",
                "no_finished_sessions",
                "screen_time_unavailable",
                "intentions_not_tracked",
            ],
            "available_drilldowns": [],
        }

    tz = _safe_tz(profile.home_tz or "UTC")
    today = _today_local(tz)
    generated_at = now_utc.astimezone(tz).isoformat()

    agg_result = await session.execute(
        select(DailyFocusAggregate)
        .where(
            DailyFocusAggregate.user_id == user_id,
            DailyFocusAggregate.focus_date >= cutoff,
        )
        .order_by(DailyFocusAggregate.focus_date.asc())
    )
    aggregates: list[DailyFocusAggregate] = list(agg_result.scalars().all())

    sessions_result = await session.execute(
        select(FocusSession)
        .options(selectinload(FocusSession.room))
        .where(
            FocusSession.user_id == user_id,
            FocusSession.status == FocusSessionStatus.finished,
            FocusSession.session_day >= cutoff,
        )
        .order_by(FocusSession.session_day.asc())
    )
    finished_sessions: list[FocusSession] = list(sessions_result.scalars().all())

    week_cutoff = today - timedelta(days=7)
    tasks_result = await session.execute(
        select(Task).where(
            Task.user_id == user_id,
            Task.status == TaskStatus.DONE,
            Task.updated_at
            >= datetime.combine(week_cutoff, datetime.min.time()).replace(tzinfo=timezone.utc),
        )
    )
    tasks_done_7d = len(list(tasks_result.scalars().all()))

    plan_minutes = parse_plan_minutes(profile.plan_minutes_json)
    agg_by_date = {a.focus_date: a for a in aggregates}

    monday = _week_monday(today)
    prev_monday = monday - timedelta(days=7)

    aggregates_7d = [a for a in aggregates if monday <= a.focus_date <= today]
    aggregates_prev_7d = [a for a in aggregates if prev_monday <= a.focus_date < monday]

    history_days = (today - cutoff).days
    is_new_user = history_days < _MIN_HISTORY_DAYS or len(finished_sessions) == 0

    today_block = _build_today(today, agg_by_date, plan_minutes, tz)
    week_plan = _build_week_plan(today, agg_by_date, plan_minutes)
    week_extremes = _build_week_extremes(today, agg_by_date)

    window_weeks = max(1, _WINDOW_DAYS // 7)
    load_realism = _build_load_realism(aggregates, plan_minutes, window_weeks)
    focus_state = _build_focus_state(
        aggregates, aggregates_7d, aggregates_prev_7d, plan_minutes, profile
    )
    sessions_block = _build_sessions(finished_sessions, today, tz)
    time_patterns = _build_time_patterns(aggregates, finished_sessions, tz)
    rooms = _build_rooms(finished_sessions)
    month = _build_month(aggregates, today)
    comparisons = _build_comparisons(aggregates, today, plan_minutes)
    intentions_results = _build_intentions_results(tasks_done_7d)

    if is_new_user:
        top_signals = [
            {
                "id": "new_user",
                "severity": "info",
                "message": "Первый день — установи план или начни первую сессию.",
                "evidence": [],
                "confidence": "high",
                "related_blocks": [],
            }
        ]
    else:
        top_signals = _build_top_signals(
            today_block, week_plan, focus_state, rooms, time_patterns, aggregates, today
        )

    data_limits = _build_data_limits(
        has_profile=True,
        history_days=history_days,
        sessions_count=len(finished_sessions),
    )

    return {
        "snapshot_version": "focus_snapshot_v1",
        "generated_at": generated_at,
        "locale": _LOCALE,
        "timezone": profile.home_tz or "UTC",
        "app_description": {
            "name": "FocusFlow",
            "description": "Приложение для фокус-сессий и трекинга продуктивности",
        },
        "scope": {
            "window_days": _WINDOW_DAYS,
            "cutoff_date": cutoff.isoformat(),
            "current_day": today.isoformat(),
            "history_days_available": history_days,
        },
        "top_signals": top_signals,
        "today": today_block,
        "week_plan": week_plan,
        "week_extremes": week_extremes,
        "load_realism": load_realism,
        "focus_state": focus_state,
        "sessions": sessions_block,
        "time_patterns": time_patterns,
        "rooms": rooms,
        "month": month,
        "comparisons": comparisons,
        "intentions_results": intentions_results,
        "data_limits": data_limits,
        "available_drilldowns": [
            "get_focus_stats_slice",
            "compare_focus_periods",
            "evaluate_focus_plan",
        ],
    }
