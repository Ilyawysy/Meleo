from __future__ import annotations

import uuid
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.focus.entities import UserBalance
from backend.domain.mascot_skins.entities import MascotSkin, UserMascotSkin
from backend.domain.users.entities import User


# Display coins ↔ subcoins (10 subcoins = 1 display coin).
SUBCOINS_PER_COIN = 10


class MascotSkinError(Exception):
    """Domain-level error for mascot skin operations."""


class MascotSkinNotFound(MascotSkinError):
    pass


class MascotSkinNotOwned(MascotSkinError):
    pass


class InsufficientCoins(MascotSkinError):
    pass


class MascotSkinService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def list_catalog(self) -> list[MascotSkin]:
        result = await self.session.execute(
            select(MascotSkin).order_by(MascotSkin.sort_order, MascotSkin.id)
        )
        return list(result.scalars().all())

    async def list_owned_skin_ids(self, user_id: uuid.UUID) -> set[int]:
        result = await self.session.execute(
            select(UserMascotSkin.skin_id).where(UserMascotSkin.user_id == user_id)
        )
        return {row[0] for row in result.all()}

    async def get_active_skin_id(self, user_id: uuid.UUID) -> Optional[int]:
        result = await self.session.execute(
            select(User.active_mascot_skin_id).where(User.id == user_id)
        )
        return result.scalar_one_or_none()

    async def buy(self, user_id: uuid.UUID, skin_id: int) -> MascotSkin:
        skin = await self.session.get(MascotSkin, skin_id)
        if skin is None:
            raise MascotSkinNotFound(f"skin {skin_id}")

        existing = await self.session.execute(
            select(UserMascotSkin).where(
                UserMascotSkin.user_id == user_id,
                UserMascotSkin.skin_id == skin_id,
            )
        )
        if existing.scalar_one_or_none() is not None:
            return skin  # Idempotent — already owned.

        balance = await self.session.get(UserBalance, user_id)
        if balance is None:
            balance = UserBalance(user_id=user_id, coins=0)
            self.session.add(balance)

        price_subcoins = skin.price_coins * SUBCOINS_PER_COIN
        if balance.coins < price_subcoins:
            raise InsufficientCoins(
                f"need {price_subcoins} subcoins, have {balance.coins}"
            )

        balance.coins -= price_subcoins
        self.session.add(UserMascotSkin(user_id=user_id, skin_id=skin_id))
        await self.session.flush()
        return skin

    async def set_active(
        self, user_id: uuid.UUID, skin_id: Optional[int]
    ) -> Optional[int]:
        if skin_id is not None:
            owned = await self.session.execute(
                select(UserMascotSkin).where(
                    UserMascotSkin.user_id == user_id,
                    UserMascotSkin.skin_id == skin_id,
                )
            )
            if owned.scalar_one_or_none() is None:
                raise MascotSkinNotOwned(f"user does not own skin {skin_id}")

        user = await self.session.get(User, user_id)
        if user is None:
            raise MascotSkinError("user not found")

        user.active_mascot_skin_id = skin_id
        await self.session.flush()
        return skin_id
