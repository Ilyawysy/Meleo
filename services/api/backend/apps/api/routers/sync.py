from __future__ import annotations

import asyncio
import uuid
from datetime import date, datetime, timezone
from time import perf_counter
from typing import Any, Optional

from fastapi import APIRouter, Depends, Query, Request, Response
from pydantic import BaseModel
from sqlalchemy import and_, exists, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.chat.entities import ChatRole
from backend.domain.focus.entities import FocusSessionStatus
from backend.domain.notifications.entities import NotificationRecurrence
from backend.domain.gamification.calculator import subcoins_to_display
from backend.domain.gamification.service import GamificationService
from backend.infrastructure.repositories.focus_repository import SqlAlchemyFocusRepository
from backend.infrastructure.repositories.gamification_repository import (
    SqlAlchemyGamificationRepository,
)
from backend.domain.sync.cursor import DomainCursor, SyncCursor

from backend.domain.sync.service import (
    get_all_focus_task_segments,
    get_checklist_item_changes,
    get_focus_room_changes,
    get_focus_session_changes,
    get_focus_snapshot,
    get_message_changes,
    get_notification_changes,
    get_subscription_snapshot,
    get_task_changes,
)
from backend.domain.announcements.entities import (
    DeveloperAnnouncement,
    UserAnnouncementRead,
)
from backend.domain.users.entities import User
from backend.domain.users.state_version import UserStateVersion
from backend.infrastructure.database.session import SessionLocal, get_session
from backend.infrastructure.etag import etag_matches
from backend.infrastructure.logging import get_log_context, get_logger
from backend.infrastructure.rate_limit import rate_limit_sync
from backend.infrastructure.security.auth import get_current_user_id

router = APIRouter(prefix="/api/v1", tags=["sync"])
logger = get_logger("sync")


# --- Response schemas ---


class SyncFocusRoomOut(BaseModel):
    id: uuid.UUID
    title: str
    color: str
    type: str
    archived: bool
    archived_at: Optional[datetime] = None
    sort_order: int = 0
    sprint_goal: Optional[str] = None
    sprint_deadline: Optional[datetime] = None
    sprint_total_hours: Optional[int] = None
    focus_duration_min: Optional[int] = None
    break_min: Optional[int] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class SyncTaskOut(BaseModel):
    id: uuid.UUID
    room_id: uuid.UUID
    title: str
    description: Optional[str] = None
    status: str
    sort_order: int = 0
    deleted: bool
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class SyncNotificationOut(BaseModel):
    id: uuid.UUID
    title: str
    time: datetime
    recurrence: NotificationRecurrence
    deleted: bool
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class SyncMessageOut(BaseModel):
    id: uuid.UUID
    thread_id: uuid.UUID
    role: ChatRole
    content: str
    order: int
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class SyncFocusSessionOut(BaseModel):
    id: uuid.UUID
    planned_duration_sec: int
    status: FocusSessionStatus
    active_elapsed_sec: int
    last_state_change_at: datetime
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    room_id: uuid.UUID
    task_id: Optional[uuid.UUID] = None
    earned_coins: float  # display coins (subcoins / 10)
    credited_minutes: Optional[int] = None
    earned_xp: int = 0
    session_day: Optional[date] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class SyncBalanceOut(BaseModel):
    coins: float


class SyncShopItemOut(BaseModel):
    id: str
    name: str
    category: str
    price: float
    owned: bool
    required_level: int = 0


class SyncGamificationProfileOut(BaseModel):
    xp: int
    level: int
    xp_to_next_level: int
    streak_current: int
    home_tz: str
    day_cutoff_hour: int
    plan_minutes: dict[int, int]
    recovery_days_remaining: int
    minimal_mode: bool
    streak_finalized_through: Optional[str] = None
    fair_play_accepted: bool
    coins: float
    shield_unlocked: bool = False
    shield_charges: int = 0
    shield_recharge_progress: int = 0
    recovery_mode: Optional[str] = None
    focus_duration_min: int = 25
    short_break_min: int = 5
    long_break_min: int = 15
    sessions_before_long_break: int = 4
    auto_start_break: bool = True
    auto_start_next_session: bool = False
    adjust_duration_after_session: bool = False
    stat_widget_config: Optional[str] = None
    active_focus_room_id: Optional[uuid.UUID] = None


