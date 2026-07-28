from __future__ import annotations

import re
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.focus_rooms.checklist_entities import ChecklistItem
from backend.domain.focus_rooms.entities import FocusRoom, FocusRoomType
from backend.domain.focus_rooms.service import FocusRoomService
from backend.domain.focus_rooms.task_entities import Task, TaskStatus
from backend.domain.focus.entities import FocusSession
from backend.infrastructure.database.session import get_session
from backend.infrastructure.logging import get_logger
from backend.infrastructure.repositories.focus_room_repository import (
    SqlAlchemyChecklistRepository,
    SqlAlchemyFocusRoomRepository,
    SqlAlchemyTaskRepository as SqlAlchemyRoomTaskRepository,
)
from backend.infrastructure.repositories.gamification_repository import (
    SqlAlchemyGamificationRepository,
)
from backend.infrastructure.security.auth import get_current_user_id

_HEX_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{3,8}$")

router = APIRouter(prefix="/api/v1", tags=["focus_rooms"])
logger = get_logger("focus_rooms_api")


# --- Schemas ---


class FocusRoomCreate(BaseModel):
    id: Optional[uuid.UUID] = None
    title: str = Field(..., min_length=1, max_length=120)
    color: str = Field(..., min_length=1, max_length=16)
    type: Optional[FocusRoomType] = FocusRoomType.REGULAR
    sort_order: int = 0
    sprint_goal: Optional[str] = Field(None, max_length=255)
    sprint_deadline: Optional[datetime] = None
    sprint_total_hours: Optional[int] = None
    focus_duration_min: Optional[int] = Field(None, ge=1, le=240)
    break_min: Optional[int] = Field(None, ge=0, le=120)

    @field_validator("color")
    @classmethod
    def validate_color(cls, v: str) -> str:
        if not _HEX_COLOR_RE.match(v.strip()):
            raise ValueError("color must be a valid hex color (e.g. #RGB, #RRGGBB, #RRGGBBAA)")
        return v.strip()

    @field_validator("sprint_goal", "sprint_deadline", "sprint_total_hours", mode="before")
    @classmethod
    def validate_sprint_fields(cls, v: object, info: object) -> object:
        return v

    def model_post_init(self, __context: object) -> None:
        room_type = self.type or FocusRoomType.REGULAR
        if room_type != FocusRoomType.SPRINT:
            if (
                self.sprint_goal is not None
                or self.sprint_deadline is not None
                or self.sprint_total_hours is not None
            ):
                raise ValueError(
                    "sprint_goal, sprint_deadline, sprint_total_hours can only be set for type=sprint rooms"
                )


class FocusRoomUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=120)
    color: Optional[str] = Field(None, min_length=1, max_length=16)
    sort_order: Optional[int] = None
    sprint_goal: Optional[str] = Field(None, max_length=255)
    sprint_deadline: Optional[datetime] = None
    sprint_total_hours: Optional[int] = None
    focus_duration_min: Optional[int] = Field(None, ge=1, le=240)
    break_min: Optional[int] = Field(None, ge=0, le=120)
    type: Optional[FocusRoomType] = None
    archived: Optional[bool] = None

    @field_validator("color")
    @classmethod
    def validate_color(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not _HEX_COLOR_RE.match(v.strip()):
            raise ValueError("color must be a valid hex color (e.g. #RGB, #RRGGBB, #RRGGBBAA)")
        return v.strip() if v is not None else v


class FocusRoomOut(BaseModel):
    id: uuid.UUID
    title: str
    color: str
    type: FocusRoomType
    archived: bool
    archived_at: Optional[datetime] = None
    sort_order: int
    sprint_goal: Optional[str] = None
    sprint_deadline: Optional[datetime] = None
    sprint_total_hours: Optional[int] = None
    focus_duration_min: Optional[int] = None
    break_min: Optional[int] = None
    task_count: int = 0
    total_focus_sec: int = 0
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class TaskCreate(BaseModel):
    id: Optional[uuid.UUID] = None
    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    sort_order: int = 0


class TaskUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    status: Optional[TaskStatus] = None
    sort_order: Optional[int] = None


class TaskOut(BaseModel):
    id: uuid.UUID
    room_id: uuid.UUID
    title: str
    description: Optional[str] = None
    status: TaskStatus
    sort_order: int
    completed_at: Optional[datetime] = None
    deleted: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class ChecklistItemCreate(BaseModel):
    id: Optional[uuid.UUID] = None
    title: str = Field(..., min_length=1, max_length=500)
    sort_order: int = 0


class ChecklistItemUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=500)
    is_done: Optional[bool] = None
    sort_order: Optional[int] = None


