from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from typing import Any, AsyncGenerator, Dict, List, Optional

import structlog.contextvars
from langchain_core.messages import AIMessage, HumanMessage, SystemMessage, ToolMessage
from langchain_openai import ChatOpenAI

from backend.apps.agent.prompts import build_focus_stats_system_prompt
from backend.apps.agent.tools import ASYNC_TOOL_IMPLS_BY_VARIANT, TOOLS_BY_VARIANT
from backend.infrastructure.config import settings
from backend.infrastructure.logging import get_logger

log = get_logger("agent.llm")

_VARIANTS = {
    "focus_stats": {
        "prompt_builder": build_focus_stats_system_prompt,
        "tools": TOOLS_BY_VARIANT["focus_stats"],
        "async_impls": ASYNC_TOOL_IMPLS_BY_VARIANT["focus_stats"],
    },
}


def _redact_for_logs(text: str, max_len: int = 200) -> str:
    redacted = text
    redacted = re.sub(r"(?i)bearer\s+[a-z0-9\-._~+/]+=*", "Bearer [REDACTED]", redacted)
    redacted = re.sub(
        r"(?i)(access_token|refresh_token|id_token|token)\s*[:=]\s*['\"]?[^'\"\\s]+",
        r"\1=[REDACTED]",
        redacted,
    )
    redacted = re.sub(
        r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",
        "[REDACTED_EMAIL]",
        redacted,
    )
    if len(redacted) > max_len:
        return redacted[:max_len] + "..."
    return redacted


_cached_llm: Dict[str, Any] = {}


def _llm(variant: str = "focus_stats") -> Any:
    variant_cfg = _VARIANTS.get(variant)
    if variant_cfg is None:
        raise ValueError(f"Unknown agent variant: {variant!r}")

    model_name = settings.AGENT_MODEL
    base_url = settings.BASE_URL
    api_key = settings.OPENROUTER_API_KEY
    tools = variant_cfg["tools"]

    cache_key = (variant, model_name, base_url, api_key, len(tools))
    cached = _cached_llm.get(cache_key)
    if cached is not None:
        return cached

    log.info(
        "LLM init model=%s base_url=%s variant=%s tools_count=%s",
        model_name,
        base_url,
        variant,
        len(tools),
    )

    default_headers = {
        "HTTP-Referer": "https://github.com/yourusername/meleo",
        "X-Title": "Meleo Focus Agent",
    }

    model = ChatOpenAI(
        api_key=api_key,
        base_url=base_url,
        model=model_name,
        temperature=0,
        default_headers=default_headers,
        timeout=settings.REQUEST_TIMEOUT_S,
        max_retries=0,
    )

    if tools:
        model_with_tools = model.bind_tools(tools)
    else:
        model_with_tools = model

    _cached_llm[cache_key] = model_with_tools
    return model_with_tools


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _sanitize_args(args: Dict[str, Any]) -> Dict[str, Any]:
    return {k: v for k, v in args.items() if k != "_user_token"}


