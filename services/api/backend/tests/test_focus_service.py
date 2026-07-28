from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional as _Optional
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from pydantic import BaseModel as _BaseModel
from pydantic import Field as _Field
from pydantic import field_validator as _field_validator

from backend.domain.focus.entities import (
    FocusSession,
    FocusSessionStatus,
    UserBalance,
)
from backend.domain.focus.service import (
    FocusService,
    InsufficientFundsError,
    InvalidSessionTransitionError,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

USER_ID = uuid.uuid4()
SESSION_ID = uuid.uuid4()
NOW = datetime(2026, 1, 15, 10, 0, 0, tzinfo=timezone.utc)


def _make_session(
    status: FocusSessionStatus = FocusSessionStatus.created,
    active_elapsed_sec: int = 0,
    started_at: datetime | None = None,
    last_state_change_at: datetime | None = None,
    credited_minutes: int | None = None,
    session_id: uuid.UUID | None = None,
) -> FocusSession:
    session = MagicMock(spec=FocusSession)
    session.id = session_id or SESSION_ID
    session.user_id = USER_ID
    session.planned_duration_sec = 1800
    session.status = status
    session.active_elapsed_sec = active_elapsed_sec
    session.last_state_change_at = last_state_change_at or NOW
    session.started_at = started_at
    session.ended_at = None
    session.task_id = None
    session.earned_coins = 0
    session.earned_xp = 0
    session.credited_minutes = credited_minutes
    session.session_day = None
    session.undo_deadline_at = None
    return session


def _make_balance(coins: int = 100) -> UserBalance:
    balance = MagicMock(spec=UserBalance)
    balance.user_id = USER_ID
    balance.coins = coins
    return balance


def _make_repo(
    session: FocusSession | None = None,
    balance: UserBalance | None = None,
) -> AsyncMock:
    repo = AsyncMock()
    repo.get_focus_session.return_value = session
    repo.update_focus_session.side_effect = lambda s: s
    repo.get_balance.return_value = balance
    repo.lock_balance.return_value = balance
    repo.create_balance.return_value = _make_balance(0)
    return repo


def _make_db_session() -> MagicMock:
    """Return a fake SQLAlchemy AsyncSession that is already in a transaction."""
    db = MagicMock()
    db.in_transaction.return_value = True
    # begin_nested returns an async context manager
    nested_ctx = MagicMock()
    nested_ctx.__aenter__ = AsyncMock(return_value=None)
    nested_ctx.__aexit__ = AsyncMock(return_value=False)
    db.begin_nested.return_value = nested_ctx
    return db


def _make_service(repo=None, db=None, gamification=None) -> FocusService:
    if repo is None:
        repo = _make_repo()
    if db is None:
        db = _make_db_session()
    return FocusService(repo, db, USER_ID, gamification_service=gamification)


# ---------------------------------------------------------------------------
# Tests: get_balance
# ---------------------------------------------------------------------------


class TestGetBalance:
    @pytest.mark.asyncio
    async def test_get_balance_returns_existing(self):
        balance = _make_balance(50)
        repo = _make_repo(balance=balance)
        service = _make_service(repo=repo)

        result = await service.get_balance()

        assert result.coins == 50
        repo.create_balance.assert_not_called()

    @pytest.mark.asyncio
    async def test_get_balance_creates_when_missing(self):
        repo = _make_repo(balance=None)
        repo.create_balance.return_value = _make_balance(0)
        service = _make_service(repo=repo)

        result = await service.get_balance()

        repo.create_balance.assert_called_once_with(0)
        assert result.coins == 0


# ---------------------------------------------------------------------------
# Tests: create_session
# ---------------------------------------------------------------------------


class TestCreateSession:
    @pytest.mark.asyncio
    async def test_create_session_creates_in_running(self):
        """Server creates sessions directly in running status."""
        created_session = _make_session(status=FocusSessionStatus.running, started_at=NOW)
        repo = _make_repo()
        repo.create_focus_session.return_value = created_session
        service = _make_service(repo=repo)

        result = await service.create_session(
            planned_duration_sec=1800, task_id=None, room_id=uuid.uuid4()
        )

        repo.create_focus_session.assert_called_once()
        assert result.status == FocusSessionStatus.running
        assert result.started_at is not None

    @pytest.mark.asyncio
    async def test_create_session_with_task_id(self):
        task_id = uuid.uuid4()
        created_session = _make_session(status=FocusSessionStatus.running, started_at=NOW)
        created_session.task_id = task_id
        repo = _make_repo()
        repo.create_focus_session.return_value = created_session
        service = _make_service(repo=repo)

        result = await service.create_session(
            planned_duration_sec=900, task_id=task_id, room_id=uuid.uuid4()
        )

        assert result.task_id == task_id

    @pytest.mark.asyncio
    async def test_session_not_found_raises_value_error(self):
        repo = _make_repo(session=None)
        service = _make_service(repo=repo)

        with pytest.raises(ValueError, match="Session not found"):
            await service.update_session_state(SESSION_ID, FocusSessionStatus.finished)


# ---------------------------------------------------------------------------
# Tests: update_session_state — finish (running → finished)
# ---------------------------------------------------------------------------


class TestUpdateSessionStateFinish:
    @pytest.mark.asyncio
    async def test_finish_from_running_sets_ended_at(self):
        start = datetime(2026, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        session = _make_session(
            status=FocusSessionStatus.running,
            started_at=start,
            last_state_change_at=start,
            active_elapsed_sec=0,
        )
        balance = _make_balance(100)
        repo = _make_repo(session=session, balance=balance)
        service = _make_service(repo=repo)

        updated, result_balance = await service.update_session_state(
            SESSION_ID, FocusSessionStatus.finished
        )

        assert updated.status == FocusSessionStatus.finished
        assert updated.ended_at is not None
        assert result_balance is not None

    @pytest.mark.asyncio
    async def test_finish_from_created_raises_invalid_transition(self):
        session = _make_session(status=FocusSessionStatus.created)
        repo = _make_repo(session=session)
        service = _make_service(repo=repo)

        with pytest.raises(InvalidSessionTransitionError):
            await service.update_session_state(SESSION_ID, FocusSessionStatus.finished)


# ---------------------------------------------------------------------------
# Tests: update_session_state — cancel
# ---------------------------------------------------------------------------


class TestUpdateSessionStateCancel:
    @pytest.mark.asyncio
    async def test_cancel_from_created_raises_invalid_transition(self):
        """Cancel from created is local-only; server rejects it."""
        session = _make_session(status=FocusSessionStatus.created)
        repo = _make_repo(session=session)
        service = _make_service(repo=repo)

        with pytest.raises(InvalidSessionTransitionError):
            await service.update_session_state(SESSION_ID, FocusSessionStatus.cancelled)

    @pytest.mark.asyncio
    async def test_cancel_from_running_accumulates_elapsed(self):
        start = datetime(2026, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        session = _make_session(
            status=FocusSessionStatus.running,
            started_at=start,
            last_state_change_at=start,
            active_elapsed_sec=0,
        )
        repo = _make_repo(session=session)
        service = _make_service(repo=repo)

        with patch("backend.domain.focus.service.datetime") as mock_dt:
            now_val = datetime(2026, 1, 15, 10, 10, 0, tzinfo=timezone.utc)
            mock_dt.now.return_value = now_val

            updated, balance = await service.update_session_state(
                SESSION_ID, FocusSessionStatus.cancelled
            )

        assert updated.status == FocusSessionStatus.cancelled
        assert updated.active_elapsed_sec == 600  # 10 minutes
        assert balance is None

    @pytest.mark.asyncio
    async def test_cancel_from_finished_raises_invalid_transition(self):
        session = _make_session(status=FocusSessionStatus.finished)
        repo = _make_repo(session=session)
        service = _make_service(repo=repo)

        with pytest.raises(InvalidSessionTransitionError):
            await service.update_session_state(SESSION_ID, FocusSessionStatus.cancelled)


# ---------------------------------------------------------------------------
# Tests: update_session_state — finish with elapsed_override_sec
# ---------------------------------------------------------------------------


class TestUpdateSessionStateFinishWithElapsedOverride:
    @pytest.mark.asyncio
    async def test_finish_with_elapsed_override_uses_client_value(self):
        start = datetime(2026, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        session = _make_session(
            status=FocusSessionStatus.running,
            started_at=start,
            last_state_change_at=start,
            active_elapsed_sec=0,
        )
        session.planned_duration_sec = 1800
        balance = _make_balance(100)
        repo = _make_repo(session=session, balance=balance)
        service = _make_service(repo=repo)

        with patch("backend.domain.focus.service.datetime") as mock_dt:
            now_val = datetime(2026, 1, 15, 10, 30, 0, tzinfo=timezone.utc)
            mock_dt.now.return_value = now_val

            updated, _ = await service.update_session_state(
                SESSION_ID, FocusSessionStatus.finished, elapsed_override_sec=900
            )

        # Client said 900s (15 min), server trusts it (capped at planned_duration_sec)
        assert updated.active_elapsed_sec == 900

    @pytest.mark.asyncio
    async def test_finish_elapsed_override_capped_at_wall_clock(self):
        """elapsed_override_sec cannot exceed wall-clock time since started_at."""
        start = datetime(2026, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        session = _make_session(
            status=FocusSessionStatus.running,
            started_at=start,
            last_state_change_at=start,
            active_elapsed_sec=0,
        )
        session.planned_duration_sec = 1800
        balance = _make_balance(100)
        repo = _make_repo(session=session, balance=balance)
        service = _make_service(repo=repo)

        with patch("backend.domain.focus.service.datetime") as mock_dt:
            # Only 10 minutes of wall-clock time
            now_val = datetime(2026, 1, 15, 10, 10, 0, tzinfo=timezone.utc)
            mock_dt.now.return_value = now_val

            updated, _ = await service.update_session_state(
                SESSION_ID, FocusSessionStatus.finished, elapsed_override_sec=1800
            )

        # Capped at wall-clock: 600s (10 min), not 1800
        assert updated.active_elapsed_sec == 600


# ---------------------------------------------------------------------------
# Tests: update_session_task
# ---------------------------------------------------------------------------


class TestUpdateSessionTask:
    @pytest.mark.asyncio
    async def test_update_task_happy_path(self):
        session = _make_session(status=FocusSessionStatus.running, started_at=NOW)
        task_id = uuid.uuid4()
        repo = _make_repo(session=session)
        service = _make_service(repo=repo)

        updated = await service.update_session_task(SESSION_ID, task_id)

        assert updated.task_id == task_id

    @pytest.mark.asyncio
    async def test_update_task_session_not_found_raises(self):
        repo = _make_repo(session=None)
        service = _make_service(repo=repo)

        with pytest.raises(ValueError, match="Session not found"):
            await service.update_session_task(SESSION_ID, uuid.uuid4())

    @pytest.mark.asyncio
    @pytest.mark.parametrize(
        "terminal_status",
        [
            FocusSessionStatus.finished,
            FocusSessionStatus.cancelled,
        ],
    )
    async def test_update_task_for_terminal_session_raises(self, terminal_status):
        session = _make_session(status=terminal_status)
        repo = _make_repo(session=session)
        service = _make_service(repo=repo)

        with pytest.raises(InvalidSessionTransitionError):
            await service.update_session_task(SESSION_ID, uuid.uuid4())


# ---------------------------------------------------------------------------
# Tests: purchase_item
# ---------------------------------------------------------------------------


class TestPurchaseItem:
    @pytest.mark.asyncio
    async def test_purchase_insufficient_funds_raises(self):
        item_id = uuid.uuid4()
        shop_item = MagicMock()
        shop_item.price = 500
        shop_item.required_level = 0

        balance = _make_balance(coins=100)  # Not enough

        repo = _make_repo(balance=balance)
        repo.get_shop_item.return_value = shop_item
        repo.get_user_shop_item.return_value = None
        repo.lock_balance.return_value = balance

        service = _make_service(repo=repo)

        with pytest.raises(InsufficientFundsError):
            await service.purchase_item(item_id)

    @pytest.mark.asyncio
    async def test_purchase_item_not_found_raises(self):
        item_id = uuid.uuid4()
        repo = _make_repo()
        repo.get_shop_item.return_value = None
        service = _make_service(repo=repo)

        with pytest.raises(ValueError, match="Item not found"):
            await service.purchase_item(item_id)

    @pytest.mark.asyncio
    async def test_purchase_already_owned_returns_existing(self):
        item_id = uuid.uuid4()
        shop_item = MagicMock()
        shop_item.price = 50
        existing_owned = MagicMock()
        balance = _make_balance(coins=200)

        repo = _make_repo(balance=balance)
        repo.get_shop_item.return_value = shop_item
        repo.get_user_shop_item.return_value = existing_owned
        service = _make_service(repo=repo)

        result_balance, owned, item = await service.purchase_item(item_id)

        assert owned is existing_owned
        repo.update_balance.assert_not_called()


# ---------------------------------------------------------------------------
# Tests: list_sessions
# ---------------------------------------------------------------------------


class TestListSessions:
    @pytest.mark.asyncio
    async def test_list_sessions_delegates_to_repo(self):
        sessions = [_make_session(), _make_session()]
        repo = _make_repo()
        repo.list_sessions.return_value = sessions
        service = _make_service(repo=repo)

        result = await service.list_sessions(limit=10, offset=0)

        repo.list_sessions.assert_called_once_with(limit=10, offset=0)
        assert len(result) == 2


# ---------------------------------------------------------------------------
# Tests: apply_actions_batch
# ---------------------------------------------------------------------------


class TestApplyActionsBatch:
    @pytest.mark.asyncio
    async def test_batch_invalid_transition_raises_and_records_failure(self):
        session = _make_session(status=FocusSessionStatus.created)
        repo = _make_repo(session=session)
        service = _make_service(repo=repo)

        # Try to finish from created — invalid (must be running first)
        actions = [{"action": FocusSessionStatus.finished}]

        with pytest.raises(InvalidSessionTransitionError):
            await service.apply_actions_batch(SESSION_ID, actions)

    @pytest.mark.asyncio
    async def test_batch_session_not_found_raises(self):
        repo = _make_repo(session=None)
        service = _make_service(repo=repo)

        actions = [{"action": FocusSessionStatus.finished}]

        with pytest.raises(ValueError, match="Session not found"):
            await service.apply_actions_batch(SESSION_ID, actions)


# ---------------------------------------------------------------------------
# Tests: FocusSessionCreate validator logic (inline Pydantic model)
# We replicate the validator logic from focus.py rather than importing the
# router module directly, because importing the routers package triggers
# database SSL setup (PG_SSLROOTCERT) which is not available in unit tests.
# ---------------------------------------------------------------------------


class _FocusSessionCreate(_BaseModel):
    """Local replica of FocusSessionCreate from backend/apps/api/routers/focus.py."""

    planned_duration_sec: int = _Field(..., ge=300, le=10800)
    task_id: _Optional[uuid.UUID] = None

    @_field_validator("planned_duration_sec")
    @classmethod
    def validate_duration(cls, value: int) -> int:
        if value % 300 != 0:
            raise ValueError("planned_duration_sec must be in 5-minute steps")
        return value


class TestFocusSessionCreateValidator:
    def test_duration_not_multiple_of_300_raises(self):
        from pydantic import ValidationError

        with pytest.raises((ValidationError, ValueError)):
            _FocusSessionCreate(planned_duration_sec=350)

    def test_duration_below_minimum_raises(self):
        from pydantic import ValidationError

        with pytest.raises((ValidationError, ValueError)):
            _FocusSessionCreate(planned_duration_sec=0)

    def test_duration_valid_passes(self):
        obj = _FocusSessionCreate(planned_duration_sec=1800)
        assert obj.planned_duration_sec == 1800

    def test_duration_multiple_of_300_minimum_passes(self):
        obj = _FocusSessionCreate(planned_duration_sec=300)
        assert obj.planned_duration_sec == 300
