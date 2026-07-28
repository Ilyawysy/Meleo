from __future__ import annotations

from sqlalchemy import BigInteger, SmallInteger
from sqlalchemy.orm import Mapped, mapped_column

from backend.infrastructure.database.base import Base


class GlobalStateVersion(Base):
    """Singleton row with global version counters used by sync ETag."""

    __tablename__ = "global_state_version"

    id: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    announcements_version: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default="0",
    )
