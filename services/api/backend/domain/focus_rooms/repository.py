from __future__ import annotations

import uuid
from typing import Protocol, Sequence

from backend.domain.focus_rooms.entities import FocusRoom
from backend.domain.focus_rooms.task_entities import Task
from backend.domain.focus_rooms.checklist_entities import ChecklistItem
from backend.domain.sync.cursor import DomainCursor


class FocusRoomRepository(Protocol):
    async def get_by_id(
        self, session, room_id: uuid.UUID, user_id: uuid.UUID
    ) -> FocusRoom | None: ...

    async def list_for_user(
        self, session, user_id: uuid.UUID, *, archived: bool = False
    ) -> list[FocusRoom]: ...

    async def create(self, session, room: FocusRoom) -> FocusRoom: ...

    async def update(
        self, session, room_id: uuid.UUID, user_id: uuid.UUID, fields: dict
    ) -> FocusRoom | None: ...

    async def archive(
        self, session, room_id: uuid.UUID, user_id: uuid.UUID
    ) -> FocusRoom | None: ...

    async def unarchive(
        self, session, room_id: uuid.UUID, user_id: uuid.UUID
    ) -> FocusRoom | None: ...

    async def get_total_focus_seconds(
        self, session, room_id: uuid.UUID, user_id: uuid.UUID
    ) -> int: ...

    async def fetch_changes(
        self,
        session,
        user_id: uuid.UUID,
        cursor: DomainCursor,
        limit: int,
    ) -> tuple[Sequence[FocusRoom], DomainCursor | None]: ...


class TaskRepository(Protocol):
    async def get_by_id(self, session, task_id: uuid.UUID, user_id: uuid.UUID) -> Task | None: ...

    async def list_for_room(
        self, session, room_id: uuid.UUID, user_id: uuid.UUID
    ) -> list[Task]: ...

    async def create(self, session, task: Task) -> Task: ...

    async def update(
        self, session, task_id: uuid.UUID, user_id: uuid.UUID, fields: dict
    ) -> Task | None: ...

    async def soft_delete(self, session, task_id: uuid.UUID, user_id: uuid.UUID) -> bool: ...

    async def fetch_changes(
        self,
        session,
        user_id: uuid.UUID,
        cursor: DomainCursor,
        limit: int,
    ) -> tuple[Sequence[Task], DomainCursor | None]: ...


class ChecklistRepository(Protocol):
    async def get_by_id(
        self, session, item_id: uuid.UUID, user_id: uuid.UUID
    ) -> ChecklistItem | None: ...

    async def list_for_task(
        self, session, task_id: uuid.UUID, user_id: uuid.UUID
    ) -> list[ChecklistItem]: ...

    async def create(self, session, item: ChecklistItem) -> ChecklistItem: ...

    async def update(
        self, session, item_id: uuid.UUID, user_id: uuid.UUID, fields: dict
    ) -> ChecklistItem | None: ...

    async def delete(self, session, item_id: uuid.UUID, user_id: uuid.UUID) -> bool: ...

    async def fetch_changes(
        self,
        session,
        user_id: uuid.UUID,
        cursor: DomainCursor,
        limit: int,
    ) -> tuple[Sequence[ChecklistItem], DomainCursor | None]: ...
