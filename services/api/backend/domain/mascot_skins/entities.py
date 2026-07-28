from __future__ import annotations

import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from backend.infrastructure.database.base import Base


class MascotSkinTier(str, enum.Enum):
    cheap = "cheap"
    medium = "medium"
    expensive = "expensive"
    pro = "pro"


class MascotSkin(Base):
    __tablename__ = "mascot_skins"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    slug: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    tier: Mapped[MascotSkinTier] = mapped_column(
        Enum(MascotSkinTier, name="mascot_skin_tier"), nullable=False
    )
    price_coins: Mapped[int] = mapped_column(Integer, nullable=False)
    color1: Mapped[str] = mapped_column(String(7), nullable=False)
    color2: Mapped[str] = mapped_column(String(7), nullable=False)
    color3: Mapped[str] = mapped_column(String(7), nullable=False)
    color4: Mapped[str] = mapped_column(String(7), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class UserMascotSkin(Base):
    __tablename__ = "user_mascot_skins"

    user_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    skin_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("mascot_skins.id", ondelete="CASCADE"),
        primary_key=True,
    )
    purchased_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
