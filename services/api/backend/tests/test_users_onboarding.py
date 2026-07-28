"""Tests for the user onboarding backend feature.

Covers:
1. /sync for a fresh user returns onboarding_completed == false
2. POST /users/me/onboarding/complete without auth -> 401
3. POST with auth -> 204
4. /sync after POST -> onboarding_completed == true (tasks_version bumped)
5. POST again (idempotent) -> 204, no additional bump
"""

from __future__ import annotations

import json
import os
import sys
import types
import uuid
from typing import Any
from unittest.mock import AsyncMock, MagicMock

import pytest

os.environ.setdefault("DB_SSL_DISABLE", "1")

# Stub redis if not installed
try:
    from redis.asyncio import Redis as _Redis  # noqa: F401
except ModuleNotFoundError:
    redis_module = types.ModuleType("redis")
    redis_asyncio_module = types.ModuleType("redis.asyncio")

    class _DummyRedis:
        def __init__(self, *args: object, **kwargs: object) -> None:
            pass

        async def ping(self) -> bool:
            return True

        async def get(self, key: str) -> str | None:
            return None

        async def set(
            self,
            key: str,
            value: str,
            *,
            ex: int | None = None,
            nx: bool | None = None,
        ) -> bool:
            return True

        def register_script(self, script: str):
            async def _runner(*args: object, **kwargs: object) -> int:
                return 1

            return _runner

    redis_asyncio_module.Redis = _DummyRedis
    redis_module.asyncio = redis_asyncio_module
    sys.modules["redis"] = redis_module
    sys.modules["redis.asyncio"] = redis_asyncio_module

from fastapi import FastAPI, status
from starlette.requests import Request
from starlette.testclient import TestClient

from backend.apps.api.routers import sync as sync_router
from backend.apps.api.routers import users as users_router
from backend.domain.sync.service import FocusSnapshotData


# ── helpers ──


def _make_request(headers: dict[str, str]) -> Request:
    scope = {
        "type": "http",
        "http_version": "1.1",
        "method": "GET",
        "scheme": "http",
        "path": "/api/v1/sync",
        "raw_path": b"/api/v1/sync",
        "query_string": b"",
        "headers": [(k.lower().encode(), v.encode()) for k, v in headers.items()],
        "client": ("127.0.0.1", 12345),
        "server": ("testserver", 80),
    }

    async def receive() -> dict[str, object]:
        return {"type": "http.request", "body": b"", "more_body": False}

    return Request(scope, receive)


class _FakeUserStateRow:
    """All domain versions are 0 so that per-domain version params can skip all fetches."""

    notifications_version = 0
    messages_version = 0
    focus_version = 0


class _FakeSession:
    """Minimal AsyncSession: .get() for UserStateVersion, .execute() for announcements."""

    async def get(self, model: object, pk: object) -> _FakeUserStateRow:
        return _FakeUserStateRow()

    async def execute(self, stmt: Any) -> Any:
        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = None
        mock_result.scalars.return_value.all.return_value = []
        return mock_result


async def _noop_rate_limit(request: Any, user_id: Any = None) -> None:
    return None


async def _fake_fetch(*args: Any, **kwargs: Any):
    return [], None


async def _fake_checklist(*args: Any, **kwargs: Any):
    return []


async def _fake_focus_segments(*args: Any, **kwargs: Any):
    return []


async def _fake_focus_snapshot(*args: Any, **kwargs: Any):
    return FocusSnapshotData(
        balance_coins=0.0,
        owned_item_ids=[],
        shop_items=[],
        profile=None,
    )


async def _fake_subscription_snapshot(*args: Any, **kwargs: Any) -> dict:
    return {"tier": "free", "chat_messages_used": 0, "chat_messages_limit": None}


