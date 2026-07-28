from __future__ import annotations

import importlib
import sys
import types
import uuid
from types import SimpleNamespace

import pytest

# Local test environment may not have redis installed.
# Provide a tiny stub so importing rate_limit/token_bucket works in unit tests.
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

from backend.domain.users.global_state_version import GlobalStateVersion
from backend.domain.users.state_version import UserStateVersion
from backend.infrastructure.etag import get_user_etag
from backend.infrastructure.rate_limit import (
    get_rate_limit_key,
    rate_limit_default,
    rate_limit_sync,
)
from backend.infrastructure.token_bucket import RateLimitBackendUnavailableError


class DummySession:
    def __init__(self, user_row: object | None, global_row: object | None) -> None:
        self._user_row = user_row
        self._global_row = global_row

    async def get(self, model: type[object], key: object) -> object | None:
        if model is UserStateVersion:
            return self._user_row
        if model is GlobalStateVersion:
            return self._global_row
        raise AssertionError(f"Unexpected model lookup: {model} / {key}")


def _make_request(
    *,
    state_user_id: str | None = None,
    device_id: str | None = None,
    ip: str = "127.0.0.1",
    path: str = "/api/v1/sync",
) -> SimpleNamespace:
    state = SimpleNamespace()
    if state_user_id is not None:
        state.user_id = state_user_id

    headers: dict[str, str] = {}
    if device_id is not None:
        headers["X-Device-ID"] = device_id

    return SimpleNamespace(
        state=state,
        headers=headers,
        client=SimpleNamespace(host=ip),
        url=SimpleNamespace(path=path),
    )


def _ensure_prometheus_stub() -> None:
    if "prometheus_client" in sys.modules:
        return

    prometheus_module = types.ModuleType("prometheus_client")

    class _DummyMetric:
        def labels(self, **kwargs: object) -> "_DummyMetric":
            return self

        def inc(self) -> None:
            return None

        def observe(self, value: float) -> None:
            return None

    def _counter(*args: object, **kwargs: object) -> _DummyMetric:
        return _DummyMetric()

    def _histogram(*args: object, **kwargs: object) -> _DummyMetric:
        return _DummyMetric()

    prometheus_module.Counter = _counter
    prometheus_module.Histogram = _histogram
    sys.modules["prometheus_client"] = prometheus_module


def _import_api_middleware(monkeypatch: pytest.MonkeyPatch):
    # Avoid DB SSL bootstrap errors when importing API middleware in isolated unit tests.
    monkeypatch.setenv("DB_SSL_DISABLE", "1")
    monkeypatch.setenv("DATABASE_URL", "postgresql+asyncpg://user:pass@localhost:5432/testdb")

    module = importlib.import_module("backend.apps.api.middleware")
    return importlib.reload(module)


def test_get_rate_limit_key_prefers_explicit_user_id() -> None:
    request = _make_request(state_user_id="state-user", device_id="device-1", ip="10.0.0.5")

    key = get_rate_limit_key(request, user_id="dep-user")

    assert key == "user:dep-user"


def test_get_rate_limit_key_falls_back_to_device_and_ip() -> None:
    request_with_device = _make_request(device_id="device-1", ip="10.0.0.5")
    request_with_ip_only = _make_request(ip="10.0.0.9")

    assert get_rate_limit_key(request_with_device) == "device:device-1"
    assert get_rate_limit_key(request_with_ip_only) == "ip:10.0.0.9"


def test_get_rate_limit_key_can_disable_device_fallback() -> None:
    request_with_device = _make_request(device_id="device-1", ip="10.0.0.5")

    assert get_rate_limit_key(request_with_device, use_device_id=False) == "ip:10.0.0.5"