class SyncSubscriptionOut(BaseModel):
    tier: str
    chat_messages_used: int
    chat_messages_limit: Optional[int] = None


class SyncDailyStatOut(BaseModel):
    date: str
    credited_minutes: int
    xp_earned: int
    coins_earned: int
    session_count: int
    is_streak_day: bool
    recovery_mode: Optional[str] = None


class SyncMascotSkinOut(BaseModel):
    id: int
    slug: str
    tier: str
    price_coins: int
    color1: str
    color2: str
    color3: str
    color4: str
    sort_order: int


class SyncFocusSnapshotOut(BaseModel):
    balance: SyncBalanceOut
    owned_item_ids: list[str] = []
    shop_items: list[SyncShopItemOut] = []  # deprecated, kept empty
    profile: Optional[SyncGamificationProfileOut] = None
    subscription: Optional[SyncSubscriptionOut] = None
    daily_stats: list[SyncDailyStatOut] = []
    active_items: dict[str, str | None] = {}
    mascot_skins: list[SyncMascotSkinOut] = []
    owned_mascot_skin_ids: list[int] = []
    active_mascot_skin_id: Optional[int] = None


class SyncChecklistItemOut(BaseModel):
    id: uuid.UUID
    task_id: uuid.UUID
    title: str
    is_done: bool
    sort_order: int
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class SyncFocusTaskSegmentOut(BaseModel):
    id: uuid.UUID
    session_id: uuid.UUID
    task_id: uuid.UUID
    started_at: datetime
    ended_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class SyncAnnouncementOut(BaseModel):
    id: str
    title: str
    message: str
    created_at: datetime


class SyncChanges(BaseModel):
    focus_rooms: list[SyncFocusRoomOut] = []
    tasks: list[SyncTaskOut] = []
    notifications: list[SyncNotificationOut]
    messages: list[SyncMessageOut]
    focus_sessions: list[SyncFocusSessionOut] = []
    focus_snapshot: Optional[SyncFocusSnapshotOut] = None
    checklist_items: list[SyncChecklistItemOut] = []
    focus_task_segments: list[SyncFocusTaskSegmentOut] = []
    announcements: list[SyncAnnouncementOut] = []


class HasMore(BaseModel):
    focus_rooms: bool = False
    tasks: bool = False
    notifications: bool = False
    messages: bool = False
    focus_sessions: bool = False
    checklist_items: bool = False


class DomainVersions(BaseModel):
    notifications: int
    messages: int
    focus: int


class SyncResponse(BaseModel):
    cursor: str
    server_time: datetime
    changes: SyncChanges
    has_more: HasMore
    versions: DomainVersions
    onboarding_completed: bool = False


# --- Helpers ---


async def get_onboarding_flag(session: AsyncSession, user_id: uuid.UUID) -> bool:
    result = await session.execute(select(User.onboarding_completed_at).where(User.id == user_id))
    return result.scalar_one_or_none() is not None


# --- Endpoints ---


def _focus_session_to_sync_out(s: Any) -> SyncFocusSessionOut:
    """Convert FocusSession ORM to SyncFocusSessionOut with subcoin→display."""
    return SyncFocusSessionOut(
        id=s.id,
        planned_duration_sec=s.planned_duration_sec,
        status=s.status,
        active_elapsed_sec=s.active_elapsed_sec,
        last_state_change_at=s.last_state_change_at,
        started_at=s.started_at,
        ended_at=s.ended_at,
        room_id=s.room_id,
        task_id=s.task_id,
        earned_coins=subcoins_to_display(s.earned_coins),
        credited_minutes=s.credited_minutes,
        earned_xp=s.earned_xp,
        session_day=s.session_day,
        created_at=s.created_at,
        updated_at=s.updated_at,
    )


