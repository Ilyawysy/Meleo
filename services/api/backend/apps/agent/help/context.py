from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from backend.domain.focus.entities import FocusSession, FocusSessionStatus, UserBalance
from backend.domain.focus_rooms.entities import FocusRoom
from backend.domain.focus_rooms.task_entities import Task, TaskStatus
from backend.domain.gamification.entities import DailyFocusAggregate, UserGamificationProfile


class NoActiveRoomError(Exception):
    pass


class ProfileMissingError(Exception):
    pass


def _pluralize_days(n: int) -> str:
    n = abs(n)
    if n % 10 == 1 and n % 100 != 11:
        return "день"
    if 2 <= n % 10 <= 4 and not (12 <= n % 100 <= 14):
        return "дня"
    return "дней"


def _safe_tz(tz_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(tz_name)
    except Exception:
        return ZoneInfo("UTC")


_WEEKDAY_RU = {
    0: "Понедельник",
    1: "Вторник",
    2: "Среда",
    3: "Четверг",
    4: "Пятница",
    5: "Суббота",
    6: "Воскресенье",
}

_WEEKDAY_SHORT_RU = {
    0: "Пн",
    1: "Вт",
    2: "Ср",
    3: "Чт",
    4: "Пт",
    5: "Сб",
    6: "Вс",
}


def _parse_plan_minutes(plan_minutes_json: str) -> dict[int, int]:
    try:
        raw = json.loads(plan_minutes_json)
        return {int(k): int(v) for k, v in raw.items()}
    except Exception:
        return {}


async def build_help_app_context(session: AsyncSession, user_id: uuid.UUID) -> str:
    profile_result = await session.execute(
        select(UserGamificationProfile).where(UserGamificationProfile.user_id == user_id)
    )
    profile = profile_result.scalar_one_or_none()

    if profile is None:
        raise ProfileMissingError("User gamification profile not found")

    if profile.active_focus_room_id is None:
        raise NoActiveRoomError("No active focus room selected")

    tz = _safe_tz(profile.home_tz or "UTC")
    now_utc = datetime.now(timezone.utc)
    now_local = now_utc.astimezone(tz)
    today_date = now_local.date()
    weekday_0 = now_local.weekday()  # 0=Mon … 6=Sun
    weekday_1 = weekday_0 + 1  # 1=Mon … 7=Sun (matches plan_minutes_json keys)

    plan_minutes = _parse_plan_minutes(profile.plan_minutes_json)
    plan_today = plan_minutes.get(weekday_1, 0)
    is_focus_day = plan_today > 0

    active_room_result = await session.execute(
        select(FocusRoom)
        .options(selectinload(FocusRoom.tasks))
        .where(FocusRoom.id == profile.active_focus_room_id, FocusRoom.deleted.is_(False))
    )
    active_room = active_room_result.scalar_one_or_none()

    other_rooms_result = await session.execute(
        select(FocusRoom)
        .where(
            FocusRoom.user_id == user_id,
            FocusRoom.archived.is_(False),
            FocusRoom.deleted.is_(False),
            FocusRoom.id != profile.active_focus_room_id,
        )
        .order_by(FocusRoom.updated_at.desc())
        .limit(3)
    )
    other_rooms = list(other_rooms_result.scalars().all())

    cutoff_7d = now_utc - timedelta(days=7)
    sessions_result = await session.execute(
        select(FocusSession)
        .options(selectinload(FocusSession.room))
        .where(
            FocusSession.user_id == user_id,
            FocusSession.status == FocusSessionStatus.finished,
            FocusSession.started_at >= cutoff_7d,
        )
        .order_by(FocusSession.started_at.desc())
        .limit(5)
    )
    recent_sessions = list(sessions_result.scalars().all())

    week_monday = today_date - timedelta(days=weekday_0)
    week_agg_result = await session.execute(
        select(DailyFocusAggregate)
        .where(
            DailyFocusAggregate.user_id == user_id,
            DailyFocusAggregate.focus_date >= week_monday,
        )
        .order_by(DailyFocusAggregate.focus_date.asc())
    )
    week_aggs = list(week_agg_result.scalars().all())

    balance_result = await session.execute(
        select(UserBalance).where(UserBalance.user_id == user_id)
    )
    balance = balance_result.scalar_one_or_none()
    coins = balance.coins if balance else 0

    running_session_result = await session.execute(
        select(FocusSession)
        .where(
            FocusSession.user_id == user_id,
            FocusSession.status == FocusSessionStatus.running,
        )
        .limit(1)
    )
    running_session = running_session_result.scalar_one_or_none()

    agg_by_date = {a.focus_date: a.total_credited_minutes for a in week_aggs}
    done_today = agg_by_date.get(today_date, 0)
    remaining_today = max(0, plan_today - done_today) if plan_today > 0 else 0

    active_room_title = active_room.title if active_room else "неизвестная комната"

    if running_session:
        timer_status = "запущен"
    else:
        timer_status = "не запущен"

    active_room_updated_str = "—"
    if active_room and active_room.updated_at:
        active_room_updated_str = active_room.updated_at.astimezone(tz).strftime("%d.%m %H:%M")

    done_tasks: list[Task] = []
    next_tasks: list[Task] = []
    if active_room:
        all_tasks = [t for t in active_room.tasks if not t.deleted]
        done_tasks_all = [t for t in all_tasks if t.status == TaskStatus.DONE]
        _dt_min = datetime.min.replace(tzinfo=timezone.utc)
        done_sorted = sorted(
            done_tasks_all,
            key=lambda t: t.completed_at or _dt_min,
            reverse=True,
        )[:5]
        done_tasks = list(reversed(done_sorted))
        next_tasks = sorted(
            [t for t in all_tasks if t.status == TaskStatus.NOT_DONE],
            key=lambda t: t.sort_order,
        )[:5]

    first_next_task = next_tasks[0].title if next_tasks else None

    streak = profile.streak_current

    # ── APP DESCRIPTION ──────────────────────────────────────────
    sections: list[str] = []

    sections.append("APP CONTEXT")
    sections.append("")

    sections.append("APP DESCRIPTION")
    sections.append(
        "Приложение помогает пользователю держаться фокус-плана через фокус-таймер.\n"
        "Фокус-день — день недели, где запланировано конкретное количество фокус-времени.\n"
        "Комната — рабочий контекст пользователя с чек-листом.\n"
        "Активная комната — текущая комната, которую пользователь выбрал или использовал последней как основную для фокуса.\n"
        "Чек-лист показывает, что уже сделано и что можно делать дальше."
    )

    # ── IMPORTANT SIGNALS ────────────────────────────────────────
    weekday_name = _WEEKDAY_RU[weekday_0]
    focus_day_label = "фокус-день" if is_focus_day else "выходной"

    sig_lines = [
        f"Сегодня {weekday_name.lower()}, это {focus_day_label}.",
        f"План на сегодня: {plan_today} минут."
        if plan_today > 0
        else "План на сегодня: нет плана.",
        f"Сделано сегодня: {done_today} минут.",
    ]
    if plan_today > 0:
        sig_lines.append(f"Осталось сегодня: {remaining_today} минут.")
    sig_lines.append(f"Сейчас {now_local.strftime('%H:%M')}.")
    sig_lines.append(f"Таймер сейчас: {timer_status}.")
    sig_lines.append(f'Активная комната: "{active_room_title}".')
    if first_next_task:
        sig_lines.append(f'Первый следующий пункт в активной комнате: "{first_next_task}".')

    sections.append("")
    sections.append("IMPORTANT SIGNALS")
    sections.append("\n".join(sig_lines))

    # ── FOCUS PLAN ───────────────────────────────────────────────
    plan_lines = ["Недельный фокус-план:"]
    for d in range(7):
        short = _WEEKDAY_SHORT_RU[d]
        plan_min = plan_minutes.get(d + 1, 0)
        plan_lines.append(f"{short} — {plan_min} минут" if plan_min > 0 else f"{short} — выходной")

    plan_lines.append("")
    plan_lines.append("Сегодня:")
    plan_lines.append(f"{weekday_name}.")
    plan_lines.append(f"Фокус-день: {'да' if is_focus_day else 'нет'}.")
    plan_lines.append(f"План: {plan_today} минут." if plan_today > 0 else "План: нет плана.")
    plan_lines.append(f"Сделано: {done_today} минут.")
    if plan_today > 0:
        plan_lines.append(f"Осталось: {remaining_today} минут.")
    plan_lines.append(f"Таймер сейчас: {timer_status}.")

    sessions_today = [
        s
        for s in recent_sessions
        if s.started_at and s.started_at.astimezone(tz).date() == today_date
    ]
    if sessions_today:
        plan_lines.append(f"Таймер сегодня запускался: {len(sessions_today)} раз.")
    else:
        plan_lines.append("Таймер сегодня запускался: нет.")

    sections.append("")
    sections.append("FOCUS PLAN")
    sections.append("\n".join(plan_lines))

    # ── ACTIVE ROOM ──────────────────────────────────────────────
    room_lines = [
        f'Название: "{active_room_title}".',
        f"Последнее использование: {active_room_updated_str}.",
    ]

    if done_tasks:
        room_lines.append("")
        room_lines.append("Чек-лист — выполнено:")
        for t in done_tasks:
            room_lines.append(f'- "{t.title}"')

    if next_tasks:
        room_lines.append("")
        room_lines.append("Чек-лист — следующее:")
        for t in next_tasks:
            room_lines.append(f'- "{t.title}"')

    sections.append("")
    sections.append("ACTIVE ROOM")
    sections.append("\n".join(room_lines))

    # ── OTHER ROOMS ──────────────────────────────────────────────
    if other_rooms:
        other_lines = []
        for r in other_rooms:
            last_use = r.updated_at.astimezone(tz).strftime("%d.%m %H:%M") if r.updated_at else "—"
            other_lines.append(f'{r.id} — "{r.title}", последнее использование: {last_use}.')

        sections.append("")
        sections.append("OTHER ROOMS")
        sections.append("\n".join(other_lines))

    # ── FOCUS HISTORY ────────────────────────────────────────────
    if recent_sessions:
        hist_lines = ["Последние сессии:"]
        for s in recent_sessions:
            if not s.started_at:
                continue
            local_dt = s.started_at.astimezone(tz)
            if local_dt.date() == today_date:
                when = "сегодня"
            else:
                when = local_dt.strftime("%d.%m")
            dur = f"{s.credited_minutes} минут" if s.credited_minutes else "—"
            room_title = s.room.title if s.room else None
            if room_title:
                hist_lines.append(f'- {when}: {dur}, комната "{room_title}"')
            else:
                hist_lines.append(f"- {when}: {dur}")

        total_credited = sum(s.credited_minutes for s in recent_sessions if s.credited_minutes)
        count = sum(1 for s in recent_sessions if s.credited_minutes)
        if count > 0:
            avg = total_credited // count
            hist_lines.append(f"Средняя недавняя сессия: {avg} минут.")

        sections.append("")
        sections.append("FOCUS HISTORY")
        sections.append("\n".join(hist_lines))

    # ── WEEK FOCUS ───────────────────────────────────────────────
    if week_aggs:
        week_lines = []
        for d in range(7):
            day_date = week_monday + timedelta(days=d)
            if day_date > today_date:
                break
            short = _WEEKDAY_SHORT_RU[d]
            done_min = agg_by_date.get(day_date, 0)
            plan_min = plan_minutes.get(d + 1, 0)
            week_lines.append(f"{short}: {done_min}/{plan_min}.")

        if week_lines:
            sections.append("")
            sections.append("WEEK FOCUS")
            sections.append("\n".join(week_lines))

    # ── APP STATE ────────────────────────────────────────────────
    sections.append("")
    sections.append("APP STATE")
    sections.append(f"Серия: {streak} {_pluralize_days(streak)}.\nМонеты: {coins}.")

    return "\n".join(sections)