def _get_tool_calls(ai: Any) -> List[Dict[str, Any]]:
    tool_calls = []

    if hasattr(ai, "tool_calls") and ai.tool_calls:
        for tc in ai.tool_calls:
            tc_dict = tc if isinstance(tc, dict) else getattr(tc, "__dict__", {})
            func_block = (
                tc_dict.get("function") if isinstance(tc_dict.get("function"), dict) else None
            )
            name = (tc_dict.get("name") if isinstance(tc_dict.get("name"), str) else None) or (
                func_block.get("name") if func_block else None
            )
            raw_args = (
                tc_dict.get("args")
                if tc_dict.get("args") is not None
                else (func_block.get("arguments") if func_block else tc_dict.get("arguments"))
            )
            args: Dict[str, Any] = {}
            if isinstance(raw_args, dict):
                args = dict(raw_args)
            elif isinstance(raw_args, str) and raw_args.strip():
                try:
                    parsed = json.loads(raw_args)
                    if isinstance(parsed, dict):
                        args = parsed
                except Exception:
                    pass
            tc_id = (
                tc_dict.get("id")
                or (func_block.get("id") if func_block else None)
                or f"tc_{id(tc)}"
            )
            if name:
                tool_calls.append({"name": name, "args": args, "id": tc_id})
        if tool_calls:
            return tool_calls

    if hasattr(ai, "additional_kwargs"):
        ak = getattr(ai, "additional_kwargs", {}) or {}
        for key in ["tool_calls", "function_call", "tool_use"]:
            if key not in ak:
                continue
            raw_tc = ak[key]
            if isinstance(raw_tc, list):
                for item in raw_tc:
                    if not isinstance(item, dict):
                        continue
                    name = item.get("name") or (
                        item.get("function", {}).get("name")
                        if isinstance(item.get("function"), dict)
                        else None
                    )
                    raw_args = (
                        item.get("arguments")
                        or item.get("args")
                        or (
                            item.get("function", {}).get("arguments")
                            if isinstance(item.get("function"), dict)
                            else None
                        )
                    )
                    args = {}
                    if isinstance(raw_args, dict):
                        args = dict(raw_args)
                    elif isinstance(raw_args, str) and raw_args.strip():
                        try:
                            parsed = json.loads(raw_args)
                            if isinstance(parsed, dict):
                                args = parsed
                        except Exception:
                            pass
                    tc_id = item.get("id") or f"tc_{id(item)}"
                    if name:
                        tool_calls.append({"name": name, "args": args, "id": tc_id})
            elif isinstance(raw_tc, dict):
                name = raw_tc.get("name") or (
                    raw_tc.get("function", {}).get("name")
                    if isinstance(raw_tc.get("function"), dict)
                    else None
                )
                raw_args = (
                    raw_tc.get("arguments")
                    or raw_tc.get("args")
                    or (
                        raw_tc.get("function", {}).get("arguments")
                        if isinstance(raw_tc.get("function"), dict)
                        else None
                    )
                )
                args = {}
                if isinstance(raw_args, dict):
                    args = dict(raw_args)
                elif isinstance(raw_args, str) and raw_args.strip():
                    try:
                        parsed = json.loads(raw_args)
                        if isinstance(parsed, dict):
                            args = parsed
                    except Exception:
                        pass
                tc_id = raw_tc.get("id") or f"tc_{id(raw_tc)}"
                if name:
                    tool_calls.append({"name": name, "args": args, "id": tc_id})
            if tool_calls:
                break

    return tool_calls


def _extract_text_from_ai(ai: Any) -> str:
    try:
        content = getattr(ai, "content", None)
        if isinstance(content, str) and content.strip():
            return content
        ak = getattr(ai, "additional_kwargs", {}) or {}
        cont = ak.get("content")
        if isinstance(cont, str) and cont.strip():
            return cont.strip()
        if isinstance(cont, list):
            parts: List[str] = []
            for item in cont:
                if isinstance(item, dict):
                    text = item.get("text") or item.get("content")
                    if isinstance(text, str) and text.strip():
                        parts.append(text.strip())
            if parts:
                return "\n".join(parts)
        for key in ("reasoning", "reasoning_content"):
            val = ak.get(key)
            if isinstance(val, str) and val.strip():
                return val.strip()
    except Exception:
        pass
    return ""


def _parse_tool_result(result: Any) -> Dict[str, Any]:
    if isinstance(result, dict):
        return result
    if isinstance(result, str) and result.strip():
        try:
            parsed = json.loads(result)
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            pass
    return {}


def _build_tool_trace_entry(
    tool_name: str,
    args: Dict[str, Any],
    started_at: str,
    finished_at: str,
    result_data: Dict[str, Any],
) -> Dict[str, Any]:
    status = result_data.get("status")
    ok = result_data.get("ok")
    if ok is None:
        ok = status != "error"
    error_code = result_data.get("error_code")
    error_msg = None if ok else (result_data.get("error") or result_data.get("message"))
    return {
        "tool_name": tool_name,
        "args": args,
        "started_at": started_at,
        "finished_at": finished_at,
        "ok": bool(ok),
        "error": error_msg,
        "error_code": error_code,
    }


