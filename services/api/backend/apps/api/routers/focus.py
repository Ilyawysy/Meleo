from __future__ import annotations

import enum
import uuid
from datetime import date, datetime
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.focus.entities import (
    FocusSessionStatus,
    ShopItem as ShopItemEntity,
    ShopItemCategory,
)
from backend.domain.focus.service import (
    FocusService,
    InsufficientFundsError,
    InvalidSessionTransitionError,
)
from backend.domain.gamification.calculator import (
    compute_xp_level,
    parse_plan_minutes,
    subcoins_to_display,
    xp_to_next_level,
)
from backend.domain.gamification.service import GamificationService
from backend.infrastructure.database.session import get_session
from backend.infrastructure.idempotency import IdempotencyResult, check_idempotency
from backend.infrastructure.logging import get_logger, should_log_success
from backend.infrastructure.repositories import SqlAlchemyFocusRepository
from backend.infrastructure.repositories.focus_room_repository import (
    SqlAlchemyFocusRoomRepository,
    SqlAlchemyTaskRepository as SqlAlchemyRoomTaskRepository,
)
from backend.infrastructure.repositories.gamification_repository import (
    SqlAlchemyGamificationRepository,
)
from backend.infrastructure.security.auth import get_current_user_id

router = APIRouter(prefix="/api/v1", tags=["focus"])
logger = get_logger("focus_api")


class BalanceOut(BaseModel):
    coins: float  # display coins (subcoins / 10)


class ShopItemOut(BaseModel):
    id: uuid.UUID
    name: str
    category: ShopItemCategory
    price: float  # display coins (subcoins / 10)
    owned: bool
    purchased_at: Optional[datetime] = None
    required_level: int = 0

    model_config = {"from_attributes": True}


class GamificationProfileSnapshotOut(BaseModel):
    xp: int
    level: int
    xp_to_next_level: int
    streak_current: int
    plan_minutes: dict[int, int]
    home_tz: str
    day_cutoff_hour: int
    shield_unlocked: bool
    shield_charges: int
    shield_recharge_progress: int
    recovery_days_remaining: int
    minimal_mode: bool
    coins: float
    recovery_mode: Optional[str] = None
    stat_widget_config: Optional[str] = None


class ActiveItemsOut(BaseModel):
    active_items: dict[str, uuid.UUID | None]


class ActivateItemRequest(BaseModel):
    item_id: uuid.UUID


class DeactivateItemRequest(BaseModel):
    category: str


class FocusSnapshotOut(BaseModel):
    balance: BalanceOut
    shop_items: list[ShopItemOut]
    profile: GamificationProfileSnapshotOut
    active_items: dict[str, uuid.UUID | None] = {}


class PurchaseRequest(BaseModel):
    item_id: uuid.UUID


class PurchaseResponse(BaseModel):
    balance: BalanceOut
    item: ShopItemOut


class FocusSessionCreate(BaseModel):
    planned_duration_sec: int = Field(..., ge=300, le=10800)
    task_id: Optional[uuid.UUID] = None
    room_id: uuid.UUID

    @field_validator("planned_duration_sec")
    @classmethod
    def validate_duration(cls, value: int) -> int:
        if value % 300 != 0:
            raise ValueError("planned_duration_sec must be in 5-minute steps")
        return value


class FocusSessionOut(BaseModel):
    id: uuid.UUID
    planned_duration_sec: int
    status: FocusSessionStatus
    active_elapsed_sec: int
    last_state_change_at: datetime
    started_at: Optional[datetime]
    ended_at: Optional[datetime]
    room_id: uuid.UUID
    task_id: Optional[uuid.UUID]
    earned_coins: float  # display coins (subcoins / 10)
    credited_minutes: Optional[int] = None
    earned_xp: int = 0
    session_day: Optional[date] = None

    model_config = {"from_attributes": True}


class FocusSessionAction(str, enum.Enum):
    finish = "finish"
    cancel = "cancel"


