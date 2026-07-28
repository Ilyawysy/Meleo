from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, List

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import exists, select, and_, or_, func
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.announcements.entities import DeveloperAnnouncement, UserAnnouncementRead
from backend.infrastructure.database.session import get_session
from backend.infrastructure.security.auth import get_current_user_id

router = APIRouter(prefix="/api/v1/announcements", tags=["announcements"])


class AnnouncementOut(BaseModel):
    id: uuid.UUID
    title: str
    message: str
    created_at: datetime

    model_config = {"from_attributes": True}


@router.get("/unread", response_model=List[AnnouncementOut])
async def get_unread_announcements(
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> Any:
    """Get all unread announcements for the current user.

    Returns announcements that:
    - Are active (is_active=true)
    - Have not expired (expires_at is NULL or > now)
    - Match targeting (target_user_ids is NULL/empty OR contains current_user_id)
    - Have not been read by current user
    """
    # Main query: get unread announcements using NOT EXISTS (faster than NOT IN)
    stmt = (
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

    result = await session.execute(stmt)
    announcements = result.scalars().all()

    return [AnnouncementOut.model_validate(a) for a in announcements]


@router.post("/{announcement_id}/mark-read", status_code=status.HTTP_204_NO_CONTENT)
async def mark_announcement_read(
    announcement_id: uuid.UUID,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> None:
    """Mark an announcement as read for the current user.

    Idempotent: if already marked as read, does nothing (returns 204).
    """
    # Check if announcement exists and is active
    stmt = select(DeveloperAnnouncement).where(DeveloperAnnouncement.id == announcement_id)
    result = await session.execute(stmt)
    announcement = result.scalar_one_or_none()

    if not announcement:
        raise HTTPException(status_code=404, detail="Announcement not found")

    # Check if already read
    check_stmt = select(UserAnnouncementRead).where(
        and_(
            UserAnnouncementRead.user_id == current_user_id,
            UserAnnouncementRead.announcement_id == announcement_id,
        )
    )
    check_result = await session.execute(check_stmt)
    existing = check_result.scalar_one_or_none()

    if existing:
        return None

    # Create read record
    read_record = UserAnnouncementRead(
        user_id=current_user_id,
        announcement_id=announcement_id,
    )
    session.add(read_record)
    await session.commit()

    return None
