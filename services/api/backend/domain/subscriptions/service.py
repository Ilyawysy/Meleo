from __future__ import annotations

import uuid
from datetime import datetime, timezone

from backend.domain.subscriptions.entities import UserSubscription
from backend.domain.subscriptions.repository import SubscriptionRepository


class SubscriptionService:
    def __init__(self, repo: SubscriptionRepository) -> None:
        self._repo = repo

    async def ensure_subscription(self, user_id: uuid.UUID) -> UserSubscription:
        return await self._repo.upsert(user_id)

    async def get_subscription(self, user_id: uuid.UUID) -> UserSubscription:
        sub = await self._repo.get_by_user_id(user_id)
        if sub is None:
            sub = await self._repo.upsert(user_id)
        return sub

    VALID_TIERS = ("free", "pro")

    async def set_tier(
        self, user_id: uuid.UUID, tier: str, source: str | None = None
    ) -> UserSubscription:
        if tier not in self.VALID_TIERS:
            raise ValueError(f"Invalid tier: {tier!r}. Must be one of {self.VALID_TIERS}")
        kwargs: dict = {"tier": tier}
        if source is not None:
            kwargs["source"] = source
        if tier == "pro":
            kwargs["activated_at"] = datetime.now(tz=timezone.utc)
        return await self._repo.upsert(user_id, **kwargs)

    async def increment_chat(self, user_id: uuid.UUID) -> int:
        return await self._repo.increment_chat_counter(user_id)
