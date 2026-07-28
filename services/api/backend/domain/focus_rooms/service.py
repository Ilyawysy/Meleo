from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from backend.domain.focus_rooms.entities import FocusRoom, FocusRoomType
from backend.domain.focus_rooms.task_entities import Task, TaskStatus
from backend.domain.users.state_version import UserStateVersion
from backend.infrastructure.logging import get_logger

logger = get_logger("focus_rooms_service")


class FocusRoomService:
    def __init__(self, session, gam_repo=None) -> None:
        self._session = session
        self._gam_repo = gam_repo

    async def create_room(
        self,
        user_id: uuid.UUID,
        title: str,
        color: str,
        *,
        room_id: uuid.UUID | None = None,
        room_type: FocusRoomType = FocusRoomType.REGULAR,
        sort_order: int = 0,
        sprint_goal: str | None = None,
        sprint_deadline: datetime | None = None,
        sprint_total_hours: int | None = None,
    ) -> FocusRoom:
        if not title or not title.strip():
            raise ValueError("title is required")
        if not color or not color.strip():
            raise ValueError("color is required")

        room = FocusRoom(
            id=room_id or uuid.uuid4(),
            user_id=user_id,
            title=title.strip(),
            color=color.strip(),
            type=room_type,
            sort_order=sort_order,
            sprint_goal=sprint_goal,
            sprint_deadline=sprint_deadline,
            sprint_total_hours=sprint_total_hours,
        )
        self._session.add(room)
        await self._session.flush()
        await self._session.refresh(room)
        logger.info("focus_room_created", room_id=str(room.id), user_id=str(user_id))
        return room

    async def archive_room(self, room_id: uuid.UUID, user_id: uuid.UUID) -> FocusRoom | None:
        result = await self._session.execute(
            select(FocusRoom).where(
                FocusRoom.id == room_id,
                FocusRoom.user_id == user_id,
                FocusRoom.deleted.is_(False),
            )
        )
        room = result.scalar_one_or_none()
        if room is None:
            return None
        room.archived = True
        room.archived_at = datetime.now(timezone.utc)
        await self._session.flush()
        await self._session.refresh(room)
        if self._gam_repo is not None:
            active_id = await self._gam_repo.get_active_focus_room_id()
            if active_id == room_id:
                await self._gam_repo.set_active_focus_room_id(None)
                await self.bump_focus_version(user_id)
        logger.info("focus_room_archived", room_id=str(room_id))
        return room

    async def set_active_room(
        self, user_id: uuid.UUID, room_id: Optional[uuid.UUID]
    ) -> Optional[uuid.UUID]:
        if room_id is not None:
            result = await self._session.execute(
                select(FocusRoom).where(
                    FocusRoom.id == room_id,
                    FocusRoom.user_id == user_id,
                    FocusRoom.deleted.is_(False),
                )
            )
            room = result.scalar_one_or_none()
            if room is None:
                raise ValueError("Room not found")
            if room.archived:
                raise ValueError("Cannot activate archived room")
        if self._gam_repo is None:
            raise RuntimeError("gam_repo is required for set_active_room")
        await self._gam_repo.set_active_focus_room_id(room_id)
        await self.bump_focus_version(user_id)
        return room_id

    async def bump_focus_version(self, user_id: uuid.UUID) -> None:
        bump_stmt = (
            pg_insert(UserStateVersion)
            .values(user_id=user_id, focus_version=1)
            .on_conflict_do_update(
                index_elements=["user_id"],
                set_={"focus_version": UserStateVersion.focus_version + 1},
            )
        )
        await self._session.execute(bump_stmt)

    async def unarchive_room(self, room_id: uuid.UUID, user_id: uuid.UUID) -> FocusRoom | None:
        result = await self._session.execute(
            select(FocusRoom).where(
                FocusRoom.id == room_id,
                FocusRoom.user_id == user_id,
                FocusRoom.deleted.is_(False),
            )
        )
        room = result.scalar_one_or_none()
        if room is None:
            return None
        room.archived = False
        room.archived_at = None
        await self._session.flush()
        await self._session.refresh(room)
        logger.info("focus_room_unarchived", room_id=str(room_id))
        return room


class TaskService:
    def __init__(self, session) -> None:
        self._session = session

    async def create_task(
        self,
        user_id: uuid.UUID,
        room_id: uuid.UUID,
        title: str,
        *,
        description: str | None = None,
        sort_order: int = 0,
        task_id: uuid.UUID | None = None,
    ) -> Task:
        if not title or not title.strip():
            raise ValueError("title is required")

        room_result = await self._session.execute(
            select(FocusRoom).where(
                FocusRoom.id == room_id,
                FocusRoom.user_id == user_id,
                FocusRoom.deleted.is_(False),
            )
        )
        room = room_result.scalar_one_or_none()
        if room is None:
            raise ValueError("Room not found")
        if room.archived:
            raise ValueError("Cannot add tasks to archived room")

        task = Task(
            id=task_id or uuid.uuid4(),
            room_id=room_id,
            user_id=user_id,
            title=title.strip(),
            description=description,
            sort_order=sort_order,
        )
        self._session.add(task)
        await self._session.flush()
        await self._session.refresh(task)
        logger.info("task_created", task_id=str(task.id), room_id=str(room_id))
        return task

    async def update_task_status(
        self,
        task_id: uuid.UUID,
        user_id: uuid.UUID,
        status: TaskStatus,
    ) -> Task | None:
        result = await self._session.execute(
            select(Task).where(
                Task.id == task_id,
                Task.user_id == user_id,
                Task.deleted.is_(False),
            )
        )
        task = result.scalar_one_or_none()
        if task is None:
            return None
        task.status = status
        if status == TaskStatus.DONE:
            task.completed_at = datetime.now(timezone.utc)
        else:
            task.completed_at = None
        await self._session.flush()
        await self._session.refresh(task)
        return task

    async def delete_task(self, task_id: uuid.UUID, user_id: uuid.UUID) -> bool:
        result = await self._session.execute(
            select(Task).where(
                Task.id == task_id,
                Task.user_id == user_id,
                Task.deleted.is_(False),
            )
        )
        task = result.scalar_one_or_none()
        if task is None:
            return False
        task.deleted = True
        await self._session.flush()
        logger.info("task_deleted", task_id=str(task_id))
        return True
