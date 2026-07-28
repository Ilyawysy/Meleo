from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Sequence

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.focus_rooms.checklist_entities import ChecklistItem
from backend.domain.focus_rooms.entities import FocusRoom
from backend.domain.focus_rooms.task_entities import Task
from backend.domain.focus.entities import FocusSession, FocusTaskSegment
from backend.domain.sync.cursor import DomainCursor


class SqlAlchemyFocusRoomRepository:
    def __init__(self, session: AsyncSession, user_id: uuid.UUID) -> None:
        self._session = session
        self._user_id = user_id

    async def get_by_id(self, room_id: uuid.UUID) -> FocusRoom | None:
        result = await self._session.execute(
            select(FocusRoom).where(
                FocusRoom.id == room_id,
                FocusRoom.user_id == self._user_id,
                FocusRoom.deleted.is_(False),
            )
        )
        return result.scalar_one_or_none()

    async def list_for_user(self, *, archived: bool = False) -> list[FocusRoom]:
        result = await self._session.execute(
            select(FocusRoom)
            .where(
                FocusRoom.user_id == self._user_id,
                FocusRoom.archived.is_(archived),
                FocusRoom.deleted.is_(False),
            )
            .order_by(FocusRoom.sort_order, FocusRoom.created_at)
        )
        return list(result.scalars().all())

    async def create(self, room: FocusRoom) -> FocusRoom:
        room.user_id = self._user_id
        self._session.add(room)
        await self._session.flush()
        await self._session.refresh(room)
        return room

    async def update(self, room_id: uuid.UUID, fields: dict) -> FocusRoom | None:
        result = await self._session.execute(
            select(FocusRoom).where(
                FocusRoom.id == room_id,
                FocusRoom.user_id == self._user_id,
                FocusRoom.deleted.is_(False),
            )
        )
        room = result.scalar_one_or_none()
        if room is None:
            return None
        for key, value in fields.items():
            setattr(room, key, value)
        await self._session.flush()
        await self._session.refresh(room)
        return room

    async def archive(self, room_id: uuid.UUID) -> FocusRoom | None:
        return await self.update(
            room_id,
            {"archived": True, "archived_at": datetime.now(timezone.utc)},
        )

    async def unarchive(self, room_id: uuid.UUID) -> FocusRoom | None:
        return await self.update(
            room_id,
            {"archived": False, "archived_at": None},
        )

    async def get_task_count(self, room_id: uuid.UUID) -> int:
        result = await self._session.execute(
            select(func.count(Task.id)).where(
                Task.room_id == room_id,
                Task.user_id == self._user_id,
                Task.deleted.is_(False),
            )
        )
        return result.scalar_one() or 0

    async def get_total_focus_seconds(self, room_id: uuid.UUID) -> int:
        duration_expr = func.extract(
            "epoch",
            FocusTaskSegment.ended_at - FocusTaskSegment.started_at,
        )
        result = await self._session.execute(
            select(func.coalesce(func.sum(duration_expr), 0))
            .select_from(FocusTaskSegment)
            .join(FocusSession, FocusTaskSegment.session_id == FocusSession.id)
            .where(
                FocusSession.room_id == room_id,
                FocusSession.user_id == self._user_id,
                FocusTaskSegment.ended_at.is_not(None),
            )
        )
        return int(result.scalar_one() or 0)

    async def fetch_changes(
        self,
        cursor: DomainCursor,
        limit: int,
    ) -> tuple[Sequence[FocusRoom], DomainCursor | None]:
        stmt = (
            select(FocusRoom)
            .where(
                FocusRoom.user_id == self._user_id,
                or_(
                    FocusRoom.updated_at > cursor.updated_at,
                    and_(
                        FocusRoom.updated_at == cursor.updated_at,
                        FocusRoom.id > cursor.last_id,
                    ),
                ),
            )
            .order_by(FocusRoom.updated_at, FocusRoom.id)
            .limit(limit)
        )
        result = await self._session.execute(stmt)
        rooms = result.scalars().all()
        if not rooms:
            return [], None
        last = rooms[-1]
        new_cursor = DomainCursor(updated_at=last.updated_at, last_id=last.id)
        return rooms, new_cursor


