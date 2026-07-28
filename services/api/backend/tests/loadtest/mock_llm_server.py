"""Mock LLM server that mimics OpenRouter/OpenAI streaming chat completions.

Run with:
    python -m backend.tests.loadtest.mock_llm_server

Env vars:
    MOCK_RESPONSE_TOKENS=10      Number of token chunks to emit per response
    MOCK_CHUNK_DELAY_MS=200      Delay between chunks in milliseconds
    MOCK_TOOL_CALL_RATE=0.2      Fraction of requests that include a tool call
    MOCK_PORT=9999               Port to listen on
"""

from __future__ import annotations

import asyncio
import json
import os
import random
import time
import uuid

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse

app = FastAPI(title="Mock LLM Server")

RESPONSE_TOKENS: int = int(os.environ.get("MOCK_RESPONSE_TOKENS", "10"))
CHUNK_DELAY_MS: float = float(os.environ.get("MOCK_CHUNK_DELAY_MS", "200"))
TOOL_CALL_RATE: float = float(os.environ.get("MOCK_TOOL_CALL_RATE", "0.2"))

_SAMPLE_WORDS = [
    "Here",
    "are",
    "your",
    "tasks",
    "for",
    "today",
    "You",
    "have",
    "several",
    "items",
    "pending",
    "review",
    "Let",
    "me",
    "show",
    "them",
    "to",
    "you",
    "now",
    "done",
]


def _make_chunk(completion_id: str, created: int, delta: dict, finish_reason: str | None) -> str:
    payload = {
        "id": completion_id,
        "object": "chat.completion.chunk",
        "created": created,
        "model": "mock-model",
        "choices": [
            {
                "index": 0,
                "delta": delta,
                "finish_reason": finish_reason,
            }
        ],
    }
    return f"data: {json.dumps(payload)}\n\n"


async def _stream_text_response(n_tokens: int, delay_s: float):
    completion_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"
    created = int(time.time())

    # role delta first
    yield _make_chunk(completion_id, created, {"role": "assistant", "content": ""}, None)

    for i in range(n_tokens):
        word = _SAMPLE_WORDS[i % len(_SAMPLE_WORDS)]
        content = word if i == 0 else f" {word}"
        yield _make_chunk(completion_id, created, {"content": content}, None)
        await asyncio.sleep(delay_s)

    yield _make_chunk(completion_id, created, {}, "stop")
    yield "data: [DONE]\n\n"


async def _stream_tool_call_response(delay_s: float):
    completion_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"
    created = int(time.time())
    call_id = f"call_{uuid.uuid4().hex[:8]}"

    yield _make_chunk(completion_id, created, {"role": "assistant", "content": None}, None)

    # First tool_calls chunk: name + id
    yield _make_chunk(
        completion_id,
        created,
        {
            "tool_calls": [
                {
                    "index": 0,
                    "id": call_id,
                    "type": "function",
                    "function": {"name": "list_tasks", "arguments": ""},
                }
            ]
        },
        None,
    )
    await asyncio.sleep(delay_s)

    # Arguments chunk
    yield _make_chunk(
        completion_id,
        created,
        {
            "tool_calls": [
                {
                    "index": 0,
                    "function": {"arguments": '{"limit": 10}'},
                }
            ]
        },
        None,
    )
    await asyncio.sleep(delay_s)

    yield _make_chunk(completion_id, created, {}, "tool_calls")
    yield "data: [DONE]\n\n"


async def _generate(use_tool: bool, n_tokens: int, delay_s: float):
    if use_tool:
        async for chunk in _stream_tool_call_response(delay_s):
            yield chunk
    else:
        async for chunk in _stream_text_response(n_tokens, delay_s):
            yield chunk


async def _handle_completions(request: Request) -> StreamingResponse:
    body = await request.json()

    stream: bool = body.get("stream", False)
    n_tokens = random.randint(max(1, RESPONSE_TOKENS - 5), RESPONSE_TOKENS + 5)
    delay_s = CHUNK_DELAY_MS / 1000.0
    use_tool = random.random() < TOOL_CALL_RATE

    if not stream:
        # Non-streaming fallback (not typically used by the agent, but handle gracefully)
        words = [_SAMPLE_WORDS[i % len(_SAMPLE_WORDS)] for i in range(n_tokens)]
        content = " ".join(words)
        return {  # type: ignore[return-value]
            "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": "mock-model",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": content},
                    "finish_reason": "stop",
                }
            ],
            "usage": {
                "prompt_tokens": 10,
                "completion_tokens": n_tokens,
                "total_tokens": 10 + n_tokens,
            },
        }

    return StreamingResponse(
        _generate(use_tool, n_tokens, delay_s),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.post("/chat/completions")
async def completions_no_prefix(request: Request):
    return await _handle_completions(request)


@app.post("/v1/chat/completions")
async def completions_v1(request: Request):
    return await _handle_completions(request)


@app.get("/health")
async def health():
    return {"status": "ok", "server": "mock-llm"}


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("MOCK_PORT", "9999"))
    uvicorn.run(app, host="0.0.0.0", port=port)
