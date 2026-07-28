from __future__ import annotations

from typing import Any

import httpx


def assert_tool_called(result: dict[str, Any], tool_name: str) -> tuple[bool, str]:
    tool_trace: list[dict[str, Any]] = result.get("tool_trace") or []
    events: list[dict[str, Any]] = result.get("events") or []
    for entry in tool_trace:
        if entry.get("tool_name") == tool_name or entry.get("name") == tool_name:
            return True, f"Tool '{tool_name}' found in tool_trace"
    for event in events:
        if event.get("name") == tool_name and event.get("type") == "function":
            return True, f"Tool '{tool_name}' found in events"
    return False, f"Tool '{tool_name}' not found in tool_trace or events"


def assert_no_errors(result: dict[str, Any]) -> tuple[bool, str]:
    errors: list[dict[str, Any]] = result.get("errors") or []
    if not errors:
        return True, "No errors"
    details = "; ".join(f"{e.get('tool_name', '?')}: {e.get('error', '?')}" for e in errors)
    return False, f"Errors present: {details}"


def assert_has_widget(result: dict[str, Any], widget_type: str) -> tuple[bool, str]:
    widgets: list[dict[str, Any]] = result.get("widgets") or []
    for widget in widgets:
        if widget.get("type") == widget_type:
            return True, f"Widget type '{widget_type}' found"
    return False, f"Widget type '{widget_type}' not found in widgets"


def assert_touched_entity(
    result: dict[str, Any],
    entity_type: str,
    action: str | None = None,
) -> tuple[bool, str]:
    touched: list[dict[str, Any]] = result.get("touched_entities") or []
    for entity in touched:
        if entity.get("entity_type") == entity_type:
            if action is None:
                return True, f"Entity type '{entity_type}' found in touched_entities"
            if entity.get("action") == action:
                return (
                    True,
                    f"Entity type '{entity_type}' with action '{action}' found",
                )
    if action is not None:
        return (
            False,
            f"Entity type '{entity_type}' with action '{action}' not found in touched_entities",
        )
    return False, f"Entity type '{entity_type}' not found in touched_entities"


def assert_status(result: dict[str, Any], expected_status: str) -> tuple[bool, str]:
    actual = result.get("status")
    if actual == expected_status:
        return True, f"Status is '{expected_status}'"
    return False, f"Expected status '{expected_status}', got '{actual}'"


def assert_http_error(response: httpx.Response, expected_code: int) -> tuple[bool, str]:
    if response.status_code == expected_code:
        return True, f"HTTP {expected_code} as expected"
    return False, f"Expected HTTP {expected_code}, got {response.status_code}"


def assert_response_text_contains(result: dict[str, Any], substring: str) -> tuple[bool, str]:
    events: list[dict[str, Any]] = result.get("events") or []
    for event in events:
        if event.get("role") == "assistant":
            content = event.get("content", "")
            if substring.lower() in content.lower():
                return True, f"Assistant message contains '{substring}'"
    return False, f"No assistant message contains '{substring}'"


def assert_tool_count(
    result: dict[str, Any], tool_name: str, expected_count: int
) -> tuple[bool, str]:
    tool_trace: list[dict[str, Any]] = result.get("tool_trace") or []
    events: list[dict[str, Any]] = result.get("events") or []
    # Prefer tool_trace; fall back to events only if tool_trace is empty
    if tool_trace:
        count = sum(
            1
            for entry in tool_trace
            if entry.get("tool_name") == tool_name or entry.get("name") == tool_name
        )
    else:
        count = sum(
            1
            for event in events
            if event.get("name") == tool_name and event.get("type") == "function"
        )
    if count == expected_count:
        return True, f"Tool '{tool_name}' called {expected_count} time(s)"
    return False, f"Tool '{tool_name}': expected {expected_count} call(s), got {count}"