@pytest.mark.asyncio
async def test_rate_limit_sync_uses_sync_prefix_and_user_scope(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[dict[str, object]] = []

    async def fake_check_or_raise(**kwargs: object) -> None:
        calls.append(kwargs)

    monkeypatch.setattr(
        "backend.infrastructure.rate_limit.token_bucket.check_or_raise", fake_check_or_raise
    )

    request = _make_request(device_id="device-1", ip="10.0.0.5")
    await rate_limit_sync(request, user_id="user-123")

    assert calls == [
        {
            "key": "sync:main:user:user-123",
            "capacity": 30,
            "rate": 0.5,
            "retry_after": 60,
        },
        {
            "key": "sync:burst:user:user-123",
            "capacity": 6,
            "rate": 0.6,
            "retry_after": 10,
        },
    ]


@pytest.mark.asyncio
async def test_rate_limit_default_ignores_device_id_for_key(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[dict[str, object]] = []

    async def fake_check_or_raise(**kwargs: object) -> None:
        calls.append(kwargs)

    monkeypatch.setattr(
        "backend.infrastructure.rate_limit.token_bucket.check_or_raise", fake_check_or_raise
    )

    request = _make_request(device_id="spoofed-device", ip="10.0.0.5", path="/api/v1/tasks")
    await rate_limit_default(request)

    assert calls == [
        {
            "key": "main:ip:10.0.0.5",
            "capacity": 60,
            "rate": 1.0,
            "retry_after": 60,
        },
        {
            "key": "burst:ip:10.0.0.5",
            "capacity": 15,
            "rate": 1.5,
            "retry_after": 10,
        },
    ]


@pytest.mark.asyncio
async def test_rate_limit_sync_fail_open_on_backend_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fake_check_or_raise(**kwargs: object) -> None:
        raise RateLimitBackendUnavailableError("redis down")

    monkeypatch.setattr(
        "backend.infrastructure.rate_limit.token_bucket.check_or_raise", fake_check_or_raise
    )

    request = _make_request(path="/api/v1/sync")
    await rate_limit_sync(request, user_id="user-123")


@pytest.mark.asyncio
async def test_rate_limit_middleware_re_raises_non_backend_errors(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    middleware_module = _import_api_middleware(monkeypatch)
    rate_limit_middleware = middleware_module.rate_limit_middleware

    async def _raise_runtime_error(*args: object, **kwargs: object) -> None:
        raise RuntimeError("unexpected limiter bug")

    monkeypatch.setattr(
        "backend.infrastructure.rate_limit.rate_limit_default", _raise_runtime_error
    )
    monkeypatch.setattr("backend.infrastructure.rate_limit.rate_limit_auth", _raise_runtime_error)

    called_next = False

    async def _call_next(_request: object) -> str:
        nonlocal called_next
        called_next = True
        return "ok"

    request = _make_request(path="/api/v1/tasks")

    with pytest.raises(RuntimeError, match="unexpected limiter bug"):
        await rate_limit_middleware(request, _call_next)

    assert called_next is False


@pytest.mark.asyncio
async def test_rate_limit_middleware_fail_open_on_backend_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    middleware_module = _import_api_middleware(monkeypatch)
    rate_limit_middleware = middleware_module.rate_limit_middleware

    async def _raise_backend_unavailable(*args: object, **kwargs: object) -> None:
        raise RateLimitBackendUnavailableError("redis down")

    monkeypatch.setattr(
        "backend.infrastructure.rate_limit.rate_limit_default",
        _raise_backend_unavailable,
    )
    monkeypatch.setattr(
        "backend.infrastructure.rate_limit.rate_limit_auth",
        _raise_backend_unavailable,
    )

    called_next = False

    async def _call_next(_request: object) -> str:
        nonlocal called_next
        called_next = True
        return "ok"

    request = _make_request(path="/api/v1/tasks")
    response = await rate_limit_middleware(request, _call_next)

    assert response == "ok"
    assert called_next is True


class _FakeMetricCounter:
    def __init__(self) -> None:
        self.labels_kwargs: dict[str, object] | None = None
        self.inc_called = False

    def labels(self, **kwargs: object) -> "_FakeMetricCounter":
        self.labels_kwargs = kwargs
        return self

    def inc(self) -> None:
        self.inc_called = True


class _FakeMetricHistogram:
    def __init__(self) -> None:
        self.labels_kwargs: dict[str, object] | None = None
        self.observed_value: float | None = None

    def labels(self, **kwargs: object) -> "_FakeMetricHistogram":
        self.labels_kwargs = kwargs
        return self

    def observe(self, value: float) -> None:
        self.observed_value = value


@pytest.mark.asyncio
async def test_metrics_middleware_uses_route_template(monkeypatch: pytest.MonkeyPatch) -> None:
    _ensure_prometheus_stub()
    from backend.infrastructure import metrics as metrics_module

    fake_counter = _FakeMetricCounter()
    fake_histogram = _FakeMetricHistogram()
    monkeypatch.setattr(metrics_module, "http_requests_total", fake_counter)
    monkeypatch.setattr(metrics_module, "http_request_duration_seconds", fake_histogram)

    request = SimpleNamespace(
        method="GET",
        scope={"route": SimpleNamespace(path="/api/v1/tasks/{task_id}")},
        url=SimpleNamespace(path="/api/v1/tasks/123"),
    )

    async def _call_next(_request: object) -> SimpleNamespace:
        return SimpleNamespace(status_code=200)

    await metrics_module.metrics_middleware(request, _call_next)

    assert fake_counter.labels_kwargs is not None
    assert fake_counter.labels_kwargs["route"] == "/api/v1/tasks/{task_id}"
    assert fake_histogram.labels_kwargs is not None
    assert fake_histogram.labels_kwargs["route"] == "/api/v1/tasks/{task_id}"


@pytest.mark.asyncio
async def test_metrics_middleware_uses_bounded_route_for_unmatched_requests(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _ensure_prometheus_stub()
    from backend.infrastructure import metrics as metrics_module

    fake_counter = _FakeMetricCounter()
    fake_histogram = _FakeMetricHistogram()
    monkeypatch.setattr(metrics_module, "http_requests_total", fake_counter)
    monkeypatch.setattr(metrics_module, "http_request_duration_seconds", fake_histogram)

    request = SimpleNamespace(
        method="GET",
        scope={},
        url=SimpleNamespace(path="/api/v1/tasks/123"),
    )

    async def _call_next(_request: object) -> SimpleNamespace:
        return SimpleNamespace(status_code=404)

    await metrics_module.metrics_middleware(request, _call_next)

    assert fake_counter.labels_kwargs is not None
    assert fake_counter.labels_kwargs["route"] == "__unmatched__"
    assert fake_histogram.labels_kwargs is not None
    assert fake_histogram.labels_kwargs["route"] == "__unmatched__"


@pytest.mark.asyncio
async def test_get_user_etag_returns_three_component_format() -> None:
    session = DummySession(
        user_row=SimpleNamespace(
            notifications_version=5,
            messages_version=12,
            focus_version=7,
        ),
        global_row=SimpleNamespace(announcements_version=7),
    )

    etag = await get_user_etag(session, uuid.uuid4())

    assert etag == '"5-12-7"'


@pytest.mark.asyncio
async def test_get_user_etag_defaults_to_zero_when_rows_missing() -> None:
    session = DummySession(user_row=None, global_row=None)

    etag = await get_user_etag(session, uuid.uuid4())

    assert etag == '"0-0-0"'


@pytest.mark.asyncio
async def test_get_user_etag_writes_to_cache(monkeypatch: pytest.MonkeyPatch) -> None:
    cache_calls: list[dict[str, object]] = []

    class _FakeCache:
        async def get(self, key: str) -> str | None:
            cache_calls.append({"op": "get", "key": key})
            return None

        async def set(self, key: str, value: str, *, ex: int, nx: bool) -> bool:
            cache_calls.append({"op": "set", "key": key, "value": value, "ex": ex, "nx": nx})
            return True

    monkeypatch.setattr("backend.infrastructure.etag.redis_cache", _FakeCache())

    session = DummySession(
        user_row=SimpleNamespace(
            notifications_version=2,
            messages_version=3,
            focus_version=4,
        ),
        global_row=SimpleNamespace(announcements_version=5),
    )

    etag = await get_user_etag(session, uuid.uuid4())

    assert etag == '"2-3-4"'
    assert [call["op"] for call in cache_calls] == ["get", "set"]