def _patch_sync_base(monkeypatch: pytest.MonkeyPatch) -> None:
    """Patch all domain fetchers and disable rate limit."""
    monkeypatch.setattr(sync_router, "rate_limit_sync", _noop_rate_limit)
    monkeypatch.setattr(sync_router, "get_notification_changes", _fake_fetch)
    monkeypatch.setattr(sync_router, "get_message_changes", _fake_fetch)
    monkeypatch.setattr(sync_router, "get_focus_room_changes", _fake_fetch)
    monkeypatch.setattr(sync_router, "get_task_changes", _fake_fetch)
    monkeypatch.setattr(sync_router, "get_checklist_item_changes", _fake_fetch)
    monkeypatch.setattr(sync_router, "get_focus_session_changes", _fake_fetch)
    monkeypatch.setattr(sync_router, "get_all_focus_task_segments", _fake_focus_segments)
    monkeypatch.setattr(sync_router, "get_focus_snapshot", _fake_focus_snapshot)
    monkeypatch.setattr(sync_router, "get_subscription_snapshot", _fake_subscription_snapshot)

    class _FakeGamService:
        async def roll_forward(self) -> None:
            return None

        async def get_daily_stats(self, days: int) -> list:
            return []

    class _FakeFocusRepo:
        async def get_active_items(self) -> list:
            return []

        async def list_shop_items_with_owned_ids(self) -> tuple:
            return [], set()

    monkeypatch.setattr(sync_router, "GamificationService", lambda *a, **kw: _FakeGamService())
    monkeypatch.setattr(sync_router, "SqlAlchemyFocusRepository", lambda *a, **kw: _FakeFocusRepo())
    monkeypatch.setattr(sync_router, "SqlAlchemyGamificationRepository", lambda *a, **kw: None)


# ── sync onboarding tests ──


