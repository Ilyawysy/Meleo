from __future__ import annotations

import json
import re

import httpx

from backend.infrastructure.config import settings
from backend.infrastructure.logging import get_logger

log = get_logger("agent.help.llm")


class HelpLLMError(Exception):
    pass


def _redact(text: str, max_len: int = 200) -> str:
    redacted = re.sub(r"(?i)bearer\s+[a-z0-9\-._~+/]+=*", "Bearer [REDACTED]", text)
    if len(redacted) > max_len:
        return redacted[:max_len] + "..."
    return redacted


async def call_help_llm(
    system_prompt: str,
    user_message: str,
    *,
    timeout_s: float = 20.0,
) -> dict:
    model = settings.HELP_AGENT_MODEL or settings.AGENT_MODEL
    base_url = settings.BASE_URL
    api_key = settings.OPENROUTER_API_KEY

    if not model or not base_url or not api_key:
        raise HelpLLMError(
            "LLM not configured: missing AGENT_MODEL, BASE_URL or OPENROUTER_API_KEY"
        )

    url = f"{base_url.rstrip('/')}/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
        "response_format": {"type": "json_object"},
    }

    log.info(
        "help_llm_call model=%s user_msg_len=%s",
        model,
        len(user_message),
    )

    last_error: Exception | None = None
    for attempt in range(2):
        if attempt == 1:
            payload["messages"][-1]["content"] = user_message + "\n\nReply with valid JSON only."

        try:
            async with httpx.AsyncClient(timeout=timeout_s) as client:
                resp = await client.post(url, headers=headers, json=payload)

            if resp.status_code >= 500:
                raise HelpLLMError(f"LLM API server error: {resp.status_code}")

            resp.raise_for_status()
            data = resp.json()
            content = data["choices"][0]["message"]["content"]

            log.info(
                "help_llm_response content_len=%s",
                len(content) if content else 0,
            )

            result = json.loads(content)
            if not isinstance(result, dict):
                raise ValueError("LLM returned non-dict JSON")
            return result

        except (json.JSONDecodeError, ValueError, KeyError) as e:
            last_error = e
            log.info(
                "help_llm_parse_error attempt=%s error=%s",
                attempt + 1,
                _redact(str(e)),
            )
            continue
        except HelpLLMError:
            raise
        except Exception as e:
            raise HelpLLMError(f"LLM call failed: {_redact(str(e))}") from e

    raise HelpLLMError(f"LLM returned invalid JSON after retries: {last_error}")