class ChecklistItemOut(BaseModel):
    id: uuid.UUID
    task_id: uuid.UUID
    title: str
    is_done: bool
    sort_order: int
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class RoomFocusTimeOut(BaseModel):
    total_active_elapsed_sec: int


class ActiveRoomIn(BaseModel):
    room_id: Optional[uuid.UUID] = None


class ActiveRoomOut(BaseModel):
    active_focus_room_id: Optional[uuid.UUID] = None


# --- Helpers ---


async def _get_room_task_count(
    session: AsyncSession, room_id: uuid.UUID, user_id: uuid.UUID
) -> int:
    result = await session.execute(
        select(func.count(Task.id)).where(
            Task.room_id == room_id,
            Task.user_id == user_id,
            Task.deleted.is_(False),
        )
    )
    return result.scalar_one() or 0


async def _get_room_focus_seconds(
    session: AsyncSession, room_id: uuid.UUID, user_id: uuid.UUID
) -> int:
    result = await session.execute(
        select(func.coalesce(func.sum(FocusSession.active_elapsed_sec), 0)).where(
            FocusSession.room_id == room_id,
            FocusSession.user_id == user_id,
        )
    )
    return int(result.scalar_one() or 0)


async def _room_to_out(room: FocusRoom, session: AsyncSession, user_id: uuid.UUID) -> FocusRoomOut:
    task_count = await _get_room_task_count(session, room.id, user_id)
    total_focus_sec = await _get_room_focus_seconds(session, room.id, user_id)
    return FocusRoomOut(
        id=room.id,
        title=room.title,
        color=room.color,
        type=room.type,
        archived=room.archived,
        archived_at=room.archived_at,
        sort_order=room.sort_order,
        sprint_goal=room.sprint_goal,
        sprint_deadline=room.sprint_deadline,
        sprint_total_hours=room.sprint_total_hours,
        focus_duration_min=room.focus_duration_min,
        break_min=room.break_min,
        task_count=task_count,
        total_focus_sec=total_focus_sec,
        created_at=room.created_at,
        updated_at=room.updated_at,
    )


# --- Room endpoints ---


