"""Async load test for the AI chat SSE streaming endpoint.

Usage:
    python -m backend.tests.loadtest.load_test --token YOUR_JWT_TOKEN [options]

Options:
    --token         JWT auth token (or set LOADTEST_TOKEN env var)
    --base-url      Backend base URL (default: http://localhost:8001)
    --tiers         Comma-separated concurrency levels (default: 5,20,50,100,200)
    --requests-per-tier
                    Override total requests per tier (default: same as concurrency)

Requires:
    pip install aiohttp
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import statistics
import sys
import time
import uuid
from dataclasses import dataclass, field
from typing import Optional

try:
    import aiohttp
except ImportError:
    print("ERROR: aiohttp is required. Install it with: pip install aiohttp")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class RequestResult:
    status: int
    ttft_ms: Optional[float]  # time to first token
    total_ms: float
    events_received: int
    error: Optional[str] = None

    @property
    def success(self) -> bool:
        return self.status == 200 and self.error is None


@dataclass
class TierSummary:
    concurrency: int
    total_requests: int
    results: list[RequestResult] = field(default_factory=list)

    @property
    def successes(self) -> list[RequestResult]:
        return [r for r in self.results if r.success]

    @property
    def success_rate(self) -> float:
        if not self.results:
            return 0.0
        return len(self.successes) / len(self.results) * 100

    def _percentile(self, values: list[float], p: float) -> float:
        if not values:
            return 0.0
        sorted_vals = sorted(values)
        idx = max(0, int(len(sorted_vals) * p / 100) - 1)
        return sorted_vals[idx]

    def ttft_stats(self) -> dict[str, float]:
        values = [r.ttft_ms for r in self.successes if r.ttft_ms is not None]
        if not values:
            return {"avg": 0, "p50": 0, "p95": 0, "p99": 0}
        return {
            "avg": statistics.mean(values),
            "p50": self._percentile(values, 50),
            "p95": self._percentile(values, 95),
            "p99": self._percentile(values, 99),
        }

    def duration_stats(self) -> dict[str, float]:
        values = [r.total_ms for r in self.successes]
        if not values:
            return {"avg": 0, "p50": 0, "p95": 0, "p99": 0}
        return {
            "avg": statistics.mean(values),
            "p50": self._percentile(values, 50),
            "p95": self._percentile(values, 95),
            "p99": self._percentile(values, 99),
        }

    def error_breakdown(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for r in self.results:
            if not r.success:
                key = r.error or f"HTTP {r.status}"
                counts[key] = counts.get(key, 0) + 1
        return counts


# ---------------------------------------------------------------------------
# SSE parsing
# ---------------------------------------------------------------------------


def _parse_sse_line(line: str) -> Optional[dict]:
    """Parse a single SSE data line into a dict, or None if not a data line."""
    if line.startswith("data: "):
        raw = line[6:].strip()
        if raw and raw != "[DONE]":
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                pass
    return None


# ---------------------------------------------------------------------------
# Single request
# ---------------------------------------------------------------------------


async def _run_single_request(
    session: aiohttp.ClientSession,
    url: str,
    token: str,
) -> RequestResult:
    request_id = str(uuid.uuid4())
    payload = {
        "request_id": request_id,
        "history": [{"role": "user", "content": "What can you help me with?"}],
    }
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
    }

    start = time.monotonic()
    ttft_ms: Optional[float] = None
    events_received = 0
    status = 0
    error: Optional[str] = None

    try:
        async with session.post(url, json=payload, headers=headers) as resp:
            status = resp.status
            if status != 200:
                body = await resp.text()
                error = f"HTTP {status}: {body[:200]}"
                total_ms = (time.monotonic() - start) * 1000
                return RequestResult(
                    status=status,
                    ttft_ms=None,
                    total_ms=total_ms,
                    events_received=0,
                    error=error,
                )

            async for raw_line in resp.content:
                line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
                if not line:
                    continue

                event = _parse_sse_line(line)
                if event is not None:
                    events_received += 1
                    if ttft_ms is None and event.get("type") == "token":
                        ttft_ms = (time.monotonic() - start) * 1000
                    if event.get("type") == "error":
                        error = event.get("message", "unknown agent error")

    except asyncio.CancelledError:
        raise
    except aiohttp.ClientConnectorError as exc:
        error = f"connection_error: {exc}"
        status = 0
    except aiohttp.ServerDisconnectedError:
        error = "server_disconnected"
        status = 0
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"
        status = 0

    total_ms = (time.monotonic() - start) * 1000
    return RequestResult(
        status=status,
        ttft_ms=ttft_ms,
        total_ms=total_ms,
        events_received=events_received,
        error=error,
    )


# ---------------------------------------------------------------------------
# Tier runner
# ---------------------------------------------------------------------------


async def _run_tier(
    concurrency: int,
    total_requests: int,
    url: str,
    token: str,
) -> TierSummary:
    summary = TierSummary(concurrency=concurrency, total_requests=total_requests)

    connector = aiohttp.TCPConnector(limit=0, limit_per_host=0)
    timeout = aiohttp.ClientTimeout(total=300, connect=10)

    async with aiohttp.ClientSession(connector=connector, timeout=timeout) as session:
        # Send all requests truly concurrently (up to concurrency limit at a time)
        semaphore = asyncio.Semaphore(concurrency)

        async def _bounded(idx: int) -> RequestResult:
            async with semaphore:
                return await _run_single_request(session, url, token)

        async with asyncio.TaskGroup() as tg:
            tasks = [tg.create_task(_bounded(i)) for i in range(total_requests)]

    summary.results = [t.result() for t in tasks]
    return summary


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

_COL = {
    "reset": "\033[0m",
    "bold": "\033[1m",
    "green": "\033[32m",
    "yellow": "\033[33m",
    "red": "\033[31m",
    "cyan": "\033[36m",
}


def _color(text: str, *codes: str) -> str:
    if not sys.stdout.isatty():
        return text
    return "".join(_COL.get(c, "") for c in codes) + text + _COL["reset"]


def _fmt_ms(ms: float) -> str:
    if ms >= 1000:
        return f"{ms / 1000:.2f}s"
    return f"{ms:.0f}ms"


def _print_tier_summary(summary: TierSummary) -> None:
    label = _color(
        f"=== Tier: {summary.concurrency} concurrent ({summary.total_requests} requests) ===",
        "bold",
        "cyan",
    )
    print(f"\n{label}")

    success_count = len(summary.successes)
    rate_color = (
        "green" if summary.success_rate >= 95 else "yellow" if summary.success_rate >= 70 else "red"
    )
    print(
        f"  Success: {_color(f'{success_count}/{summary.total_requests} ({summary.success_rate:.1f}%)', rate_color)}"
    )

    ttft = summary.ttft_stats()
    dur = summary.duration_stats()

    print(f"  {'Metric':<20} {'avg':>8} {'p50':>8} {'p95':>8} {'p99':>8}")
    print(f"  {'-' * 52}")
    print(
        f"  {'TTFT':<20} {_fmt_ms(ttft['avg']):>8} {_fmt_ms(ttft['p50']):>8}"
        f" {_fmt_ms(ttft['p95']):>8} {_fmt_ms(ttft['p99']):>8}"
    )
    print(
        f"  {'Total duration':<20} {_fmt_ms(dur['avg']):>8} {_fmt_ms(dur['p50']):>8}"
        f" {_fmt_ms(dur['p95']):>8} {_fmt_ms(dur['p99']):>8}"
    )

    errors = summary.error_breakdown()
    if errors:
        print("  Errors:")
        for err, count in sorted(errors.items(), key=lambda x: -x[1]):
            print(f"    {_color(err, 'red')}: {count}")


def _print_final_summary(summaries: list[TierSummary]) -> None:
    print("\n" + _color("=" * 70, "bold"))
    print(_color("FINAL SUMMARY", "bold", "cyan"))
    print(_color("=" * 70, "bold"))
    header = f"  {'Tier':>6}  {'Req':>5}  {'Success%':>9}  {'TTFT avg':>9}  {'TTFT p95':>9}  {'Dur avg':>8}  {'Dur p95':>8}"
    print(header)
    print(f"  {'-' * 68}")
    for s in summaries:
        ttft = s.ttft_stats()
        dur = s.duration_stats()
        rate_color = (
            "green" if s.success_rate >= 95 else "yellow" if s.success_rate >= 70 else "red"
        )
        row = (
            f"  {s.concurrency:>6}  {s.total_requests:>5}  "
            f"{_color(f'{s.success_rate:.1f}%', rate_color):>9}  "
            f"{_fmt_ms(ttft['avg']):>9}  {_fmt_ms(ttft['p95']):>9}  "
            f"{_fmt_ms(dur['avg']):>8}  {_fmt_ms(dur['p95']):>8}"
        )
        print(row)
    print()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="FocusFlow chat SSE load test")
    parser.add_argument(
        "--token",
        default=os.environ.get("LOADTEST_TOKEN", ""),
        help="JWT auth token (or set LOADTEST_TOKEN env var)",
    )
    parser.add_argument(
        "--base-url",
        default="http://localhost:8001",
        help="Backend base URL (default: http://localhost:8001)",
    )
    parser.add_argument(
        "--tiers",
        default="5,20,50,100,200",
        help="Comma-separated concurrency levels (default: 5,20,50,100,200)",
    )
    parser.add_argument(
        "--requests-per-tier",
        type=int,
        default=None,
        help="Override total requests per tier (default: same as concurrency level)",
    )
    return parser.parse_args()


async def _main() -> None:
    args = _parse_args()

    if not args.token:
        print("ERROR: --token is required (or set LOADTEST_TOKEN env var)")
        sys.exit(1)

    tiers = [int(t.strip()) for t in args.tiers.split(",") if t.strip()]
    url = args.base_url.rstrip("/") + "/api/v1/agent/chat.stream"

    print(_color("FocusFlow Chat SSE Load Test", "bold"))
    print(f"  Target: {url}")
    print(f"  Tiers:  {tiers}")
    if args.requests_per_tier:
        print(f"  Requests per tier: {args.requests_per_tier} (overridden)")
    print()

    tier_names = {5: "Warm-up", 20: "Light", 50: "Medium", 100: "Heavy", 200: "Stress"}
    summaries: list[TierSummary] = []

    for concurrency in tiers:
        total = args.requests_per_tier if args.requests_per_tier is not None else concurrency
        name = tier_names.get(concurrency, f"{concurrency}-concurrent")
        print(_color(f"Running {name} tier ({concurrency} concurrent, {total} total)...", "yellow"))

        summary = await _run_tier(concurrency, total, url, args.token)
        summaries.append(summary)
        _print_tier_summary(summary)

        # Brief pause between tiers to let the server settle
        if tiers.index(concurrency) < len(tiers) - 1:
            await asyncio.sleep(2)

    _print_final_summary(summaries)


def main() -> None:
    asyncio.run(_main())


if __name__ == "__main__":
    main()
