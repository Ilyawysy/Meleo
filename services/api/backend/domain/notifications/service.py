from __future__ import annotations

from datetime import datetime
from typing import Sequence
import uuid

from backend.domain.notifications.entities import Notification, NotificationRecurrence
from backend.domain.notifications.repository import NotificationRepository
from backend.infrastructure.logging import get_logger


class NotificationService:
    def __init__(self, repository: NotificationRepository) -> None:
        self._repository = repository
        self._logger = get_logger("notification_service")

    async def create_notification(
        self,
        title: str,
        time: datetime,
        *,
        recurrence: NotificationRecurrence = NotificationRecurrence.none,
    ) -> Notification:
        if not title or not title.strip():
            raise ValueError("title is required")
        self._logger.info("creating_notification", title=title, time=time, recurrence=recurrence)
        notification = Notification(
            title=title.strip(),
            time=time,
            recurrence=recurrence,
        )
        created_notification = await self._repository.create(notification)
        self._logger.info(
            "notification_created",
            notification_id=str(created_notification.id),
            title=created_notification.title,
        )
        return created_notification

    async def list_paginated(
        self,
        *,
        limit: int = 20,
        offset: int = 0,
        time_before: datetime | None = None,
        time_after: datetime | None = None,
        sort_by: str | None = None,
        sort_dir: str | None = None,
    ) -> tuple[int | None, Sequence[Notification]]:
        return await self._repository.list_paginated(
            limit=limit,
            offset=offset,
            time_before=time_before,
            time_after=time_after,
            sort_by=sort_by,
            sort_dir=sort_dir,
        )

    async def get_notification(self, notification_id: uuid.UUID) -> Notification | None:
        return await self._repository.get(notification_id)

    async def update_notification(self, notification_id: uuid.UUID, **fields) -> Notification:
        notification = await self._repository.get(notification_id)
        if not notification:
            raise ValueError("Notification not found")

        for key, value in fields.items():
            setattr(notification, key, value)

        updated = await self._repository.update(notification)
        self._logger.info("notification_updated", notification_id=str(updated.id))
        return updated

    async def delete_notification(self, notification_id: uuid.UUID) -> None:
        await self._repository.delete(notification_id)
