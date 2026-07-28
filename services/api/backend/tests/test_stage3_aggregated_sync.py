from __future__ import annotations

import contextlib
import os
import sys
import types
import uuid

import pytest
from starlette.requests import Request

os.environ.setdefault("DB_SSL_DISABLE", "1")

# Local test environment may not have redis installed.
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

from backend.apps.api.routers import sync as sync_router
from backend.domain.sync.cursor import SyncCursor
from backend.domain.sync.service import FocusSnapshotData


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


class _DummyReadSession:
    async def __aenter__(self) -> object:
        return object()

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False


class _FakeUserRow:
    """Mimics UserStateVersion with fixed version numbers."""

    notifications_version = 3
    messages_version = 12
    focus_version = 0


class _FakeSession:
    """Mimics AsyncSession.get() returning a fixed UserStateVersion row."""

    async def get(self, model: object, pk: object) -> _FakeUserRow:
        return _FakeUserRow()

    async def execute(self, stmt: object) -> object:
        from unittest.mock import MagicMock

        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = None
        mock_result.scalars.return_value.all.return_value = []
        return mock_result


# ETag computed from _FakeUserRow versions: "notif_v-msgs_v-focus_v"
_ETAG = '"3-12-0"'


@pytest.mark.asyncio
async def test_sync_etag_is_applied_when_header_matches(monkeypatch: pytest.MonkeyPatch) -> None:
    call_count = {"fetches": 0}

    async def _noop_rate_limit(request, user_id=None) -> None:
        return None

    async def _fake_fetch(*args, **kwargs):
        call_count["fetches"] += 1
        return [], None

    async def _fake_focus_snapshot(*args, **kwargs):
        return FocusSnapshotData(
            balance_coins=0.0,
            owned_item_ids=[],
            shop_items=[],
            profile=None,
        )

    async def _fake_segments(*args, **kwargs):
        return []

    async def _fake_focus_domain_fetch(*args, **kwargs):
        return [], None

    async def _fake_onboarding_flag(*args, **kwargs) -> bool:
        return False

    async def _fake_subscription_snapshot(*args, **kwargs):
        return {"tier": "free", "chat_messages_used": 0, "chat_messages_limit": None}

    async def _fake_daily_stats(*args, **kwargs):
        return []

    @contextlib.asynccontextmanager
    async def _fake_session_local():
        yield _FakeSession()

    monkeypatch.setattr(sync_router, "SessionLocal", _fake_session_local)
    monkeypatch.setattr(sync_router, "rate_limit_sync", _noop_rate_limit)
    monkeypatch.setattr(sync_router, "get_onboarding_flag", _fake_onboarding_flag)
    monkeypatch.setattr(sync_router, "get_notification_changes", _fake_fetch)
    monkeypatch.setattr(sync_router, "get_message_changes", _fake_fetch)
    monkeypatch.setattr(sync_router, "get_focus_room_changes", _fake_focus_domain_fetch)
    monkeypatch.setattr(sync_router, "get_task_changes", _fake_focus_domain_fetch)
    monkeypatch.setattr(sync_router, "get_checklist_item_changes", _fake_focus_domain_fetch)
    monkeypatch.setattr(sync_router, "get_focus_session_changes", _fake_fetch)
    monkeypatch.setattr(sync_router, "get_all_focus_task_segments", _fake_segments)
    monkeypatch.setattr(sync_router, "get_focus_snapshot", _fake_focus_snapshot)
    monkeypatch.setattr(sync_router, "get_subscription_snapshot", _fake_subscription_snapshot)

    # Patch GamificationService to avoid DB calls
    class _FakeGamService:
        async def roll_forward(self):
            pass

        async def get_daily_stats(self, days: int):
            return []

    class _FakeFocusRepo:
        async def get_active_items(self):
            return []

        async def list_shop_items_with_owned_ids(self):
            return [], set()

    monkeypatch.setattr(sync_router, "GamificationService", lambda *a, **kw: _FakeGamService())
    monkeypatch.setattr(sync_router, "SqlAlchemyFocusRepository", lambda *a, **kw: _FakeFocusRepo())
    monkeypatch.setattr(sync_router, "SqlAlchemyGamificationRepository", lambda *a, **kw: None)

    user_id = uuid.uuid4()
    session = _FakeSession()

    first_page_request = _make_request({"If-None-Match": _ETAG})
    first_page_response = await sync_router.sync_changes(
        request=first_page_request,
        cursor=None,
        limit=25,
        session=session,
        current_user_id=user_id,
    )
    assert first_page_response.status_code == 304

    cursor_request = _make_request({"If-None-Match": _ETAG})
    cursor_response = await sync_router.sync_changes(
        request=cursor_request,
        cursor=SyncCursor.initial().encode(),
        limit=25,
        session=session,
        current_user_id=user_id,
    )
    assert cursor_response.status_code == 304

    no_header_request = _make_request({})
    no_header_response = await sync_router.sync_changes(
        request=no_header_request,
        cursor=SyncCursor.initial().encode(),
        limit=25,
        session=session,
        current_user_id=user_id,
    )
    assert no_header_response.status_code == 200
    assert no_header_response.headers.get("etag") == _ETAG
    # 3 domain fetchers: notifications + messages + focus (tasks disabled in Phase 1)
    assert call_count["fetches"] == 3