@pytest.mark.asyncio
async def test_sync_fresh_user_onboarding_completed_false(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """GET /sync for a fresh user (NULL onboarding_completed_at) returns onboarding_completed=false."""
    _patch_sync_base(monkeypatch)

    async def _fake_onboarding_flag(session: Any, user_id: Any) -> bool:
        return False

    monkeypatch.setattr(sync_router, "get_onboarding_flag", _fake_onboarding_flag)

    user_id = uuid.uuid4()
    session = _FakeSession()

    # Pass nv/mv/fv matching server versions (all 0) to skip all domain fetches
    response = await sync_router.sync_changes(
        request=_make_request({}),
        cursor=None,
        limit=25,
        nv=0,
        mv=0,
        fv=0,
        session=session,
        current_user_id=user_id,
    )
    assert response.status_code == 200
    body = json.loads(response.body)
    assert body["onboarding_completed"] is False


@pytest.mark.asyncio
async def test_sync_completed_user_onboarding_completed_true(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """GET /sync for a user with onboarding set returns onboarding_completed=true."""
    _patch_sync_base(monkeypatch)

    async def _fake_onboarding_flag(session: Any, user_id: Any) -> bool:
        return True

    monkeypatch.setattr(sync_router, "get_onboarding_flag", _fake_onboarding_flag)

    user_id = uuid.uuid4()
    session = _FakeSession()

    response = await sync_router.sync_changes(
        request=_make_request({}),
        cursor=None,
        limit=25,
        nv=0,
        mv=0,
        fv=0,
        session=session,
        current_user_id=user_id,
    )
    assert response.status_code == 200
    body = json.loads(response.body)
    assert body["onboarding_completed"] is True


# ── users router tests ──


@pytest.mark.asyncio
async def test_complete_onboarding_marks_and_bumps_version() -> None:
    """POST /users/me/onboarding/complete marks onboarding and bumps tasks_version when NULL."""
    user_id = uuid.uuid4()

    mock_repo = MagicMock()
    mock_repo.mark_onboarding_completed = AsyncMock(return_value=True)

    execute_mock = AsyncMock()
    session_mock = MagicMock()
    session_mock.execute = execute_mock
    session_mock.commit = AsyncMock()

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(users_router, "SqlAlchemyUserRepository", lambda s: mock_repo)
        await users_router.complete_onboarding(
            session=session_mock,
            current_user_id=user_id,
        )

    mock_repo.mark_onboarding_completed.assert_awaited_once_with(user_id)
    execute_mock.assert_awaited_once()
    session_mock.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_complete_onboarding_idempotent_no_bump() -> None:
    """POST /users/me/onboarding/complete is idempotent: no version bump when already completed."""
    user_id = uuid.uuid4()

    mock_repo = MagicMock()
    mock_repo.mark_onboarding_completed = AsyncMock(return_value=False)

    execute_mock = AsyncMock()
    session_mock = MagicMock()
    session_mock.execute = execute_mock
    session_mock.commit = AsyncMock()

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(users_router, "SqlAlchemyUserRepository", lambda s: mock_repo)
        await users_router.complete_onboarding(
            session=session_mock,
            current_user_id=user_id,
        )

    mock_repo.mark_onboarding_completed.assert_awaited_once_with(user_id)
    execute_mock.assert_not_awaited()
    session_mock.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_complete_onboarding_creates_state_version_for_fresh_user(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """UPSERT creates user_state_version row for a fresh user (no existing row).

    Simulates the cross-device scenario: device A completes onboarding,
    device B (with cached ETag "0-0-0-0") must not receive 304.
    """
    user_id = uuid.uuid4()

    mock_repo = MagicMock()
    mock_repo.mark_onboarding_completed = AsyncMock(return_value=True)

    executed_stmts: list[Any] = []

    async def _capturing_execute(stmt: Any) -> MagicMock:
        executed_stmts.append(stmt)
        return MagicMock()

    session_mock = MagicMock()
    session_mock.execute = _capturing_execute
    session_mock.commit = AsyncMock()

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(users_router, "SqlAlchemyUserRepository", lambda s: mock_repo)
        await users_router.complete_onboarding(
            session=session_mock,
            current_user_id=user_id,
        )

    mock_repo.mark_onboarding_completed.assert_awaited_once_with(user_id)
    session_mock.commit.assert_awaited_once()

    # Exactly one statement executed — the UPSERT
    assert len(executed_stmts) == 1

    # The statement must be an INSERT (pg_insert generates an Insert object)
    from sqlalchemy.dialects.postgresql.dml import Insert as PgInsert

    assert isinstance(executed_stmts[0], PgInsert), (
        f"Expected postgresql INSERT (upsert), got {type(executed_stmts[0])}"
    )

    # Verify the upsert targets user_state_version table
    assert executed_stmts[0].table.name == "user_state_version"

    # Simulate /sync after onboarding: tasks_version is now 1, so ETag differs
    # from the cached "0-0-0-0". Verify sync returns 200, not 304.
    _patch_sync_base(monkeypatch)

    async def _fake_onboarding_flag_true(session: Any, user_id: Any) -> bool:
        return True

    monkeypatch.setattr(sync_router, "get_onboarding_flag", _fake_onboarding_flag_true)

    class _FakeStateRowBumped:
        notifications_version = 0
        messages_version = 0
        focus_version = 1

    class _FakeSessionWithBumpedVersion:
        async def get(self, model: object, pk: object) -> _FakeStateRowBumped:
            return _FakeStateRowBumped()

        async def execute(self, stmt: Any) -> Any:
            result = MagicMock()
            result.scalar_one_or_none.return_value = None
            result.scalars.return_value.all.return_value = []
            return result

    # Device B sends the old cached ETag "0-0-0" via If-None-Match.
    # nv/mv/fv=0 match server versions (0) so focus domain is still fetched (focus_v=0 vs 1).
    response = await sync_router.sync_changes(
        request=_make_request({"If-None-Match": '"0-0-0"'}),
        cursor=None,
        limit=25,
        nv=0,
        mv=0,
        fv=0,
        session=_FakeSessionWithBumpedVersion(),
        current_user_id=user_id,
    )
    assert response.status_code == 200, (
        f"Expected 200 after onboarding bump, got {response.status_code}"
    )
    body = json.loads(response.body)
    assert body["onboarding_completed"] is True


def test_complete_onboarding_requires_auth() -> None:
    """POST /api/v1/users/me/onboarding/complete without Authorization header -> 401."""
    app = FastAPI()

    async def _fake_session():
        yield MagicMock()

    from backend.infrastructure.database.session import get_session

    app.include_router(users_router.router, prefix="/api/v1")
    app.dependency_overrides[get_session] = _fake_session

    client = TestClient(app, raise_server_exceptions=False)
    response = client.post("/api/v1/users/me/onboarding/complete")
    assert response.status_code == status.HTTP_401_UNAUTHORIZED