class FocusSessionStateUpdate(BaseModel):
    action: FocusSessionAction


class FocusSessionStateResponse(BaseModel):
    session: FocusSessionOut
    balance: Optional[BalanceOut] = None


class BatchActionItem(BaseModel):
    action: FocusSessionAction
    elapsed_override_sec: Optional[int] = Field(None, ge=0)


class TaskSegmentIn(BaseModel):
    task_id: uuid.UUID
    started_at: datetime
    ended_at: Optional[datetime] = None


class BatchActionsRequest(BaseModel):
    actions: list[BatchActionItem] = Field(..., min_length=1, max_length=50)
    segments: Optional[list[TaskSegmentIn]] = None


class BatchActionResult(BaseModel):
    index: int
    ok: bool
    error: Optional[str] = None


class BatchActionsResponse(BaseModel):
    session: FocusSessionOut
    balance: Optional[BalanceOut] = None
    results: list[BatchActionResult]


class FocusSessionTaskUpdate(BaseModel):
    task_id: Optional[uuid.UUID] = None


def get_service(
    db_session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> FocusService:
    repo = SqlAlchemyFocusRepository(db_session, current_user_id)
    gam_repo = SqlAlchemyGamificationRepository(db_session, current_user_id)
    gam_service = GamificationService(gam_repo, repo, db_session, current_user_id)
    return FocusService(repo, db_session, current_user_id, gamification_service=gam_service)


@router.get("/focus/snapshot", response_model=FocusSnapshotOut)
async def get_focus_snapshot(
    service: FocusService = Depends(get_service),
) -> FocusSnapshotOut:
    try:
        gam_service = service._gamification
        gam_repo = gam_service._gam_repo

        balance = await service.get_balance()
        items, owned_ids = await service.list_shop_items_with_ownership()
        profile = await gam_service.roll_forward()

        coins_subcoins = balance.coins
        level = compute_xp_level(profile.xp)
        plan_minutes = parse_plan_minutes(profile.plan_minutes_json)

        today = gam_service._user_today(profile)
        agg = await gam_repo.get_aggregate(today)
        recovery_mode = agg.recovery_mode if agg else None

        active_map = await service.get_active_items()
        shop_items = [
            ShopItemOut(
                id=item.id,
                name=item.name,
                category=item.category,
                price=subcoins_to_display(item.price),
                owned=item.id in owned_ids,
                required_level=item.required_level,
            )
            for item in items
        ]

        return FocusSnapshotOut(
            balance=BalanceOut(coins=subcoins_to_display(balance.coins)),
            shop_items=shop_items,
            active_items={
                "aura": active_map.get("aura"),
                "skin": active_map.get("skin"),
                "environment": active_map.get("environment"),
            },
            profile=GamificationProfileSnapshotOut(
                xp=profile.xp,
                level=level,
                xp_to_next_level=xp_to_next_level(profile.xp),
                streak_current=profile.streak_current,
                plan_minutes=plan_minutes,
                home_tz=profile.home_tz,
                day_cutoff_hour=profile.day_cutoff_hour,
                shield_unlocked=profile.shield_unlocked,
                shield_charges=profile.shield_charges,
                shield_recharge_progress=profile.shield_recharge_progress,
                recovery_days_remaining=profile.recovery_days_remaining,
                minimal_mode=profile.minimal_mode,
                coins=subcoins_to_display(coins_subcoins),
                recovery_mode=recovery_mode,
                stat_widget_config=profile.stat_widget_config,
            ),
        )
    except Exception as exc:
        logger.exception("focus_snapshot_failed", error=str(exc))
        raise


@router.get("/balance", response_model=BalanceOut)
async def get_balance(service: FocusService = Depends(get_service)) -> BalanceOut:
    try:
        balance = await service.get_balance()
        return BalanceOut(coins=subcoins_to_display(balance.coins))
    except Exception as exc:
        logger.exception("focus_balance_failed", error=str(exc))
        raise


class CatalogItemOut(BaseModel):
    id: uuid.UUID
    name: str
    category: ShopItemCategory
    price: float
    required_level: int = 0

    model_config = {"from_attributes": True}


@router.get("/shop/catalog", response_model=list[CatalogItemOut])
async def get_shop_catalog(
    request: Request,
    db_session: AsyncSession = Depends(get_session),
) -> Any:
    """Public shop catalog (no auth required for browsing). Supports ETag caching."""
    max_updated = await db_session.execute(select(func.max(ShopItemEntity.updated_at)))
    max_ts = max_updated.scalar()
    etag = f'"{hash(max_ts)}"' if max_ts else '"empty"'

    client_etag = request.headers.get("If-None-Match")
    if client_etag and client_etag == etag:
        return Response(
            status_code=304,
            headers={"ETag": etag, "Cache-Control": "private, max-age=3600"},
        )

    result = await db_session.execute(
        select(ShopItemEntity).order_by(ShopItemEntity.created_at.asc())
    )
    items = result.scalars().all()
    catalog = [
        CatalogItemOut(
            id=item.id,
            name=item.name,
            category=item.category,
            price=subcoins_to_display(item.price),
            required_level=item.required_level,
        )
        for item in items
    ]
    body = "[" + ",".join(c.model_dump_json() for c in catalog) + "]"
    return Response(
        content=body,
        media_type="application/json",
        headers={"ETag": etag, "Cache-Control": "private, max-age=3600"},
    )


@router.get("/shop/items", response_model=list[ShopItemOut])
async def list_shop_items(service: FocusService = Depends(get_service)) -> list[ShopItemOut]:
    try:
        items, owned_ids = await service.list_shop_items_with_ownership()
    except Exception as exc:
        logger.exception("focus_shop_list_failed", error=str(exc))
        raise
    result: list[ShopItemOut] = []
    for item in items:
        result.append(
            ShopItemOut(
                id=item.id,
                name=item.name,
                category=item.category,
                price=subcoins_to_display(item.price),
                owned=item.id in owned_ids,
                required_level=item.required_level,
            )
        )
    return result


@router.post("/shop/purchase", response_model=PurchaseResponse)
async def purchase_item(
    payload: PurchaseRequest, service: FocusService = Depends(get_service)
) -> PurchaseResponse:
    try:
        balance, owned, item = await service.purchase_item(payload.item_id)
    except InsufficientFundsError as exc:
        logger.warning(
            "focus_shop_purchase_insufficient_funds",
            item_id=str(payload.item_id),
            error=str(exc),
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except ValueError as exc:
        logger.warning(
            "focus_shop_purchase_not_found",
            item_id=str(payload.item_id),
            error=str(exc),
        )
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except Exception as exc:
        logger.exception("focus_shop_purchase_failed", item_id=str(payload.item_id), error=str(exc))
        raise

    return PurchaseResponse(
        balance=BalanceOut(coins=subcoins_to_display(balance.coins)),
        item=ShopItemOut(
            id=item.id,
            name=item.name,
            category=item.category,
            price=subcoins_to_display(item.price),
            owned=True,
            purchased_at=owned.purchased_at,
            required_level=item.required_level,
        ),
    )


@router.get("/shop/active-items", response_model=ActiveItemsOut)
async def get_active_items(service: FocusService = Depends(get_service)) -> ActiveItemsOut:
    active = await service.get_active_items()
    return ActiveItemsOut(
        active_items={
            "aura": active.get("aura"),
            "skin": active.get("skin"),
            "environment": active.get("environment"),
        }
    )


@router.post("/shop/activate", response_model=ActiveItemsOut)
async def activate_item(
    payload: ActivateItemRequest, service: FocusService = Depends(get_service)
) -> ActiveItemsOut:
    try:
        active = await service.activate_item(payload.item_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    return ActiveItemsOut(
        active_items={
            "aura": active.get("aura"),
            "skin": active.get("skin"),
            "environment": active.get("environment"),
        }
    )


@router.post("/shop/deactivate", response_model=ActiveItemsOut)
async def deactivate_item(
    payload: DeactivateItemRequest, service: FocusService = Depends(get_service)
) -> ActiveItemsOut:
    try:
        active = await service.deactivate_item(payload.category)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    return ActiveItemsOut(
        active_items={
            "aura": active.get("aura"),
            "skin": active.get("skin"),
            "environment": active.get("environment"),
        }
    )


def _session_to_out(session) -> FocusSessionOut:
    """Convert a FocusSession ORM object to FocusSessionOut with subcoin→display conversion."""
    return FocusSessionOut(
        id=session.id,
        planned_duration_sec=session.planned_duration_sec,
        status=session.status,
        active_elapsed_sec=session.active_elapsed_sec,
        last_state_change_at=session.last_state_change_at,
        started_at=session.started_at,
        ended_at=session.ended_at,
        room_id=session.room_id,
        task_id=session.task_id,
        earned_coins=subcoins_to_display(session.earned_coins),
        credited_minutes=session.credited_minutes,
        earned_xp=session.earned_xp,
        session_day=session.session_day,
    )


@router.get("/focus-sessions", response_model=list[FocusSessionOut])
async def list_focus_sessions(
    service: FocusService = Depends(get_service),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> list[FocusSessionOut]:
    try:
        sessions = await service.list_sessions(limit=limit, offset=offset)
        return [_session_to_out(s) for s in sessions]
    except Exception as exc:
        logger.exception("focus_sessions_list_failed", error=str(exc))
        raise


@router.post("/focus-sessions", response_model=FocusSessionOut, status_code=status.HTTP_201_CREATED)
async def create_focus_session(
    payload: FocusSessionCreate,
    service: FocusService = Depends(get_service),
    db_session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> FocusSessionOut:
    try:
        room_repo = SqlAlchemyFocusRoomRepository(db_session, current_user_id)
        room = await room_repo.get_by_id(payload.room_id)
        if room is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
        if room.archived:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT, detail="Cannot start session in archived room"
            )
        if payload.task_id is not None:
            task_repo = SqlAlchemyRoomTaskRepository(db_session, current_user_id)
            task = await task_repo.get_by_id(payload.task_id)
            if task is None or task.room_id != payload.room_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Task not found in the specified room",
                )
        focus_session = await service.create_session(
            planned_duration_sec=payload.planned_duration_sec,
            task_id=payload.task_id,
            room_id=payload.room_id,
        )
        if should_log_success():
            logger.info("focus_session_create_sampled", session_id=str(focus_session.id))
        return _session_to_out(focus_session)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("focus_session_create_failed", error=str(exc))
        raise


@router.get("/focus-sessions/{session_id}", response_model=FocusSessionOut)
async def get_focus_session(
    session_id: uuid.UUID, service: FocusService = Depends(get_service)
) -> FocusSessionOut:
    try:
        session = await service.get_session(session_id)
        if not session:
            logger.warning("focus_session_get_not_found", session_id=str(session_id))
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")
        return _session_to_out(session)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("focus_session_get_failed", session_id=str(session_id), error=str(exc))
        raise


_ACTION_MAP: dict[FocusSessionAction, FocusSessionStatus] = {
    FocusSessionAction.finish: FocusSessionStatus.finished,
    FocusSessionAction.cancel: FocusSessionStatus.cancelled,
}


@router.post("/focus-sessions/{session_id}/state", response_model=FocusSessionStateResponse)
async def update_focus_session_state(
    session_id: uuid.UUID,
    payload: FocusSessionStateUpdate,
    service: FocusService = Depends(get_service),
) -> FocusSessionStateResponse:
    try:
        target_status = _ACTION_MAP[payload.action]
        session, balance = await service.update_session_state(
            session_id=session_id,
            action=target_status,
        )
    except InvalidSessionTransitionError as exc:
        logger.warning(
            "focus_session_state_invalid_transition",
            session_id=str(session_id),
            action=payload.action.value,
            error=str(exc),
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except ValueError as exc:
        logger.warning(
            "focus_session_state_not_found",
            session_id=str(session_id),
            action=payload.action.value,
            error=str(exc),
        )
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except Exception as exc:
        logger.exception(
            "focus_session_state_failed",
            session_id=str(session_id),
            action=payload.action.value,
            error=str(exc),
        )
        raise
    return FocusSessionStateResponse(
        session=_session_to_out(session),
        balance=BalanceOut(coins=subcoins_to_display(balance.coins)) if balance else None,
    )


@router.post("/focus-sessions/{session_id}/actions", response_model=BatchActionsResponse)
async def batch_session_actions(
    session_id: uuid.UUID,
    payload: BatchActionsRequest,
    service: FocusService = Depends(get_service),
    idempotency: IdempotencyResult = Depends(check_idempotency),
) -> Any:
    """Apply multiple actions to a session in one request."""
    if idempotency.cached:
        return Response(
            content=__import__("json").dumps(idempotency.response_body),
            media_type="application/json",
            status_code=idempotency.response_status or 200,
        )

    actions_for_service = []
    for item in payload.actions:
        target_status = _ACTION_MAP[item.action]
        actions_for_service.append(
            {
                "action": target_status,
                "elapsed_override_sec": item.elapsed_override_sec,
            }
        )

    try:
        session, balance, results = await service.apply_actions_batch(
            session_id=session_id,
            actions=actions_for_service,
        )
        # Save task segments if provided
        if payload.segments:
            await service.save_task_segments(
                session_id=session_id,
                segments=[
                    {"task_id": s.task_id, "started_at": s.started_at, "ended_at": s.ended_at}
                    for s in payload.segments
                ],
            )
    except InvalidSessionTransitionError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except Exception as exc:
        logger.exception(
            "focus_session_batch_actions_failed",
            session_id=str(session_id),
            error=str(exc),
        )
        raise

    response = BatchActionsResponse(
        session=_session_to_out(session),
        balance=BalanceOut(coins=subcoins_to_display(balance.coins)) if balance else None,
        results=[BatchActionResult(**r) for r in results],
    )
    await idempotency.save(200, response.model_dump(mode="json"))
    return response


class TaskFocusTimeOut(BaseModel):
    task_id: uuid.UUID
    total_sec: int


@router.get("/focus/task-times", response_model=list[TaskFocusTimeOut])
async def get_task_focus_times(
    task_ids: str = Query(..., description="Comma-separated task UUIDs"),
    service: FocusService = Depends(get_service),
) -> list[TaskFocusTimeOut]:
    try:
        parsed_ids = [uuid.UUID(tid.strip()) for tid in task_ids.split(",") if tid.strip()]
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid task_id format"
        )
    if not parsed_ids:
        return []
    times = await service.get_task_focus_times(parsed_ids[:100])
    return [TaskFocusTimeOut(task_id=tid, total_sec=sec) for tid, sec in times.items()]


@router.patch("/focus-sessions/{session_id}", response_model=FocusSessionOut)
async def update_focus_session_task(
    session_id: uuid.UUID,
    payload: FocusSessionTaskUpdate,
    service: FocusService = Depends(get_service),
) -> FocusSessionOut:
    try:
        session = await service.update_session_task(session_id, payload.task_id)
    except InvalidSessionTransitionError as exc:
        logger.warning(
            "focus_session_task_invalid_transition",
            session_id=str(session_id),
            error=str(exc),
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except ValueError as exc:
        logger.warning("focus_session_task_not_found", session_id=str(session_id), error=str(exc))
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except Exception as exc:
        logger.exception("focus_session_task_failed", session_id=str(session_id), error=str(exc))
        raise
    return _session_to_out(session)
