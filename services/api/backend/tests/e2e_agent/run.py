from __future__ import annotations

import argparse
import asyncio
import io
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

# Force UTF-8 stdout on Windows (cp1252 cannot handle Cyrillic)
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# Allow `python -m tests.e2e_agent.run` from backend/
_here = Path(__file__).resolve().parent
_backend_root = _here.parents[1]
if str(_backend_root) not in sys.path:
    sys.path.insert(0, str(_backend_root))

from tests.e2e_agent.client import AgentClient, obtain_token  # noqa: E402
from tests.e2e_agent.scenarios import SCENARIOS, context  # noqa: E402

ANSI_GREEN = "\033[92m"
ANSI_RED = "\033[91m"
ANSI_YELLOW = "\033[93m"
ANSI_RESET = "\033[0m"


def _colored(text: str, color: str) -> str:
    return f"{color}{text}{ANSI_RESET}"


def _print_result(name: str, verdict: str, duration: float, message: str = "") -> None:
    if verdict == "PASS":
        label = _colored("PASS", ANSI_GREEN)
    elif verdict == "FAIL":
        label = _colored("FAIL", ANSI_RED)
    else:
        label = _colored("SKIP", ANSI_YELLOW)
    suffix = f"  {message}" if message else ""
    print(f"  [{label}] {name} ({duration:.1f}s){suffix}")


def _extract_agent_reply(response: dict[str, Any] | None) -> str | None:
    """Extract the assistant's text reply from the job response."""
    if not response:
        return None
    result = response.get("result") or {}
    events = result.get("events") or []
    parts: list[str] = []
    for event in events:
        if event.get("role") == "assistant" and event.get("content"):
            parts.append(event["content"])
    return "\n".join(parts) if parts else None


def _extract_tool_trace(response: dict[str, Any] | None) -> list[str]:
    """Extract tool names called from the job response."""
    if not response:
        return []
    result = response.get("result") or {}
    trace = result.get("tool_trace") or []
    names = [e.get("tool_name") or e.get("name") or "?" for e in trace]
    if not names:
        events = result.get("events") or []
        names = [e["name"] for e in events if e.get("type") == "function" and e.get("name")]
    return names


async def _run_scenario(
    scenario: dict[str, Any],
    client: AgentClient,
    verbose: bool,
    poll_timeout: float,
    poll_interval: float,
    passed_deps: set[str],
) -> dict[str, Any]:
    name: str = scenario["name"]
    depends_on: str | None = scenario.get("depends_on")
    skip_poll: bool = scenario.get("skip_poll", False)
    token_override: str | None = scenario.get("token_override")
    is_rate_limit_probe: bool = scenario.get("_rate_limit_probe", False)

    if depends_on and depends_on not in passed_deps:
        return {
            "name": name,
            "verdict": "SKIP",
            "duration": 0.0,
            "reason": f"depends_on '{depends_on}' did not pass",
        }

    history_factory = scenario.get("history_factory")
    if history_factory is not None:
        history = history_factory()
    else:
        history = scenario.get("history") or []

    mentions = scenario.get("mentions")
    assertions: list[Any] = scenario.get("assertions") or []
    extract = scenario.get("extract")

    start = time.monotonic()
    failures: list[str] = []

    raw_response: dict[str, Any] | None = None

    try:
        if skip_poll:
            if is_rate_limit_probe:
                # Wait for rate limit to reset, then fire two requests back-to-back
                await asyncio.sleep(11)
                await client.raw_submit(history, token_override=token_override)
                response = await client.raw_submit(history, token_override=token_override)
            else:
                response = await client.raw_submit(history, token_override=token_override)

            raw_response = {"http_status": response.status_code}
            for assertion in assertions:
                passed, msg = assertion(response)
                if not passed:
                    failures.append(msg)
        else:
            job_response = await client.run(
                history, mentions, timeout=poll_timeout, interval=poll_interval
            )
            raw_response = job_response

            if extract is not None:
                result_data = job_response.get("result") or {}
                try:
                    extract(result_data)
                except Exception as exc:
                    if verbose:
                        print(f"    extract() error: {exc}")

            for assertion in assertions:
                result_data = job_response.get("result") or {}
                merged = {**result_data, "status": job_response.get("status")}
                passed, msg = assertion(merged)
                if not passed:
                    failures.append(msg)

        duration = time.monotonic() - start

        # Extract assistant reply text and tool_trace for the report
        agent_reply = _extract_agent_reply(raw_response)
        tool_trace = _extract_tool_trace(raw_response)

        entry: dict[str, Any] = {
            "name": name,
            "duration": duration,
            "request": {"history": history},
            "response": raw_response,
            "agent_reply": agent_reply,
            "tool_trace": tool_trace,
        }

        if failures:
            if verbose:
                for f in failures:
                    print(f"    {_colored('x', ANSI_RED)} {f}")
            return {**entry, "verdict": "FAIL", "failures": failures}

        return {**entry, "verdict": "PASS"}

    except Exception as exc:
        duration = time.monotonic() - start
        msg = str(exc)
        if verbose:
            import traceback

            traceback.print_exc()
        return {
            "name": name,
            "verdict": "FAIL",
            "duration": duration,
            "request": {"history": history},
            "failures": [msg],
        }


