from __future__ import annotations

import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.mascot_skins.entities import MascotSkin, MascotSkinTier
from backend.domain.mascot_skins.service import (
    InsufficientCoins,
    MascotSkinNotFound,
    MascotSkinNotOwned,
    MascotSkinService,
)
from backend.infrastructure.database.session import get_session
from backend.infrastructure.security.auth import get_current_user_id


router = APIRouter(prefix="/api/v1/mascot-skins", tags=["mascot_skins"])


class MascotSkinOut(BaseModel):
    id: int
    slug: str
    tier: MascotSkinTier
    price_coins: int
    color1: str
    color2: str
    color3: str
    color4: str
    sort_order: int
    owned: bool
    active: bool


class CatalogOut(BaseModel):
    skins: list[MascotSkinOut]
    active_skin_id: Optional[int] = None


class SetActiveIn(BaseModel):
    skin_id: Optional[int] = None


def _to_out(skin: MascotSkin, owned: bool, active: bool) -> MascotSkinOut:
    return MascotSkinOut(
        id=skin.id,
        slug=skin.slug,
        tier=skin.tier,
        price_coins=skin.price_coins,
        color1=skin.color1,
        color2=skin.color2,
        color3=skin.color3,
        color4=skin.color4,
        sort_order=skin.sort_order,
        owned=owned,
        active=active,
    )


@router.get("", response_model=CatalogOut)
async def list_skins(
    user_id: uuid.UUID = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> CatalogOut:
    service = MascotSkinService(session)
    skins = await service.list_catalog()
    owned_ids = await service.list_owned_skin_ids(user_id)
    active_id = await service.get_active_skin_id(user_id)
    return CatalogOut(
        skins=[
            _to_out(s, owned=s.id in owned_ids, active=s.id == active_id)
            for s in skins
        ],
        active_skin_id=active_id,
    )


@router.post("/{skin_id}/buy", response_model=MascotSkinOut)
async def buy_skin(
    skin_id: int,
    user_id: uuid.UUID = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> MascotSkinOut:
    service = MascotSkinService(session)
    try:
        skin = await service.buy(user_id, skin_id)
    except MascotSkinNotFound:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "skin not found")
    except InsufficientCoins:
        raise HTTPException(status.HTTP_402_PAYMENT_REQUIRED, "insufficient coins")
    await session.commit()

    active_id = await service.get_active_skin_id(user_id)
    return _to_out(skin, owned=True, active=skin.id == active_id)


@router.post("/active", response_model=CatalogOut)
async def set_active(
    body: SetActiveIn,
    user_id: uuid.UUID = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> CatalogOut:
    service = MascotSkinService(session)
    try:
        await service.set_active(user_id, body.skin_id)
    except MascotSkinNotOwned:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "skin not owned")
    except MascotSkinNotFound:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "skin not found")
    await session.commit()

    skins = await service.list_catalog()
    owned_ids = await service.list_owned_skin_ids(user_id)
    active_id = await service.get_active_skin_id(user_id)
    return CatalogOut(
        skins=[
            _to_out(s, owned=s.id in owned_ids, active=s.id == active_id)
            for s in skins
        ],
        active_skin_id=active_id,
    )