class SqlAlchemyTaskRepository:
    def __init__(self, session: AsyncSession, user_id: uuid.UUID) -> None:
        self._session = session
        self._user_id = user_id

    async def get_by_id(self, task_id: uuid.UUID) -> Task | None:
        result = await self._session.execute(
            select(Task).where(
                Task.id == task_id,
                Task.user_id == self._user_id,
                Task.deleted.is_(False),
            )
        )
        return result.scalar_one_or_none()

    async def list_for_room(self, room_id: uuid.UUID) -> list[Task]:
        result = await self._session.execute(
            select(Task)
            .where(
                Task.room_id == room_id,
                Task.user_id == self._user_id,
                Task.deleted.is_(False),
            )
            .order_by(Task.sort_order, Task.created_at)
        )
        return list(result.scalars().all())

    async def create(self, task: Task) -> Task:
        task.user_id = self._user_id
        self._session.add(task)
        await self._session.flush()
        await self._session.refresh(task)
        return task

    async def update(self, task_id: uuid.UUID, fields: dict) -> Task | None:
        result = await self._session.execute(
            select(Task).where(
                Task.id == task_id,
                Task.user_id == self._user_id,
                Task.deleted.is_(False),
            )
        )
        task = result.scalar_one_or_none()
        if task is None:
            return None
        for key, value in fields.items():
            setattr(task, key, value)
        await self._session.flush()
        await self._session.refresh(task)
        return task

    async def soft_delete(self, task_id: uuid.UUID) -> bool:
        result = await self._session.execute(
            select(Task).where(
                Task.id == task_id,
                Task.user_id == self._user_id,
                Task.deleted.is_(False),
            )
        )
        task = result.scalar_one_or_none()
        if task is None:
            return False
        task.deleted = True
        await self._session.flush()
        return True

    async def fetch_changes(
        self,
        cursor: DomainCursor,
        limit: int,
    ) -> tuple[Sequence[Task], DomainCursor | None]:
        stmt = (
            select(Task)
            .where(
                Task.user_id == self._user_id,
                or_(
                    Task.updated_at > cursor.updated_at,
                    and_(
                        Task.updated_at == cursor.updated_at,
                        Task.id > cursor.last_id,
                    ),
                ),
            )
            .order_by(Task.updated_at, Task.id)
            .limit(limit)
        )
        result = await self._session.execute(stmt)
        tasks = result.scalars().all()
        if not tasks:
            return [], None
        last = tasks[-1]
        new_cursor = DomainCursor(updated_at=last.updated_at, last_id=last.id)
        return tasks, new_cursor


class SqlAlchemyChecklistRepository:
    def __init__(self, session: AsyncSession, user_id: uuid.UUID) -> None:
        self._session = session
        self._user_id = user_id

    async def get_by_id(self, item_id: uuid.UUID) -> ChecklistItem | None:
        result = await self._session.execute(
            select(ChecklistItem)
            .join(Task, ChecklistItem.task_id == Task.id)
            .where(
                ChecklistItem.id == item_id,
                Task.user_id == self._user_id,
                Task.deleted.is_(False),
            )
        )
        return result.scalar_one_or_none()

    async def list_for_task(self, task_id: uuid.UUID) -> list[ChecklistItem]:
        result = await self._session.execute(
            select(ChecklistItem)
            .join(Task, ChecklistItem.task_id == Task.id)
            .where(
                ChecklistItem.task_id == task_id,
                Task.user_id == self._user_id,
                Task.deleted.is_(False),
            )
            .order_by(ChecklistItem.sort_order, ChecklistItem.created_at)
        )
        return list(result.scalars().all())

    async def create(self, item: ChecklistItem) -> ChecklistItem:
        self._session.add(item)
        await self._session.flush()
        await self._session.refresh(item)
        return item

    async def update(self, item_id: uuid.UUID, fields: dict) -> ChecklistItem | None:
        item = await self.get_by_id(item_id)
        if item is None:
            return None
        for key, value in fields.items():
            setattr(item, key, value)
        await self._session.flush()
        await self._session.refresh(item)
        return item

    async def delete(self, item_id: uuid.UUID) -> bool:
        item = await self.get_by_id(item_id)
        if item is None:
            return False
        await self._session.delete(item)
        await self._session.flush()
        return True

    async def fetch_changes(
        self,
        cursor: DomainCursor,
        limit: int,
    ) -> tuple[Sequence[ChecklistItem], DomainCursor | None]:
        stmt = (
            select(ChecklistItem)
            .join(Task, ChecklistItem.task_id == Task.id)
            .where(
                Task.user_id == self._user_id,
                or_(
                    ChecklistItem.updated_at > cursor.updated_at,
                    and_(
                        ChecklistItem.updated_at == cursor.updated_at,
                        ChecklistItem.id > cursor.last_id,
                    ),
                ),
            )
            .order_by(ChecklistItem.updated_at, ChecklistItem.id)
            .limit(limit)
        )
        result = await self._session.execute(stmt)
        items = result.scalars().all()
        if not items:
            return [], None
        last = items[-1]
        new_cursor = DomainCursor(updated_at=last.updated_at, last_id=last.id)
        return items, new_cursor
