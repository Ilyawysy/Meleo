"""Idempotency key support for safe retries.

Usage as FastAPI dependency:
    @router.post("/endpoint")
    async def handler(
        ...,
        idempotency: IdempotencyResult = Depends(check_idempotency),
    ):
        if idempotency.cached:
            return JSONResponse(
                status_code=idempotency.response_status,
                content=idempotency.response_body,
            )
        # ... do work ...
        await idempotency.save(status_code, body_dict)
        return response
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import Depends, Header
from sqlalchemy import DateTime, ForeignKey, Integer, Text, delete, select
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from backend.infrastructure.database.base import Base
from backend.infrastructure.database.session import get_session
from backend.infrastructure.security.auth import get_current_user_id


class IdempotencyKey(Base):
    __tablename__ = "idempotency_keys"

    key: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    endpoint: Mapped[str] = mapped_column(Text, nullable=False)
    response_status: Mapped[int] = mapped_column(Integer, nullable=False)
    response_body: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc)
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class IdempotencyResult:
    """Result of idempotency check."""

    def __init__(
        self,
        cached: bool,
        response_status: int | None = None,
        response_body: dict | None = None,
        *,
        _session: AsyncSession | None = None,
        _key: uuid.UUID | None = None,
        _user_id: uuid.UUID | None = None,
        _endpoint: str = "",
    ) -> None:
        self.cached = cached
        self.response_status = response_status
        self.response_body = response_body
        self._session = _session
        self._key = _key
        self._user_id = _user_id
        self._endpoint = _endpoint

    async def save(self, status_code: int, body: dict[str, Any]) -> None:
        """Store response for this idempotency key."""
        if self._session is None or self._key is None:
            return
        from datetime import timedelta

        now = datetime.now(timezone.utc)
        row = IdempotencyKey(
            key=self._key,
            user_id=self._user_id,
            endpoint=self._endpoint,
            response_status=status_code,
            response_body=body,
            created_at=now,
            expires_at=now + timedelta(hours=24),
        )
        self._session.add(row)
        await self._session.flush()


async def check_idempotency(
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key"),
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> IdempotencyResult:
    """FastAPI dependency: check for existing idempotency key.

    If no Idempotency-Key header → no-op (normal processing).
    If key exists and not expired → return cached response.
    Otherwise → return saveable result for storing response after handler.
    """
    if not idempotency_key:
        return IdempotencyResult(cached=False)

    try:
        key_uuid = uuid.UUID(idempotency_key)
    except ValueError:
        return IdempotencyResult(cached=False)

    now = datetime.now(timezone.utc)
    result = await session.execute(
        select(IdempotencyKey).where(
            IdempotencyKey.key == key_uuid,
            IdempotencyKey.user_id == current_user_id,
            IdempotencyKey.expires_at > now,
        )
    )
    existing = result.scalar_one_or_none()

    if existing is not None:
        return IdempotencyResult(
            cached=True,
            response_status=existing.response_status,
            response_body=existing.response_body,
        )

    return IdempotencyResult(
        cached=False,
        _session=session,
        _key=key_uuid,
        _user_id=current_user_id,
        _endpoint="",
    )


async def cleanup_expired_keys(session: AsyncSession) -> int:
    """Remove expired idempotency keys. Call periodically."""
    result = await session.execute(
        delete(IdempotencyKey).where(IdempotencyKey.expires_at < datetime.now(timezone.utc))
    )
    return result.rowcount or 0
