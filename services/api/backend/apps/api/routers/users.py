from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, status
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.users.state_version import UserStateVersion
from backend.infrastructure.database.session import get_session
from backend.infrastructure.repositories.user_repository import SqlAlchemyUserRepository
from backend.infrastructure.security.auth import get_current_user_id

router = APIRouter(prefix="/users", tags=["users"])


@router.post("/me/onboarding/complete", status_code=status.HTTP_204_NO_CONTENT)
async def complete_onboarding(
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> None:
    user_repo = SqlAlchemyUserRepository(session)
    updated = await user_repo.mark_onboarding_completed(current_user_id)
    if updated:
        bump_stmt = (
            pg_insert(UserStateVersion)
            .values(user_id=current_user_id, focus_version=1)
            .on_conflict_do_update(
                index_elements=["user_id"],
                set_={"focus_version": UserStateVersion.focus_version + 1},
            )
        )
        await session.execute(bump_stmt)
    await session.commit()
    return None
