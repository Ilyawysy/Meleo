from __future__ import annotations

import uuid
from typing import Sequence

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from backend.domain.focus.entities import (
    FocusSession,
    FocusTaskSegment,
    ShopItem,
    UserActiveItem,
    UserBalance,
    UserShopItem,
)
from backend.domain.focus.repository import FocusRepository


class SqlAlchemyFocusRepository(FocusRepository):
    def __init__(self, session: AsyncSession, user_id: uuid.UUID) -> None:
        self._session = session
        self._user_id = user_id

    @property
    def session(self) -> AsyncSession:
        return self._session

    async def list_shop_items_with_owned_ids(self) -> tuple[Sequence[ShopItem], set[uuid.UUID]]:
        result = await self._session.execute(
            select(ShopItem, UserShopItem.user_id)
            .outerjoin(
                UserShopItem,
                (ShopItem.id == UserShopItem.item_id) & (UserShopItem.user_id == self._user_id),
            )
            .order_by(ShopItem.created_at.asc())
        )
        rows = result.all()
        items: list[ShopItem] = []
        owned_ids: set[uuid.UUID] = set()
        for shop_item, owner_id in rows:
            items.append(shop_item)
            if owner_id is not None:
                owned_ids.add(shop_item.id)
        return items, owned_ids

    async def get_shop_item(self, item_id: uuid.UUID) -> ShopItem | None:
        result = await self._session.execute(select(ShopItem).where(ShopItem.id == item_id))
        return result.scalar_one_or_none()

    async def get_user_shop_item(self, item_id: uuid.UUID) -> UserShopItem | None:
        result = await self._session.execute(
            select(UserShopItem).where(
                UserShopItem.user_id == self._user_id, UserShopItem.item_id == item_id
            )
        )
        return result.scalar_one_or_none()

    async def get_balance(self) -> UserBalance | None:
        result = await self._session.execute(
            select(UserBalance).where(UserBalance.user_id == self._user_id)
        )
        return result.scalar_one_or_none()

    async def lock_balance(self) -> UserBalance | None:
        result = await self._session.execute(
            select(UserBalance).where(UserBalance.user_id == self._user_id).with_for_update()
        )
        return result.scalar_one_or_none()

    async def create_balance(self, coins: int) -> UserBalance:
        balance = UserBalance(user_id=self._user_id, coins=coins)
        self._session.add(balance)
        await self._session.flush()
        return balance

    async def update_balance(self, balance: UserBalance) -> UserBalance:
        await self._session.flush()
        await self._session.refresh(balance)
        return balance

    async def create_user_shop_item(self, item_id: uuid.UUID) -> UserShopItem:
        owned = UserShopItem(user_id=self._user_id, item_id=item_id)
        self._session.add(owned)
        await self._session.flush()
        return owned

    async def create_focus_session(self, session: FocusSession) -> FocusSession:
        session.user_id = self._user_id
        self._session.add(session)
        await self._session.flush()
        await self._session.refresh(session)
        return session

    async def get_focus_session(self, session_id: uuid.UUID) -> FocusSession | None:
        result = await self._session.execute(
            select(FocusSession).where(
                FocusSession.id == session_id, FocusSession.user_id == self._user_id
            )
        )
        return result.scalar_one_or_none()

    async def update_focus_session(self, session: FocusSession) -> FocusSession:
        await self._session.flush()
        await self._session.refresh(session)
        return session

    async def list_sessions(self, *, limit: int = 50, offset: int = 0) -> Sequence[FocusSession]:
        result = await self._session.execute(
            select(FocusSession)
            .where(FocusSession.user_id == self._user_id)
            .order_by(FocusSession.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(result.scalars().all())

    async def get_active_items(self) -> list[UserActiveItem]:
        result = await self._session.execute(
            select(UserActiveItem)
            .where(UserActiveItem.user_id == self._user_id)
            .options(selectinload(UserActiveItem.item))
        )
        return list(result.scalars().all())

    async def set_active_item(self, category: str, item_id: uuid.UUID) -> UserActiveItem:
        await self._session.execute(
            delete(UserActiveItem).where(
                UserActiveItem.user_id == self._user_id,
                UserActiveItem.category == category,
            )
        )
        active = UserActiveItem(
            id=uuid.uuid4(),
            user_id=self._user_id,
            category=category,
            item_id=item_id,
        )
        self._session.add(active)
        await self._session.flush()
        await self._session.refresh(active)
        return active

    async def remove_active_item(self, category: str) -> None:
        await self._session.execute(
            delete(UserActiveItem).where(
                UserActiveItem.user_id == self._user_id,
                UserActiveItem.category == category,
            )
        )
        await self._session.flush()

    async def get_task_focus_times(
        self, user_id: uuid.UUID, task_ids: list[uuid.UUID]
    ) -> dict[uuid.UUID, int]:
        if not task_ids:
            return {}
        duration_expr = func.extract(
            "epoch",
            FocusTaskSegment.ended_at - FocusTaskSegment.started_at,
        )
        result = await self._session.execute(
            select(
                FocusTaskSegment.task_id,
                func.coalesce(func.sum(duration_expr), 0).label("total_sec"),
            )
            .where(
                FocusTaskSegment.user_id == user_id,
                FocusTaskSegment.task_id.in_(task_ids),
                FocusTaskSegment.ended_at.is_not(None),
            )
            .group_by(FocusTaskSegment.task_id)
        )
        return {row.task_id: int(row.total_sec) for row in result.all()}