def _build_action_summary(events: List[Dict[str, Any]], tool_calls_count: int) -> str:
    step_events = events[-tool_calls_count:] if len(events) >= tool_calls_count else events
    parts: List[str] = []
    for event in step_events:
        if event.get("type") != "function":
            continue
        tool_name = event.get("name", "unknown")
        result_raw = event.get("result", "")
        try:
            result_data = json.loads(result_raw) if isinstance(result_raw, str) else result_raw
            if isinstance(result_data, dict):
                status = "ok" if result_data.get("status") != "error" else "error"
                parts.append(f"{tool_name}(status={status})")
            else:
                parts.append(f"{tool_name}(status=ok)")
        except Exception:
            parts.append(f"{tool_name}(status=ok)")
    if not parts:
        return ""
    return "ACTION_SUMMARY: " + ", ".join(parts)


def _prepare_chat_messages(
    history: List[Dict[str, str]],
    snapshot: dict,
    variant: str,
) -> tuple[list, str]:
    last_user_message_content = ""
    for msg in reversed(history):
        if msg.get("role") == "user":
            last_user_message_content = msg.get("content", "")
            break

    generated_at_iso = snapshot.get("generated_at", _utc_now_iso())
    snapshot_json_str = json.dumps(snapshot, ensure_ascii=False, indent=2)

    variant_cfg = _VARIANTS[variant]
    prompt_builder = variant_cfg["prompt_builder"]
    system_prompt = prompt_builder(snapshot_json_str, generated_at_iso)

    messages = [SystemMessage(content=system_prompt)]
    for msg in history:
        role = msg.get("role", "")
        content = msg.get("content", "")
        if role == "user":
            messages.append(HumanMessage(content=content))
        elif role == "assistant":
            messages.append(AIMessage(content=content))

    return messages, last_user_message_content


async def _safe_call_async(model: Any, messages: list) -> Any:
    from backend.apps.agent.circuit_breaker import CircuitOpenError, openrouter_breaker

    try:
        log.info("LLM async invoke msg_count=%s", len(messages))
        result = await openrouter_breaker.call_async(model.ainvoke, messages)
        response_content = _extract_text_from_ai(result)
        tool_calls = _get_tool_calls(result)
        log.info(
            "LLM async response: content_len=%s tool_calls_count=%s",
            len(response_content),
            len(tool_calls),
        )
        return result
    except CircuitOpenError:
        raise
    except Exception as e:
        err_text = str(e)
        if "No endpoints found that support tool use" in err_text:
            raise RuntimeError(
                "Configured model does not support tool calling on OpenRouter."
            ) from e
        log.exception("LLM async call error: %s", e)
        raise