async def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Meleo agent E2E test runner")
    parser.add_argument("--scenarios", default="", help="Comma-separated scenario names to run")
    parser.add_argument("--verbose", action="store_true", help="Verbose output")
    parser.add_argument("--base-url", default="", help="Base URL override")
    parser.add_argument("--token", default="", help="JWT token override")
    args = parser.parse_args(argv)

    base_url = args.base_url or os.environ.get("E2E_BASE_URL", "http://localhost:8001")
    token = args.token or os.environ.get("E2E_SUPABASE_TOKEN", "")
    poll_timeout = float(os.environ.get("E2E_POLL_TIMEOUT", "120"))
    poll_interval = float(os.environ.get("E2E_POLL_INTERVAL", "2"))

    # Auto-login: if no token but email/password + Supabase creds are set, obtain JWT
    if not token:
        email = os.environ.get("E2E_USER_EMAIL", "")
        password = os.environ.get("E2E_USER_PASSWORD", "")
        supabase_url = os.environ.get("E2E_SUPABASE_URL", os.environ.get("SUPABASE_URL", ""))
        anon_key = os.environ.get("E2E_SUPABASE_ANON_KEY", os.environ.get("SUPABASE_ANON_KEY", ""))

        if email and password and supabase_url and anon_key:
            print("  Logging in via Supabase Auth...")
            try:
                token = await obtain_token(supabase_url, anon_key, email, password)
                print(_colored("  Token obtained successfully", ANSI_GREEN))
            except RuntimeError as exc:
                print(_colored(f"ERROR: auto-login failed: {exc}", ANSI_RED))
                return 1
        else:
            missing = []
            if not email:
                missing.append("E2E_USER_EMAIL")
            if not password:
                missing.append("E2E_USER_PASSWORD")
            if not supabase_url:
                missing.append("E2E_SUPABASE_URL (or SUPABASE_URL)")
            if not anon_key:
                missing.append("E2E_SUPABASE_ANON_KEY (or SUPABASE_ANON_KEY)")
            print(
                _colored(
                    "ERROR: no token. Either set E2E_SUPABASE_TOKEN / --token,\n"
                    "  or provide all of: E2E_USER_EMAIL, E2E_USER_PASSWORD, "
                    "E2E_SUPABASE_URL, E2E_SUPABASE_ANON_KEY.\n"
                    f"  Missing: {', '.join(missing)}",
                    ANSI_RED,
                )
            )
            return 1

    filter_names: set[str] = set()
    if args.scenarios:
        filter_names = {s.strip() for s in args.scenarios.split(",") if s.strip()}

    scenarios = SCENARIOS
    if filter_names:
        scenarios = [s for s in scenarios if s["name"] in filter_names]

    client = AgentClient(base_url=base_url, token=token)

    print(f"\nMeleo Agent E2E — {len(scenarios)} scenario(s)")
    print(f"  Base URL : {base_url}")
    print(f"  Timeout  : {poll_timeout}s  interval: {poll_interval}s\n")

    results: list[dict[str, Any]] = []
    passed_deps: set[str] = set()
    context.clear()

    for scenario in scenarios:
        name = scenario["name"]
        desc = scenario.get("description", "")
        if args.verbose:
            print(f"  Running: {name} — {desc}")

        result = await _run_scenario(
            scenario=scenario,
            client=client,
            verbose=args.verbose,
            poll_timeout=poll_timeout,
            poll_interval=poll_interval,
            passed_deps=passed_deps,
        )
        results.append(result)

        verdict = result["verdict"]
        duration = result.get("duration", 0.0)
        reason = result.get("reason", "")
        failures = result.get("failures", [])
        msg = reason or (failures[0] if failures else "")
        _print_result(name, verdict, duration, msg)

        if verdict == "PASS":
            passed_deps.add(name)

        # Run cleanup if defined and scenario passed
        cleanup_msg: str | None = scenario.get("cleanup")
        if cleanup_msg and verdict == "PASS":
            try:
                await asyncio.sleep(11)  # respect rate limit before cleanup
                await client.run([{"role": "user", "content": cleanup_msg}])
            except Exception:
                pass

        # Respect server rate limit: 1 request per 10s for chat.run
        # Always wait if the next scenario will make a real chat.run request
        next_idx = scenarios.index(scenario) + 1
        if next_idx < len(scenarios):
            next_is_skip = scenarios[next_idx].get("skip_poll", False)
            if not next_is_skip:
                if args.verbose:
                    print("    (waiting 11s for rate limit reset)")
                await asyncio.sleep(11)

    # Summary
    total = len(results)
    passed = sum(1 for r in results if r["verdict"] == "PASS")
    failed = sum(1 for r in results if r["verdict"] == "FAIL")
    skipped = sum(1 for r in results if r["verdict"] == "SKIP")
    total_time = sum(r.get("duration", 0.0) for r in results)

    print(f"\n{'─' * 50}")
    print(
        f"  Total: {total}  "
        f"{_colored(f'PASS: {passed}', ANSI_GREEN)}  "
        f"{_colored(f'FAIL: {failed}', ANSI_RED)}  "
        f"{_colored(f'SKIP: {skipped}', ANSI_YELLOW)}  "
        f"({total_time:.1f}s)"
    )

    # Save JSON report
    reports_dir = _here / "reports"
    reports_dir.mkdir(exist_ok=True)
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    report_path = reports_dir / f"{timestamp}.json"
    report: dict[str, Any] = {
        "timestamp": timestamp,
        "base_url": base_url,
        "total": total,
        "passed": passed,
        "failed": failed,
        "skipped": skipped,
        "total_time": round(total_time, 2),
        "scenarios": results,
    }
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"  Report  : {report_path}\n")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