@router.get("/rooms", response_model=list[FocusRoomOut])
async def list_rooms(
    archived: bool = Query(False),
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> list[FocusRoomOut]:
    task_count_sub = (
        select(Task.room_id, func.count(Task.id).label("task_count"))
        .where(Task.user_id == current_user_id, Task.deleted.is_(False))
        .group_by(Task.room_id)
        .subquery()
    )
    focus_sec_sub = (
        select(
            FocusSession.room_id,
            func.coalesce(func.sum(FocusSession.active_elapsed_sec), 0).label("total_focus_sec"),
        )
        .where(FocusSession.user_id == current_user_id)
        .group_by(FocusSession.room_id)
        .subquery()
    )
    stmt = (
        select(
            FocusRoom,
            func.coalesce(task_count_sub.c.task_count, 0).label("task_count"),
            func.coalesce(focus_sec_sub.c.total_focus_sec, 0).label("total_focus_sec"),
        )
        .outerjoin(task_count_sub, FocusRoom.id == task_count_sub.c.room_id)
        .outerjoin(focus_sec_sub, FocusRoom.id == focus_sec_sub.c.room_id)
        .where(
            FocusRoom.user_id == current_user_id,
            FocusRoom.archived.is_(archived),
            FocusRoom.deleted.is_(False),
        )
        .order_by(FocusRoom.sort_order, FocusRoom.created_at)
    )
    rows = (await session.execute(stmt)).all()
    return [
        FocusRoomOut(
            id=room.id,
            title=room.title,
            color=room.color,
            type=room.type,
            archived=room.archived,
            archived_at=room.archived_at,
            sort_order=room.sort_order,
            sprint_goal=room.sprint_goal,
            sprint_deadline=room.sprint_deadline,
            sprint_total_hours=room.sprint_total_hours,
            focus_duration_min=room.focus_duration_min,
            break_min=room.break_min,
            task_count=task_count,
            total_focus_sec=int(total_focus_sec),
            created_at=room.created_at,
            updated_at=room.updated_at,
        )
        for room, task_count, total_focus_sec in rows
    ]


@router.post("/rooms", response_model=FocusRoomOut, status_code=status.HTTP_201_CREATED)
async def create_room(
    payload: FocusRoomCreate,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> FocusRoomOut:
    room = FocusRoom(
        id=payload.id or uuid.uuid4(),
        user_id=current_user_id,
        title=payload.title.strip(),
        color=payload.color.strip(),
        type=payload.type or FocusRoomType.REGULAR,
        sort_order=payload.sort_order,
        sprint_goal=payload.sprint_goal,
        sprint_deadline=payload.sprint_deadline,
        sprint_total_hours=payload.sprint_total_hours,
        focus_duration_min=payload.focus_duration_min,
        break_min=payload.break_min,
    )
    repo = SqlAlchemyFocusRoomRepository(session, current_user_id)
    created = await repo.create(room)
    await session.commit()
    await session.refresh(created)
    logger.info("room_created", room_id=str(created.id))
    return await _room_to_out(created, session, current_user_id)


@router.put("/rooms/active", response_model=ActiveRoomOut)
async def set_active_room(
    payload: ActiveRoomIn,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> ActiveRoomOut:
    gam_repo = SqlAlchemyGamificationRepository(session, current_user_id)
    service = FocusRoomService(session, gam_repo=gam_repo)
    try:
        new_id = await service.set_active_room(current_user_id, payload.room_id)
    except ValueError as exc:
        msg = str(exc)
        if "not found" in msg.lower():
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=msg) from exc
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=msg) from exc
    await session.commit()
    return ActiveRoomOut(active_focus_room_id=new_id)


@router.patch("/rooms/{room_id}", response_model=FocusRoomOut)
async def update_room(
    room_id: uuid.UUID,
    payload: FocusRoomUpdate,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> FocusRoomOut:
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No fields to update")
    archiving = fields.get("archived") is True
    if "archived" in fields:
        fields["archived_at"] = datetime.now(timezone.utc) if fields["archived"] else None
    repo = SqlAlchemyFocusRoomRepository(session, current_user_id)
    room = await repo.update(room_id, fields)
    if room is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    if archiving:
        gam_repo = SqlAlchemyGamificationRepository(session, current_user_id)
        service = FocusRoomService(session, gam_repo=gam_repo)
        active_id = await gam_repo.get_active_focus_room_id()
        if active_id == room_id:
            await gam_repo.set_active_focus_room_id(None)
            await service.bump_focus_version(current_user_id)
    await session.commit()
    await session.refresh(room)
    return await _room_to_out(room, session, current_user_id)


@router.post("/rooms/{room_id}/archive", response_model=FocusRoomOut)
async def archive_room(
    room_id: uuid.UUID,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> FocusRoomOut:
    gam_repo = SqlAlchemyGamificationRepository(session, current_user_id)
    service = FocusRoomService(session, gam_repo=gam_repo)
    room = await service.archive_room(room_id, current_user_id)
    if room is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    await session.commit()
    await session.refresh(room)
    return await _room_to_out(room, session, current_user_id)


@router.post("/rooms/{room_id}/unarchive", response_model=FocusRoomOut)
async def unarchive_room(
    room_id: uuid.UUID,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> FocusRoomOut:
    repo = SqlAlchemyFocusRoomRepository(session, current_user_id)
    room = await repo.unarchive(room_id)
    if room is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    await session.commit()
    await session.refresh(room)
    return await _room_to_out(room, session, current_user_id)


@router.get("/rooms/{room_id}/focus-time", response_model=RoomFocusTimeOut)
async def get_room_focus_time(
    room_id: uuid.UUID,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> RoomFocusTimeOut:
    repo = SqlAlchemyFocusRoomRepository(session, current_user_id)
    room = await repo.get_by_id(room_id)
    if room is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    total_sec = await _get_room_focus_seconds(session, room_id, current_user_id)
    return RoomFocusTimeOut(total_active_elapsed_sec=total_sec)


# --- Task endpoints ---


@router.get("/rooms/{room_id}/tasks", response_model=list[TaskOut])
async def list_tasks(
    room_id: uuid.UUID,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> list[TaskOut]:
    room_repo = SqlAlchemyFocusRoomRepository(session, current_user_id)
    room = await room_repo.get_by_id(room_id)
    if room is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    task_repo = SqlAlchemyRoomTaskRepository(session, current_user_id)
    tasks = await task_repo.list_for_room(room_id)
    return [TaskOut.model_validate(t) for t in tasks]


@router.post("/rooms/{room_id}/tasks", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
async def create_task(
    room_id: uuid.UUID,
    payload: TaskCreate,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> TaskOut:
    room_repo = SqlAlchemyFocusRoomRepository(session, current_user_id)
    room = await room_repo.get_by_id(room_id)
    if room is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    if room.archived:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Cannot add tasks to archived room"
        )
    task = Task(
        id=payload.id or uuid.uuid4(),
        room_id=room_id,
        user_id=current_user_id,
        title=payload.title.strip(),
        description=payload.description,
        sort_order=payload.sort_order,
    )
    task_repo = SqlAlchemyRoomTaskRepository(session, current_user_id)
    created = await task_repo.create(task)
    await session.commit()
    await session.refresh(created)
    logger.info("task_created", task_id=str(created.id), room_id=str(room_id))
    return TaskOut.model_validate(created)


@router.patch("/tasks/{task_id}", response_model=TaskOut)
async def update_task(
    task_id: uuid.UUID,
    payload: TaskUpdate,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> TaskOut:
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No fields to update")

    task_repo = SqlAlchemyRoomTaskRepository(session, current_user_id)
    task = await task_repo.get_by_id(task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    if (
        "status" in fields
        and fields["status"] == TaskStatus.DONE
        and task.status != TaskStatus.DONE
    ):
        fields["completed_at"] = datetime.now(timezone.utc)
    elif "status" in fields and fields["status"] == TaskStatus.NOT_DONE:
        fields["completed_at"] = None

    updated = await task_repo.update(task_id, fields)
    if updated is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    await session.commit()
    await session.refresh(updated)
    return TaskOut.model_validate(updated)


@router.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_task(
    task_id: uuid.UUID,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> None:
    task_repo = SqlAlchemyRoomTaskRepository(session, current_user_id)
    deleted = await task_repo.soft_delete(task_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    await session.commit()
    return None


# --- Checklist endpoints ---


@router.get("/tasks/{task_id}/checklist", response_model=list[ChecklistItemOut])
async def list_checklist(
    task_id: uuid.UUID,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> list[ChecklistItemOut]:
    task_repo = SqlAlchemyRoomTaskRepository(session, current_user_id)
    task = await task_repo.get_by_id(task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    checklist_repo = SqlAlchemyChecklistRepository(session, current_user_id)
    items = await checklist_repo.list_for_task(task_id)
    return [ChecklistItemOut.model_validate(i) for i in items]


@router.post(
    "/tasks/{task_id}/checklist",
    response_model=ChecklistItemOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_checklist_item(
    task_id: uuid.UUID,
    payload: ChecklistItemCreate,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> ChecklistItemOut:
    task_repo = SqlAlchemyRoomTaskRepository(session, current_user_id)
    task = await task_repo.get_by_id(task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    item = ChecklistItem(
        id=payload.id or uuid.uuid4(),
        task_id=task_id,
        title=payload.title.strip(),
        sort_order=payload.sort_order,
    )
    checklist_repo = SqlAlchemyChecklistRepository(session, current_user_id)
    created = await checklist_repo.create(item)
    await session.commit()
    await session.refresh(created)
    return ChecklistItemOut.model_validate(created)


@router.patch("/tasks/{task_id}/checklist/{item_id}", response_model=ChecklistItemOut)
async def update_checklist_item(
    task_id: uuid.UUID,
    item_id: uuid.UUID,
    payload: ChecklistItemUpdate,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> ChecklistItemOut:
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No fields to update")
    checklist_repo = SqlAlchemyChecklistRepository(session, current_user_id)
    updated = await checklist_repo.update(item_id, fields)
    if updated is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    await session.commit()
    await session.refresh(updated)
    return ChecklistItemOut.model_validate(updated)


@router.delete("/tasks/{task_id}/checklist/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_checklist_item(
    task_id: uuid.UUID,
    item_id: uuid.UUID,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> None:
    checklist_repo = SqlAlchemyChecklistRepository(session, current_user_id)
    deleted = await checklist_repo.delete(item_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    await session.commit()
    return None