async def run_chat_stream(
    history: List[Dict[str, str]],
    *,
    user_token: Optional[str] = None,
    variant: str = "focus_stats",
    snapshot: dict,
    request_id: Optional[str] = None,
) -> AsyncGenerator[Dict[str, Any], None]:
    """Streaming agent loop.

    Yields SSE-compatible dicts:
      {"type": "token", "content": "..."}
      {"type": "tool_start", "name": "...", "args": {...}}
      {"type": "tool_result", "name": "...", "ok": bool}
      {"type": "done", "result": {"events": [...], "tool_trace": [...]}}
      {"type": "error", "message": "..."}
    """

    from backend.apps.agent.circuit_breaker import CircuitOpenError, openrouter_breaker

    context_vars = {"source": "agent"}
    if request_id:
        context_vars["request_id"] = request_id
    structlog.contextvars.bind_contextvars(**context_vars)

    if variant not in _VARIANTS:
        yield {"type": "error", "message": f"Unknown variant: {variant!r}"}
        return

    variant_cfg = _VARIANTS[variant]
    async_impls = variant_cfg["async_impls"]

    messages, last_user_message_content = _prepare_chat_messages(history, snapshot, variant)
    model = _llm(variant)

    log.info(
        "run_chat_stream start variant=%s history=%s messages_count=%s",
        variant,
        len(history),
        len(messages),
    )

    events: List[Dict[str, Any]] = []
    tool_trace: List[Dict[str, Any]] = []

    max_steps = 6
    step = 0

    try:
        while step < max_steps:
            gathered = None
            step_text = ""

            try:
                openrouter_breaker._check_state()
                _stream_error = None
                try:
                    async for chunk in model.astream(messages):
                        gathered = chunk if gathered is None else gathered + chunk
                        chunk_content = ""
                        if hasattr(chunk, "content") and isinstance(chunk.content, str):
                            chunk_content = chunk.content
                        if chunk_content:
                            step_text += chunk_content
                            yield {"type": "token", "content": chunk_content}
                except Exception as _exc:
                    _stream_error = _exc
                    raise
                finally:
                    if _stream_error is not None:
                        openrouter_breaker._on_failure(_stream_error)
                    else:
                        openrouter_breaker._on_success()
            except CircuitOpenError:
                yield {"type": "error", "message": "Service temporarily unavailable (circuit open)"}
                return
            except Exception as e:
                err_text = str(e)
                if "No endpoints found that support tool use" in err_text:
                    yield {"type": "error", "message": "Model does not support tool calling"}
                    return
                log.exception("LLM stream error: %s", e)
                yield {"type": "error", "message": str(e)[:500]}
                return

            if gathered is None:
                yield {"type": "error", "message": "No response from LLM"}
                return

            tool_calls = _get_tool_calls(gathered)
            log.info("stream tool_calls=%s step=%s", len(tool_calls), step + 1)

            if tool_calls:
                messages.append(gathered)
                tool_results_msgs: list = []

                for idx, tc in enumerate(tool_calls):
                    name = tc.get("name")
                    args = tc.get("args", {})
                    tc_id = tc.get("id") or f"tc_{step + 1}_{idx}"

                    if user_token and isinstance(args, dict):
                        args["_user_token"] = user_token

                    async_impl = async_impls.get(name)
                    if not async_impl:
                        log.warning("Unknown stream tool call name=%s; skipping", name)
                        continue

                    trace_args = _sanitize_args(args) if isinstance(args, dict) else {}
                    yield {"type": "tool_start", "name": name, "args": trace_args}

                    started_at = _utc_now_iso()
                    try:
                        result_dict = await async_impl(**args)
                        res = json.dumps(result_dict, ensure_ascii=False)
                        events.append(
                            {
                                "type": "function",
                                "name": name,
                                "arguments": trace_args,
                                "result": res,
                            }
                        )
                        tool_results_msgs.append(
                            ToolMessage(tool_call_id=tc_id, name=name, content=res)
                        )
                        result_data = _parse_tool_result(res)
                    except Exception as e:
                        log.exception("Stream tool execution failed for tool=%s", name)
                        error_msg = str(e)[:200] if str(e) else "Unknown error"
                        error_result = json.dumps({"status": "error", "message": error_msg})
                        events.append(
                            {
                                "type": "function",
                                "name": name,
                                "arguments": trace_args,
                                "result": error_result,
                            }
                        )
                        tool_results_msgs.append(
                            ToolMessage(tool_call_id=tc_id, name=name, content=error_result)
                        )
                        result_data = _parse_tool_result(error_result)

                    finished_at = _utc_now_iso()
                    tool_trace.append(
                        _build_tool_trace_entry(
                            tool_name=name,
                            args=trace_args,
                            started_at=started_at,
                            finished_at=finished_at,
                            result_data=result_data,
                        )
                    )
                    yield {
                        "type": "tool_result",
                        "name": name,
                        "ok": result_data.get("status") != "error",
                    }

                messages.extend(tool_results_msgs)
                action_summary = _build_action_summary(events, len(tool_calls))
                if action_summary:
                    messages.append(SystemMessage(content=action_summary))
                step += 1
                continue

            # No tool calls -> final text response
            content = _extract_text_from_ai(gathered)
            if not content.strip():
                content = "Извините, я не смог сформировать ответ."
                if not step_text:
                    yield {"type": "token", "content": content}

            events.append({"role": "assistant", "content": content})
            log.info("run_chat_stream done events=%s", len(events))
            result = {"events": events, "tool_trace": tool_trace}
            yield {"type": "done", "result": result}
            return

        # Max steps reached
        log.warning("Stream: max tool steps reached without final response")
        fallback = "Извините, не удалось завершить ответ."
        yield {"type": "token", "content": fallback}
        events.append({"role": "assistant", "content": fallback})
        result = {"events": events, "tool_trace": tool_trace}
        yield {"type": "done", "result": result}

    except Exception as e:
        log.exception("run_chat_stream unexpected error: %s", e)
        yield {"type": "error", "message": str(e)[:500]}
