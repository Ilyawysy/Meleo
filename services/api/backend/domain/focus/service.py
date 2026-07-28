from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Sequence, Tuple

from backend.domain.focus.entities import (
    FocusSession,
    FocusSessionStatus,
    FocusTaskSegment,
    ShopItem,
    UserBalance,
    UserShopItem,
)
from backend.domain.focus.repository import FocusRepository
from backend.domain.gamification.service import GamificationService
from backend.infrastructure.logging import get_logger


@dataclass
class BalanceSnapshot:
    """Lightweight read-only balance returned from state transitions."""

    user_id: uuid.UUID
    coins: int


class InsufficientFundsError(Exception):
    pass


class InvalidSessionTransitionError(Exception):
    pass


class FocusService:
    def __init__(
        self,
        repository: FocusRepository,
        session,
        user_id: uuid.UUID,
        gamification_service: GamificationService | None = None,
    ) -> None:
        self._repository = repository
        self._session = session
        self._user_id = user_id
        self._gamification = gamification_service
        self._logger = get_logger("focus_service")

    def _transaction_ctx(self):
        """Use nested transaction if one is already active."""
        return (
            self._session.begin_nested()
            if self._session.in_transaction()
            else self._session.begin()
        )

    async def list_shop_items_with_ownership(self) -> Tuple[Sequence[ShopItem], set[uuid.UUID]]:
        self._logger.info("focus_shop_items_with_ownership_start")
        items, owned_ids = await self._repository.list_shop_items_with_owned_ids()
        self._logger.info(
            "focus_shop_items_with_ownership_done",
            items=len(items),
            owned=len(owned_ids),
        )
        return items, owned_ids

    async def get_balance(self) -> UserBalance:
        self._logger.info("focus_balance_get_start")
        balance = await self._repository.get_balance()
        if balance is None:
            balance = await self._repository.create_balance(0)
        self._logger.info("focus_balance_get_done", coins=balance.coins)
        return balance

    async def purchase_item(self, item_id: uuid.UUID) -> tuple[UserBalance, UserShopItem, ShopItem]:
        self._logger.info("focus_shop_purchase_start", item_id=str(item_id))
        async with self._transaction_ctx():
            item = await self._repository.get_shop_item(item_id)
            if not item:
                raise ValueError("Item not found")

            existing = await self._repository.get_user_shop_item(item_id)
            if existing:
                balance = await self.get_balance()
                self._logger.info(
                    "focus_shop_purchase_already_owned",
                    item_id=str(item_id),
                    coins=balance.coins,
                )
                return balance, existing, item

            # Check level requirement
            if item.required_level > 0 and self._gamification:
                profile = await self._gamification.get_or_create_profile()
                from backend.domain.gamification.calculator import compute_xp_level

                user_level = compute_xp_level(profile.xp)
                if user_level < item.required_level:
                    raise ValueError(f"Level {item.required_level} required to purchase this item")

            balance = await self._repository.lock_balance()
            if balance is None:
                balance = await self._repository.create_balance(0)

            if balance.coins < item.price:
                raise InsufficientFundsError("Not enough coins")

            balance.coins -= item.price
            owned = await self._repository.create_user_shop_item(item_id)
            await self._repository.update_balance(balance)

            self._logger.info(
                "shop_item_purchased",
                user_id=str(self._user_id),
                item_id=str(item_id),
                price=item.price,
                coins=balance.coins,
            )
            return balance, owned, item

    async def create_session(
        self,
        planned_duration_sec: int,
        task_id: uuid.UUID | None,
        room_id: uuid.UUID,
    ) -> FocusSession:
        """Create a new session directly in running state.

        The 'created' status is local-only (mobile UI) and never reaches the server.
        """
        self._logger.info(
            "focus_session_create_start",
            planned_duration_sec=planned_duration_sec,
            task_id=str(task_id) if task_id else None,
        )
        now = datetime.now(timezone.utc)

        # Compute session_day using gamification profile timezone
        session_day = None
        if self._gamification:
            profile = await self._gamification.get_or_create_profile()
            from backend.domain.gamification.calculator import focus_date

            session_day = focus_date(now, profile.home_tz, profile.day_cutoff_hour)

        session = FocusSession(
            user_id=self._user_id,
            planned_duration_sec=planned_duration_sec,
            status=FocusSessionStatus.running,
            active_elapsed_sec=0,
            last_state_change_at=now,
            started_at=now,
            ended_at=None,
            room_id=room_id,
            task_id=task_id,
            earned_coins=0,
            session_day=session_day,
        )
        created = await self._repository.create_focus_session(session)
        self._logger.info("focus_session_created", session_id=str(created.id))
        return created

    async def get_session(self, session_id: uuid.UUID) -> FocusSession | None:
        return await self._repository.get_focus_session(session_id)

    async def update_session_task(
        self, session_id: uuid.UUID, task_id: uuid.UUID | None
    ) -> FocusSession:
        self._logger.info(
            "focus_session_task_update_start",
            session_id=str(session_id),
            task_id=str(task_id) if task_id else None,
        )
        session = await self._repository.get_focus_session(session_id)
        if not session:
            raise ValueError("Session not found")
        terminal_statuses = (
            FocusSessionStatus.finished,
            FocusSessionStatus.cancelled,
        )
        if session.status in terminal_statuses:
            raise InvalidSessionTransitionError("Cannot update task for completed/credited session")
        session.task_id = task_id
        updated = await self._repository.update_focus_session(session)
        self._logger.info(
            "focus_session_task_update_done",
            session_id=str(updated.id),
            task_id=str(updated.task_id) if updated.task_id else None,
        )
        return updated

    async def update_session_state(
        self,
        session_id: uuid.UUID,
        action: FocusSessionStatus,
        elapsed_override_sec: int | None = None,
    ) -> tuple[FocusSession, BalanceSnapshot | None]:
        self._logger.info(
            "focus_session_state_update_start",
            session_id=str(session_id),
            action=action.value,
        )
        session = await self._repository.get_focus_session(session_id)
        if not session:
            raise ValueError("Session not found")

        # ── Finish (running → finished, server computes rewards) ──
        if action == FocusSessionStatus.finished:
            if session.status == FocusSessionStatus.finished:
                balance = await self.get_balance()
                return session, BalanceSnapshot(user_id=self._user_id, coins=balance.coins)
            if session.status != FocusSessionStatus.running:
                raise InvalidSessionTransitionError("Invalid transition to finished")
            now = datetime.now(timezone.utc)
            elapsed = max(0, int((now - session.last_state_change_at).total_seconds()))
            session.active_elapsed_sec += elapsed
            if elapsed_override_sec is not None:
                capped = min(elapsed_override_sec, session.planned_duration_sec)
                # Sanity check: client elapsed cannot exceed wall-clock time
                if session.started_at:
                    wall_clock = int((now - session.started_at).total_seconds())
                    capped = min(capped, wall_clock)
                session.active_elapsed_sec = capped
            session.ended_at = now

            credited_minutes = session.active_elapsed_sec // 60

            async with self._transaction_ctx():
                balance = await self._repository.lock_balance()
                if balance is None:
                    balance = await self._repository.create_balance(0)

                if self._gamification and credited_minutes > 0:
                    await self._gamification.calculate_and_award_session(
                        session, credited_minutes, balance
                    )
                else:
                    session.credited_minutes = credited_minutes
                    session.earned_coins = 0
                    session.earned_xp = 0
                    session.status = FocusSessionStatus.finished

                session.last_state_change_at = now
                updated = await self._repository.update_focus_session(session)
                final_coins = balance.coins

            self._logger.info(
                "focus_session_finished",
                session_id=str(updated.id),
                credited_minutes=updated.credited_minutes,
                earned_xp=updated.earned_xp,
                earned_coins=updated.earned_coins,
            )
            return updated, BalanceSnapshot(user_id=self._user_id, coins=final_coins)

        # ── Cancel (running → cancelled, no rewards) ──
        if action == FocusSessionStatus.cancelled:
            if session.status != FocusSessionStatus.running:
                raise InvalidSessionTransitionError("Invalid transition to cancelled")
            now = datetime.now(timezone.utc)
            elapsed = max(0, int((now - session.last_state_change_at).total_seconds()))
            session.active_elapsed_sec += elapsed
            session.status = FocusSessionStatus.cancelled
            session.last_state_change_at = now
            session.ended_at = now
            session.credited_minutes = 0
            session.earned_coins = 0
            session.earned_xp = 0
            updated = await self._repository.update_focus_session(session)
            self._logger.info(
                "focus_session_cancelled",
                session_id=str(updated.id),
                active_elapsed_sec=updated.active_elapsed_sec,
            )
            return updated, None

        raise InvalidSessionTransitionError("Unsupported action")

    async def apply_actions_batch(
        self,
        session_id: uuid.UUID,
        actions: list[dict],
    ) -> tuple[FocusSession, BalanceSnapshot | None, list[dict]]:
        """Apply a batch of actions sequentially. Rollback entire batch on error."""
        results: list[dict] = []
        final_session: FocusSession | None = None
        final_balance: BalanceSnapshot | None = None

        async with self._transaction_ctx():
            for idx, action_entry in enumerate(actions):
                try:
                    action = action_entry["action"]
                    elapsed_override_sec = action_entry.get("elapsed_override_sec")

                    session, balance = await self.update_session_state(
                        session_id=session_id,
                        action=action,
                        elapsed_override_sec=elapsed_override_sec,
                    )
                    final_session = session
                    if balance is not None:
                        final_balance = balance
                    results.append({"index": idx, "ok": True})
                except (InvalidSessionTransitionError, ValueError) as exc:
                    results.append({"index": idx, "ok": False, "error": str(exc)})
                    raise
                except Exception as exc:
                    results.append({"index": idx, "ok": False, "error": str(exc)})
                    raise

        if final_session is None:
            session = await self._repository.get_focus_session(session_id)
            if not session:
                raise ValueError("Session not found")
            final_session = session

        return final_session, final_balance, results

    async def save_task_segments(
        self,
        session_id: uuid.UUID,
        segments: list[dict],
    ) -> None:
        """Persist task time segments sent by the mobile client.

        Replaces all existing segments for the session to handle retries safely.
        """
        from sqlalchemy import delete

        await self._session.execute(
            delete(FocusTaskSegment).where(FocusTaskSegment.session_id == session_id)
        )
        for seg in segments:
            entity = FocusTaskSegment(
                id=uuid.uuid4(),
                session_id=session_id,
                task_id=seg["task_id"],
                user_id=self._user_id,
                started_at=seg["started_at"],
                ended_at=seg.get("ended_at"),
            )
            self._session.add(entity)
        await self._session.flush()

    async def get_task_focus_times(
        self,
        task_ids: list[uuid.UUID],
    ) -> dict[uuid.UUID, int]:
        """Return total focus seconds per task from segments."""
        return await self._repository.get_task_focus_times(self._user_id, task_ids)

    async def list_sessions(self, limit: int = 50, offset: int = 0) -> Sequence[FocusSession]:
        self._logger.info("focus_session_list_start", limit=limit, offset=offset)
        sessions = await self._repository.list_sessions(limit=limit, offset=offset)
        self._logger.info("focus_session_list_done", count=len(sessions))
        return sessions

    async def get_active_items(self) -> dict[str, uuid.UUID]:
        items = await self._repository.get_active_items()
        return {ai.category: ai.item_id for ai in items}

    _ACTIVATABLE_CATEGORIES = {"aura", "skin", "environment"}

    async def activate_item(self, item_id: uuid.UUID) -> dict[str, uuid.UUID]:
        item = await self._repository.get_shop_item(item_id)
        if not item:
            raise ValueError("Item not found")
        if item.category.value not in self._ACTIVATABLE_CATEGORIES:
            raise ValueError(f"Category {item.category.value} cannot be activated")
        if item.price > 0:
            existing = await self._repository.get_user_shop_item(item_id)
            if not existing:
                raise ValueError("Item not owned")
        # Check level requirement
        if item.required_level > 0 and self._gamification:
            profile = await self._gamification.get_or_create_profile()
            from backend.domain.gamification.calculator import compute_xp_level

            user_level = compute_xp_level(profile.xp)
            if user_level < item.required_level:
                raise ValueError(f"Level {item.required_level} required")
        await self._repository.set_active_item(item.category.value, item_id)
        return await self.get_active_items()

    async def deactivate_item(self, category: str) -> dict[str, uuid.UUID]:
        if category not in self._ACTIVATABLE_CATEGORIES:
            raise ValueError(f"Invalid category: {category}")
        await self._repository.remove_active_item(category)
        return await self.get_active_items()
