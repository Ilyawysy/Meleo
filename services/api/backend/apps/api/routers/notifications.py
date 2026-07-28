from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.notifications.entities import NotificationRecurrence
from backend.domain.notifications.service import NotificationService
from backend.infrastructure.database.session import get_session
from backend.infrastructure.repositories.notification_repository import (
    SqlAlchemyNotificationRepository,
)
from backend.infrastructure.security.auth import get_current_user_id
from backend.infrastructure.logging import get_logger, get_log_context, should_log_success

router = APIRouter(prefix="/api/v1/notifications", tags=["notifications"])
logger = get_logger("notifications")


class NotificationCreate(BaseModel):
    model_config = {
        "extra": "forbid",
        "str_strip_whitespace": True,
    }
    title: str = Field(..., min_length=1, max_length=255)
    time: datetime
    recurrence: NotificationRecurrence = NotificationRecurrence.none


class NotificationUpdate(BaseModel):
    model_config = {
        "extra": "forbid",
        "str_strip_whitespace": True,
    }
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    time: Optional[datetime] = None
    recurrence: Optional[NotificationRecurrence] = None


class NotificationOut(BaseModel):
    id: uuid.UUID
    title: str
    time: datetime
    recurrence: NotificationRecurrence
    created_at: Optional[datetime]
    updated_at: Optional[datetime]

    model_config = {"from_attributes": True}


class PaginatedNotifications(BaseModel):
    total: int | None
    items: List[NotificationOut]


def get_service(
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> NotificationService:
    repo = SqlAlchemyNotificationRepository(session, current_user_id)
    return NotificationService(repo)


@router.get("/", response_model=PaginatedNotifications)
async def list_notifications(
    service: NotificationService = Depends(get_service),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    time_before: Optional[datetime] = Query(None),
    time_after: Optional[datetime] = Query(None),
    sort_by: Optional[str] = Query(None, pattern="^(created_at|time)$"),
    sort_dir: Optional[str] = Query(None, pattern="^(asc|desc)$"),
) -> Any:
    total, items = await service.list_paginated(
        limit=limit,
        offset=offset,
        time_before=time_before,
        time_after=time_after,
        sort_by=sort_by,
        sort_dir=sort_dir,
    )

    if should_log_success():
        ctx = get_log_context()
        logger.info(
            "list_notifications_sampled",
            request_id=ctx["request_id"],
            user_id=ctx["user_id"],
            returned=len(items),
            total=total,
        )
    return {"total": total, "items": items}


@router.post("/", response_model=NotificationOut, status_code=status.HTTP_201_CREATED)
async def create_notification(
    payload: NotificationCreate, service: NotificationService = Depends(get_service)
) -> NotificationOut:
    notification = await service.create_notification(
        title=payload.title,
        time=payload.time,
        recurrence=payload.recurrence,
    )
    if should_log_success():
        ctx = get_log_context()
        logger.info(
            "create_notification_sampled",
            request_id=ctx["request_id"],
            user_id=ctx["user_id"],
            notification_id=str(notification.id),
        )
    return NotificationOut.model_validate(notification)


@router.patch("/{notification_id}", response_model=NotificationOut)
async def update_notification(
    notification_id: uuid.UUID,
    payload: NotificationUpdate,
    service: NotificationService = Depends(get_service),
) -> NotificationOut:
    fields_set = getattr(payload, "model_fields_set", set())
    fields = {k: getattr(payload, k) for k in fields_set}
    try:
        updated = await service.update_notification(notification_id, **fields)
    except ValueError:
        ctx = get_log_context()
        logger.warning(
            "update_notification_not_found",
            request_id=ctx["request_id"],
            user_id=ctx["user_id"],
            notification_id=str(notification_id),
        )
        raise HTTPException(status_code=404, detail="Notification not found")
    if should_log_success():
        ctx = get_log_context()
        logger.info(
            "update_notification_sampled",
            request_id=ctx["request_id"],
            user_id=ctx["user_id"],
            notification_id=str(updated.id),
        )
    return NotificationOut.model_validate(updated)


@router.delete("/{notification_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_notification(
    notification_id: uuid.UUID, service: NotificationService = Depends(get_service)
) -> None:
    try:
        await service.delete_notification(notification_id)
    except ValueError:
        ctx = get_log_context()
        logger.warning(
            "delete_notification_not_found",
            request_id=ctx["request_id"],
            user_id=ctx["user_id"],
            notification_id=str(notification_id),
        )
        raise HTTPException(status_code=404, detail="Notification not found")
    return None
