from __future__ import annotations

import uuid
from datetime import datetime
from typing import Protocol, Sequence

from backend.domain.notifications.entities import Notification


class NotificationRepository(Protocol):
    async def create(self, notification: Notification) -> Notification: ...
    async def get(self, notification_id: uuid.UUID) -> Notification | None: ...
    async def list(self, *, limit: int = 20, offset: int = 0) -> Sequence[Notification]: ...
    async def list_paginated(
        self,
        *,
        limit: int = 20,
        offset: int = 0,
        time_before: datetime | None = None,
        time_after: datetime | None = None,
        sort_by: str | None = None,  # created_at|time
        sort_dir: str | None = None,  # asc|desc
    ) -> tuple[int | None, Sequence[Notification]]: ...
    async def update(self, notification: Notification) -> Notification: ...
    async def delete(self, notification_id: uuid.UUID) -> None: ...
