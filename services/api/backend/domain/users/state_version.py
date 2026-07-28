from __future__ import annotations

import uuid

from sqlalchemy import BigInteger
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from backend.infrastructure.database.base import Base


class UserStateVersion(Base):
    """Tracks per-user version counters for O(1) ETag computation.

    Version columns are incremented by database triggers on INSERT/UPDATE/DELETE
    of the corresponding domain tables.
    """

    __tablename__ = "user_state_version"

    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True)
    notifications_version: Mapped[int] = mapped_column(
        BigInteger, nullable=False, server_default="0"
    )
    messages_version: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    announcements_version: Mapped[int] = mapped_column(
        BigInteger, nullable=False, server_default="0"
    )
    focus_version: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    rhythm_version: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
