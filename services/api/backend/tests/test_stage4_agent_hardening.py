from __future__ import annotations

import os
import sys
import threading
import types
import uuid
from pathlib import Path

import pytest
from fastapi import HTTPException

from backend.apps.agent.circuit_breaker import CircuitBreaker, CircuitOpenError

# Local test environment may not have redis installed, or another test may
# preload an incomplete redis stub without redis.exceptions.
needs_redis_stub = False
try:
    from redis.asyncio import Redis as _Redis  # noqa: F401
except Exception:
    needs_redis_stub = True

if "redis.exceptions" not in sys.modules:
    needs_redis_stub = True

if needs_redis_stub:
    redis_module = sys.modules.get("redis", types.ModuleType("redis"))
    redis_exceptions_module = sys.modules.get(
        "redis.exceptions",
        types.ModuleType("redis.exceptions"),
    )
    redis_asyncio_module = sys.modules.get(
        "redis.asyncio",
        types.ModuleType("redis.asyncio"),
    )

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
            async def _runner(*args: object, **kwargs: object):
                return "ok"

            return _runner

    class _ResponseError(Exception):
        pass

    redis_asyncio_module.Redis = getattr(redis_asyncio_module, "Redis", _DummyRedis)
    redis_exceptions_module.ResponseError = getattr(
        redis_exceptions_module,
        "ResponseError",
        _ResponseError,
    )
    redis_module.asyncio = redis_asyncio_module
    redis_module.exceptions = redis_exceptions_module
    sys.modules["redis"] = redis_module
    sys.modules["redis.asyncio"] = redis_asyncio_module
    sys.modules["redis.exceptions"] = redis_exceptions_module

_repo_root = Path(__file__).resolve().parents[4]
os.environ.setdefault(
    "PG_SSLROOTCERT", str(_repo_root / "infra" / "certs" / "prod-ca-2021.crt")
)
os.environ.setdefault("DB_SSL_DISABLE", "1")

# Local test environment may not have celery installed.
try:
    import celery  # noqa: F401
except ModuleNotFoundError:
    celery_module = types.ModuleType("celery")
    celery_result_module = types.ModuleType("celery.result")
    celery_signals_module = types.ModuleType("celery.signals")

    class _DummySignal:
        def connect(self, fn=None, **kwargs):
            if fn is not None:
                return fn

            def _decorator(inner_fn):
                return inner_fn

            return _decorator

    class _DummyTask:
        def __init__(self, fn):
            self._fn = fn

        def __call__(self, *args, **kwargs):
            return self._fn(*args, **kwargs)

        def run(self, *args, **kwargs):
            return self._fn(*args, **kwargs)

        def apply_async(self, *args, **kwargs):
            return None

    class _DummyConf(dict):
        def update(self, **kwargs):
            super().update(kwargs)

    class _DummyCelery:
        def __init__(self, *args, **kwargs):
            self.conf = _DummyConf()

        def task(self, *args, **kwargs):
            def _decorator(fn):
                return _DummyTask(fn)

            return _decorator

    class _DummyAsyncResult:
        def __init__(self, *args, **kwargs):
            self.result = None
            self.info = None

        def ready(self) -> bool:
            return False

        def successful(self) -> bool:
            return False

    celery_module.Celery = _DummyCelery
    celery_result_module.AsyncResult = _DummyAsyncResult
    celery_signals_module.task_failure = _DummySignal()
    celery_signals_module.task_revoked = _DummySignal()

    sys.modules["celery"] = celery_module
    sys.modules["celery.result"] = celery_result_module
    sys.modules["celery.signals"] = celery_signals_module


def _get_semaphore_module():
    from backend.infrastructure import agent_semaphore as semaphore_module

    return semaphore_module


@pytest.mark.asyncio
async def test_agent_semaphore_user_limit_returns_429(monkeypatch: pytest.MonkeyPatch) -> None:
    semaphore_module = _get_semaphore_module()
    semaphore = semaphore_module.AgentSemaphore()

    async def _acquire_script(*, keys, args):
        raise semaphore_module.redis.exceptions.ResponseError("user_limit")

    async def _fake_get_scripts():
        return _acquire_script, None

    monkeypatch.setattr(semaphore, "_get_scripts", _fake_get_scripts)

    with pytest.raises(HTTPException) as exc:
        await semaphore.acquire(uuid.uuid4(), "job-user-limit")

    assert exc.value.status_code == 429


@pytest.mark.asyncio
async def test_agent_semaphore_global_limit_returns_503(monkeypatch: pytest.MonkeyPatch) -> None:
    semaphore_module = _get_semaphore_module()
    semaphore = semaphore_module.AgentSemaphore()

    async def _acquire_script(*, keys, args):
        raise semaphore_module.redis.exceptions.ResponseError("global_limit")

    async def _fake_get_scripts():
        return _acquire_script, None

    monkeypatch.setattr(semaphore, "_get_scripts", _fake_get_scripts)

    with pytest.raises(HTTPException) as exc:
        await semaphore.acquire(uuid.uuid4(), "job-global-limit")

    assert exc.value.status_code == 503


def test_circuit_breaker_half_open_allows_single_probe() -> None:
    breaker = CircuitBreaker(failure_threshold=1, recovery_timeout=0.0, name="test")

    with pytest.raises(RuntimeError):
        breaker.call(lambda: (_ for _ in ()).throw(RuntimeError("boom")))

    probe_started = threading.Event()
    probe_release = threading.Event()
    probe_result: list[str] = []
    probe_error: list[Exception] = []

    def _probe() -> str:
        probe_started.set()
        probe_release.wait(timeout=1.0)
        return "ok"

    def _run_probe() -> None:
        try:
            probe_result.append(breaker.call(_probe))
        except Exception as exc:  # pragma: no cover - defensive
            probe_error.append(exc)

    t = threading.Thread(target=_run_probe)
    t.start()
    assert probe_started.wait(timeout=1.0)

    with pytest.raises(CircuitOpenError):
        breaker.call(lambda: "second-probe")

    probe_release.set()
    t.join(timeout=2.0)

    assert probe_error == []
    assert probe_result == ["ok"]
    assert breaker.state == "closed"


def test_circuit_breaker_probe_failure_reopens() -> None:
    breaker = CircuitBreaker(failure_threshold=1, recovery_timeout=0.0, name="test")

    with pytest.raises(RuntimeError):
        breaker.call(lambda: (_ for _ in ()).throw(RuntimeError("boom")))

    assert breaker.state == "open"

    with pytest.raises(RuntimeError):
        breaker.call(lambda: (_ for _ in ()).throw(RuntimeError("probe-failed")))

    assert breaker.state == "open"
