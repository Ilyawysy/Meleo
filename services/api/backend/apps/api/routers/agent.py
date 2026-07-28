from __future__ import annotations

import asyncio
import json
import uuid
from typing import List, Literal, Optional

import structlog.contextvars
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.responses import StreamingResponse

from backend.infrastructure.agent_semaphore import semaphore
from backend.infrastructure.config import settings
from backend.infrastructure.database.session import get_session
from backend.infrastructure.logging import get_logger
from backend.infrastructure.rate_limit import rate_limit_agent
from backend.infrastructure.security.auth import get_current_user_id

router = APIRouter(prefix="/api/v1/agent", tags=["agent"])
log = get_logger("agent.api")


class Msg(BaseModel):
    role: Literal["user", "assistant"]
    content: str
    id: Optional[str] = None


MAX_HISTORY_MESSAGES = 50


class ChatRequest(BaseModel):
    session_id: Optional[str] = None
    user_id: Optional[str] = None
    request_id: Optional[str] = None
    history: List[Msg] = Field(default_factory=list)
    user_token: Optional[str] = None
    variant: Literal["focus_stats"] = "focus_stats"


def _extract_bearer_token(authorization: Optional[str], payload_token: Optional[str]) -> str:
    token: Optional[str] = None
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()

    if not token:
        raise HTTPException(401, "User token required for agent")

    if payload_token and payload_token.strip() != token:
        raise HTTPException(403, "Body token mismatch")

    return token


def _prepare_history(payload: ChatRequest) -> list[dict[str, str]]:
    msgs = (
        payload.history[-MAX_HISTORY_MESSAGES:]
        if len(payload.history) > MAX_HISTORY_MESSAGES
        else payload.history
    )
    return [m.model_dump(include={"role", "content"}) for m in msgs]


ASYNC_CHAT_TIMEOUT_S = 240


@router.post("/chat.stream")
async def chat_stream(
    request: Request,
    payload: ChatRequest,
    current_user_id: uuid.UUID = Depends(get_current_user_id),
    authorization: Optional[str] = Header(None),
    session: AsyncSession = Depends(get_session),
):
    """Run agent chat with SSE streaming.

    Returns Server-Sent Events:
      data: {"type": "token", "content": "..."}
      data: {"type": "tool_start", "name": "...", "args": {...}}
      data: {"type": "tool_result", "name": "...", "ok": true}
      data: {"type": "done", "result": {...}}
      data: {"type": "error", "message": "..."}
    """
    structlog.contextvars.bind_contextvars(source="agent")

    if not (settings.LOADTEST_MODE and settings.ENV == "dev"):
        await rate_limit_agent(request, current_user_id=str(current_user_id))

    user_token = _extract_bearer_token(authorization, payload.user_token)
    history = _prepare_history(payload)
    request_id = payload.request_id or str(uuid.uuid4())
    job_id = str(uuid.uuid4())

    _loadtest = settings.LOADTEST_MODE and settings.ENV == "dev"
    if not _loadtest:
        await semaphore.acquire(current_user_id, job_id)

    from backend.apps.agent.focus_snapshot import build_focus_snapshot

    snapshot = await build_focus_snapshot(session, current_user_id)

    log.info(
        "agent_stream_started",
        job_id=job_id,
        request_id=request_id,
        user_id=str(current_user_id),
        variant=payload.variant,
    )

    async def event_generator():
        from backend.apps.agent.llm import run_chat_stream

        async def _with_heartbeat(stream):
            HEARTBEAT_INTERVAL = 15
            queue: asyncio.Queue = asyncio.Queue()

            async def _send_heartbeat(q: asyncio.Queue):
                while True:
                    await asyncio.sleep(HEARTBEAT_INTERVAL)
                    await q.put(": heartbeat\n\n")

            async def _consume_stream():
                try:
                    async for event in stream:
                        await queue.put(f"data: {json.dumps(event, ensure_ascii=False)}\n\n")
                finally:
                    await queue.put(None)

            consumer = asyncio.create_task(_consume_stream())
            heartbeat_task = asyncio.create_task(_send_heartbeat(queue))
            try:
                while True:
                    item = await queue.get()
                    if item is None:
                        break
                    yield item
            finally:
                heartbeat_task.cancel()
                if not consumer.done():
                    consumer.cancel()
                for t in (heartbeat_task, consumer):
                    try:
                        await t
                    except (asyncio.CancelledError, Exception):
                        pass

        try:
            async with asyncio.timeout(ASYNC_CHAT_TIMEOUT_S):
                async for chunk in _with_heartbeat(
                    run_chat_stream(
                        history,
                        user_token=user_token,
                        variant=payload.variant,
                        snapshot=snapshot,
                        request_id=request_id,
                    )
                ):
                    yield chunk
        except asyncio.CancelledError:
            log.info("agent_stream_cancelled", job_id=job_id)
        except TimeoutError:
            log.warning("agent_stream_timeout", job_id=job_id, timeout_s=ASYNC_CHAT_TIMEOUT_S)
            error_event = {"type": "error", "message": "Response timeout exceeded"}
            yield f"data: {json.dumps(error_event, ensure_ascii=False)}\n\n"
        except Exception as e:
            log.exception("agent_stream_error", job_id=job_id, error=str(e))
            error_event = {"type": "error", "message": str(e)[:500]}
            yield f"data: {json.dumps(error_event, ensure_ascii=False)}\n\n"
        finally:
            if not _loadtest:
                await semaphore.release(job_id, keep_owner_mapping=False)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