@router.get("/sync", response_model=SyncResponse)
async def sync_changes(
    request: Request,
    cursor: Optional[str] = Query(None, description="Encoded sync cursor"),
    limit: int = Query(200, ge=1, le=500, description="Max items per domain"),
    nv: Optional[int] = Query(None, description="Client notifications_version; skip if matches"),
    mv: Optional[int] = Query(None, description="Client messages_version; skip if matches"),
    fv: Optional[int] = Query(None, description="Client focus_version; skip if matches"),
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> Any:
    """Aggregated sync endpoint: fetches delta changes across all domains.

    Returns 304 Not Modified if composite ETag matches (nothing changed).
    When per-domain version params (tv/nv/mv/fv) are provided, skips SELECTs
    for domains whose version already matches the server, reducing DB work.
    """
    t_total_start = perf_counter()

    # 1. Rate limit (skipped in LOADTEST_MODE)
    from backend.infrastructure.config import settings

    if not (settings.LOADTEST_MODE and settings.ENV == "dev"):
        await rate_limit_sync(request, user_id=str(current_user_id))

    # 2. Decode cursor
    sync_cursor = SyncCursor.decode(cursor) if cursor else SyncCursor.initial()

    # 3. Get user state versions (single O(1) PK lookup)
    t_ver = perf_counter()
    user_row = await session.get(UserStateVersion, current_user_id)
    notif_v = user_row.notifications_version if user_row else 0
    msgs_v = user_row.messages_version if user_row else 0
    focus_v = user_row.focus_version if user_row else 0
    ver_dur_ms = (perf_counter() - t_ver) * 1000

    # 4. Composite ETag check — 304 when nothing changed
    etag = f'"{notif_v}-{msgs_v}-{focus_v}"'
    client_etag = request.headers.get("If-None-Match")
    if etag_matches(client_etag, etag):
        return Response(
            status_code=304,
            headers={
                "ETag": etag,
                "Cache-Control": "private, max-age=15",
            },
        )

    # 5. Per-domain version check: skip SELECTs for unchanged domains
    need_notifs = nv is None or nv != notif_v
    need_msgs = mv is None or mv != msgs_v
    need_focus = fv is None or fv != focus_v

    # ── Timing instrumentation ──
    timings: list[str] = [f"db_versions;dur={ver_dur_ms:.1f}"]

    # 5b. Fetch onboarding flag (only on 200 path)
    t0_onb = perf_counter()
    onboarding_completed = await get_onboarding_flag(session, current_user_id)
    timings.append(f"db_onboarding;dur={(perf_counter() - t0_onb) * 1000:.1f}")

    def _t() -> float:
        return perf_counter()

    def _record(name: str, start: float) -> None:
        dur_ms = (perf_counter() - start) * 1000
        timings.append(f"{name};dur={dur_ms:.1f}")

    # 6. Fetch changes only for domains that actually changed (sequential, single session)
    focus_rooms: list[Any] = []
    tasks: list[Any] = []
    notifications: list[Any] = []
    messages: list[Any] = []
    focus_sessions: list[Any] = []
    checklist_items: list[Any] = []
    notif_new = None
    msg_new = None
    focus_new = None

    focus_task_segments: list[Any] = []

    if need_notifs:
        t0 = _t()
        notifications, notif_new = await get_notification_changes(
            session, current_user_id, sync_cursor.notifications, limit
        )
        _record("db_notifications", t0)
    if need_msgs:
        t0 = _t()
        messages, msg_new = await get_message_changes(
            session, current_user_id, sync_cursor.messages, limit
        )
        _record("db_messages", t0)
    if need_focus:
        # Semaphore(2): per-request limit on parallel DB sessions.
        # With main session (Depends), each request holds up to 3 connections.
        # Pool: pool_size=10, max_overflow=5 → 15 ceiling supports ~5 concurrent /sync.
        _sem = asyncio.Semaphore(2)

        async def _run_with_session(name: str, factory: Any) -> Any:
            async with _sem:
                async with SessionLocal() as s:
                    t0_inner = perf_counter()
                    result = await factory(s)
                    timings.append(f"{name};dur={(perf_counter() - t0_inner) * 1000:.1f}")
                    return result

        t0 = _t()
        (
            (focus_rooms, _rooms_cursor),
            (tasks, _tasks_cursor),
            (checklist_items, _chk_cursor),
            (focus_sessions, focus_new),
            focus_task_segments,
        ) = await asyncio.gather(
            _run_with_session(
                "db_focus_rooms",
                lambda s: get_focus_room_changes(s, current_user_id, sync_cursor.focus, limit),
            ),
            _run_with_session(
                "db_tasks",
                lambda s: get_task_changes(s, current_user_id, sync_cursor.focus, limit),
            ),
            _run_with_session(
                "db_checklist",
                lambda s: get_checklist_item_changes(s, current_user_id, sync_cursor.focus, limit),
            ),
            _run_with_session(
                "db_focus_sessions",
                lambda s: get_focus_session_changes(s, current_user_id, sync_cursor.focus, limit),
            ),
            _run_with_session(
                "db_focus_segments",
                lambda s: get_all_focus_task_segments(s, current_user_id),
            ),
        )
        _record("db_focus_parallel", t0)
    # 6a. Announcements (snapshot of unread, not cursor-based)
    t0 = _t()
    ann_stmt = (
        select(DeveloperAnnouncement)
        .where(
            and_(
                DeveloperAnnouncement.is_active,
                or_(
                    DeveloperAnnouncement.expires_at.is_(None),
                    DeveloperAnnouncement.expires_at > func.now(),
                ),
                or_(
                    DeveloperAnnouncement.target_user_ids.is_(None),
                    DeveloperAnnouncement.target_user_ids == [],
                    DeveloperAnnouncement.target_user_ids.contains([current_user_id]),
                ),
                ~exists(
                    select(1).where(
                        UserAnnouncementRead.announcement_id == DeveloperAnnouncement.id,
                        UserAnnouncementRead.user_id == current_user_id,
                    )
                ),
            )
        )
        .order_by(DeveloperAnnouncement.created_at.desc())
    )
    ann_rows = (await session.execute(ann_stmt)).scalars().all()
    _record("db_announcements", t0)

    # 6b. Focus snapshot (balance/owned_ids/profile) — only when focus_version changed
    focus_snapshot_out = None
    if need_focus:
        # Roll forward streak evaluation before reading snapshot
        focus_repo = SqlAlchemyFocusRepository(session, current_user_id)
        gam_repo = SqlAlchemyGamificationRepository(session, current_user_id)
        gam_service = GamificationService(gam_repo, focus_repo, session, current_user_id)
        t0 = _t()
        await gam_service.roll_forward()
        _record("roll_forward", t0)

        t0 = _t()
        snapshot = await get_focus_snapshot(session, current_user_id)
        _record("db_focus_snapshot", t0)
        t0 = _t()
        sub_data = await get_subscription_snapshot(session, current_user_id)
        _record("db_subscription", t0)
        t0 = _t()
        daily_stats_raw = await gam_service.get_daily_stats(62)
        _record("db_daily_stats", t0)
        t0 = _t()
        active_items_raw = await focus_repo.get_active_items()
        _record("db_active_items", t0)
        t0 = _t()
        catalog_items, owned_ids = await focus_repo.list_shop_items_with_owned_ids()
        _record("db_shop_catalog", t0)
        t0 = _t()
        from backend.domain.mascot_skins.service import MascotSkinService

        skin_service = MascotSkinService(session)
        mascot_skins = await skin_service.list_catalog()
        owned_skin_ids = await skin_service.list_owned_skin_ids(current_user_id)
        active_skin_id = await skin_service.get_active_skin_id(current_user_id)
        _record("db_mascot_skins", t0)
        active_items_map: dict[str, str | None] = {
            "aura": None,
            "skin": None,
            "environment": None,
        }
        for ai in active_items_raw:
            if ai.category in active_items_map:
                active_items_map[ai.category] = str(ai.item_id)
        profile_out = None
        if snapshot.profile:
            profile_out = SyncGamificationProfileOut(**snapshot.profile)
        focus_snapshot_out = SyncFocusSnapshotOut(
            balance=SyncBalanceOut(coins=snapshot.balance_coins),
            owned_item_ids=snapshot.owned_item_ids,
            shop_items=[
                SyncShopItemOut(
                    id=str(item.id),
                    name=item.name,
                    category=item.category.value,
                    price=item.price / 10,
                    owned=item.id in owned_ids,
                    required_level=item.required_level,
                )
                for item in catalog_items
            ],
            profile=profile_out,
            subscription=SyncSubscriptionOut(**sub_data),
            daily_stats=[SyncDailyStatOut(**s) for s in daily_stats_raw],
            active_items=active_items_map,
            mascot_skins=[
                SyncMascotSkinOut(
                    id=s.id,
                    slug=s.slug,
                    tier=s.tier.value,
                    price_coins=s.price_coins,
                    color1=s.color1,
                    color2=s.color2,
                    color3=s.color3,
                    color4=s.color4,
                    sort_order=s.sort_order,
                )
                for s in mascot_skins
            ],
            owned_mascot_skin_ids=sorted(owned_skin_ids),
            active_mascot_skin_id=active_skin_id,
        )

    # 7. Build new cursor — MAX(updated_at, id) across all 5 focus sub-fetchers
    all_focus_results = [focus_rooms, tasks, checklist_items, focus_sessions, focus_task_segments]
    any_focus_hit_limit = any(len(rs) >= limit for rs in all_focus_results)
    if need_focus:
        if any_focus_hit_limit:
            new_focus_cursor = sync_cursor.focus
            has_more_focus = True
        else:
            all_focus_items = [r for rs in all_focus_results for r in rs]
            if all_focus_items:
                max_pos = max(
                    (
                        (r.updated_at, r.id)
                        for r in all_focus_items
                        if hasattr(r, "updated_at") and r.updated_at is not None
                    ),
                    default=(sync_cursor.focus.updated_at, sync_cursor.focus.last_id),
                )
                new_focus_cursor = DomainCursor(updated_at=max_pos[0], last_id=max_pos[1])
            else:
                new_focus_cursor = sync_cursor.focus
            has_more_focus = False
    else:
        new_focus_cursor = sync_cursor.focus
        has_more_focus = False

    new_cursor = SyncCursor(
        notifications=notif_new or sync_cursor.notifications,
        messages=msg_new or sync_cursor.messages,
        focus=new_focus_cursor,
    )

    # 8. Has more flags (skipped domains always False)
    has_more = HasMore(
        focus_rooms=has_more_focus,
        tasks=len(tasks) >= limit,
        notifications=len(notifications) >= limit,
        messages=len(messages) >= limit,
        focus_sessions=len(focus_sessions) >= limit,
        checklist_items=len(checklist_items) >= limit,
    )

    # 9. Logging (always log with timings for diagnostics)
    ctx = get_log_context()
    timing_dict = {}
    for entry in timings:
        name, dur = entry.split(";dur=")
        timing_dict[name] = float(dur)
    logger.info(
        "sync_completed",
        request_id=ctx["request_id"],
        user_id=ctx["user_id"],
        focus_rooms=len(focus_rooms),
        tasks=len(tasks),
        notifications=len(notifications),
        messages=len(messages),
        focus_sessions=len(focus_sessions),
        checklist_items=len(checklist_items),
        focus_task_segments=len(focus_task_segments),
        has_cursor=cursor is not None,
        skipped_notifs=not need_notifs,
        skipped_msgs=not need_msgs,
        skipped_focus=not need_focus,
        **timing_dict,
    )

    # 10. Response
    t_serial = _t()
    resp = SyncResponse(
        cursor=new_cursor.encode(),
        server_time=datetime.now(timezone.utc),
        changes=SyncChanges(
            focus_rooms=[SyncFocusRoomOut.model_validate(r) for r in focus_rooms],
            tasks=[SyncTaskOut.model_validate(t) for t in tasks],
            notifications=[SyncNotificationOut.model_validate(n) for n in notifications],
            messages=[SyncMessageOut.model_validate(m) for m in messages],
            focus_sessions=[_focus_session_to_sync_out(s) for s in focus_sessions],
            focus_snapshot=focus_snapshot_out,
            checklist_items=[SyncChecklistItemOut.model_validate(c) for c in checklist_items],
            focus_task_segments=[
                SyncFocusTaskSegmentOut.model_validate(s) for s in focus_task_segments
            ],
            announcements=[
                SyncAnnouncementOut(
                    id=str(a.id),
                    title=a.title,
                    message=a.message,
                    created_at=a.created_at,
                )
                for a in ann_rows
            ],
        ),
        has_more=has_more,
        versions=DomainVersions(
            notifications=notif_v,
            messages=msgs_v,
            focus=focus_v,
        ),
        onboarding_completed=onboarding_completed,
    )
    body = resp.model_dump_json()
    _record("serialize", t_serial)

    total_ms = (perf_counter() - t_total_start) * 1000
    timings.append(f"total;dur={total_ms:.1f}")

    return Response(
        content=body,
        media_type="application/json",
        headers={
            "ETag": etag,
            "Cache-Control": "private, max-age=15",
            "Server-Timing": ", ".join(timings),
        },
    )
