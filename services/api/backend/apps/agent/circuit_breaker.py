from __future__ import annotations

import threading
import time

from backend.infrastructure.logging import get_logger

logger = get_logger("agent.circuit_breaker")


class CircuitBreaker:
    """Simple circuit breaker for OpenRouter API calls.

    States:
    - closed: requests pass through normally
    - open: requests are rejected immediately
    - half-open: one probe request is allowed to test recovery

    Thread-safe via a lock (Celery workers run in threads).
    """

    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 60.0,
        name: str = "openrouter",
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.name = name

        self._lock = threading.Lock()
        self._failures = 0
        self._last_failure_time: float = 0.0
        self._state = "closed"
        self._half_open_probe_in_flight = False

    @property
    def state(self) -> str:
        with self._lock:
            return self._state

    def _enter(self) -> bool:
        """Shared gate logic for call / call_async / _check_state.

        Transitions open → half-open when recovery_timeout has elapsed, and
        rejects requests while the circuit is open or a half-open probe is
        already in flight.

        Returns True if the caller is the half-open probe (and therefore must
        call _on_success / _on_failure when done).
        """
        with self._lock:
            if self._state == "open":
                elapsed = time.monotonic() - self._last_failure_time
                if elapsed >= self.recovery_timeout:
                    self._state = "half-open"
                    logger.info(
                        "circuit_half_open",
                        name=self.name,
                        elapsed=round(elapsed, 1),
                    )
                else:
                    logger.warning(
                        "circuit_open_rejected",
                        name=self.name,
                        retry_in=round(self.recovery_timeout - elapsed, 1),
                    )
                    raise CircuitOpenError(
                        f"Circuit breaker '{self.name}' is open, "
                        f"retry in {round(self.recovery_timeout - elapsed)}s"
                    )

            if self._state == "half-open":
                if self._half_open_probe_in_flight:
                    logger.warning(
                        "circuit_half_open_probe_rejected",
                        name=self.name,
                    )
                    raise CircuitOpenError(
                        f"Circuit breaker '{self.name}' is half-open, "
                        "probe request is already in progress"
                    )
                self._half_open_probe_in_flight = True
                return True

            return False

    def _check_state(self) -> None:
        """Check circuit state and raise CircuitOpenError if requests should be rejected.

        Used by streaming callers that cannot wrap the entire operation in call/call_async
        because the operation returns an async iterator rather than a coroutine.
        """
        self._enter()

    def call(self, func, *args, **kwargs):
        """Execute *func* through the circuit breaker."""
        probe_in_flight = self._enter()
        try:
            result = func(*args, **kwargs)
            self._on_success(probe_in_flight=probe_in_flight)
            return result
        except Exception as exc:
            self._on_failure(exc, probe_in_flight=probe_in_flight)
            raise

    async def call_async(self, func, *args, **kwargs):
        """Async variant of call() for use with async functions."""
        probe_in_flight = self._enter()
        try:
            result = await func(*args, **kwargs)
            self._on_success(probe_in_flight=probe_in_flight)
            return result
        except Exception as exc:
            self._on_failure(exc, probe_in_flight=probe_in_flight)
            raise

    def _on_success(self, *, probe_in_flight: bool = False) -> None:
        with self._lock:
            prev = self._state
            self._failures = 0
            self._state = "closed"
            if probe_in_flight:
                self._half_open_probe_in_flight = False
            if prev != "closed":
                logger.info("circuit_closed", name=self.name)

    def _on_failure(self, exc: Exception, *, probe_in_flight: bool = False) -> None:
        with self._lock:
            if probe_in_flight:
                self._half_open_probe_in_flight = False

            if self._state == "half-open":
                self._state = "open"
                self._failures = self.failure_threshold
                self._last_failure_time = time.monotonic()
                logger.error(
                    "circuit_reopened_from_half_open",
                    name=self.name,
                    failures=self._failures,
                    error=str(exc)[:200],
                )
                return

            self._failures += 1
            self._last_failure_time = time.monotonic()
            if self._failures >= self.failure_threshold:
                self._state = "open"
                logger.error(
                    "circuit_opened",
                    name=self.name,
                    failures=self._failures,
                    error=str(exc)[:200],
                )


class CircuitOpenError(Exception):
    """Raised when a call is rejected because the circuit breaker is open."""


# Module-level singleton used by llm.py
openrouter_breaker = CircuitBreaker(
    failure_threshold=5,
    recovery_timeout=60.0,
    name="openrouter",
)
