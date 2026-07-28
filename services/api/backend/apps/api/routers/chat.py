from __future__ import annotations

import uuid
from typing import List, Optional
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.chat.entities import ChatRole
from backend.domain.chat.service import ChatService
from backend.infrastructure.database.session import get_session
from backend.infrastructure.repositories.chat_repository import SQLAlchemyChatRepository
from backend.infrastructure.security.auth import get_current_user_id
from backend.infrastructure.logging import get_logger, should_log_success


router = APIRouter(prefix="/api/v1/chat", tags=["chat"])
log = get_logger("chat")


class ThreadCreate(BaseModel):
    title: str
    metadata: Optional[str] = None


class ThreadOut(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    title: str
    metadata: Optional[str] = Field(default=None, alias="metadata_")
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        populate_by_name = True


class PaginatedThreads(BaseModel):
    total: int | None
    items: List[ThreadOut]


class MessageCreate(BaseModel):
    role: ChatRole
    content: str
    metadata: Optional[str] = None


class MessageOut(BaseModel):
    id: uuid.UUID
    thread_id: uuid.UUID
    role: ChatRole
    content: str
    metadata: Optional[str] = Field(default=None, alias="metadata_")
    order: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        populate_by_name = True


class PaginatedMessages(BaseModel):
    total: int | None
    items: List[MessageOut]


def get_chat_service(
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> ChatService:
    repo = SQLAlchemyChatRepository(session, current_user_id)
    return ChatService(repo)


@router.post("/threads", response_model=ThreadOut, status_code=status.HTTP_201_CREATED)
async def create_thread(
    payload: ThreadCreate,
    current_user_id: uuid.UUID = Depends(get_current_user_id),
    service: ChatService = Depends(get_chat_service),
) -> ThreadOut:
    thread = await service.create_thread(current_user_id, payload.title, payload.metadata)
    if should_log_success():
        log.info(
            "create_thread_sampled",
            extra={"thread_id": str(thread.id), "user_id": str(current_user_id)},
        )
    return ThreadOut.model_validate(thread)


@router.get("/threads", response_model=PaginatedThreads)
async def list_threads(
    limit: int = 20,
    offset: int = 0,
    current_user_id: uuid.UUID = Depends(get_current_user_id),
    service: ChatService = Depends(get_chat_service),
) -> PaginatedThreads:
    total, threads = await service.list_user_threads(current_user_id, limit=limit, offset=offset)
    if should_log_success():
        log.info("list_threads_sampled", extra={"total": total, "user_id": str(current_user_id)})
    return PaginatedThreads(total=total, items=[ThreadOut.model_validate(t) for t in threads])


@router.get("/threads/{thread_id}", response_model=ThreadOut)
async def get_thread(
    thread_id: uuid.UUID,
    current_user_id: uuid.UUID = Depends(get_current_user_id),
    service: ChatService = Depends(get_chat_service),
) -> ThreadOut:
    thread = await service.get_thread(thread_id)
    if not thread:
        log.warning("thread_not_found", extra={"thread_id": str(thread_id)})
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    if thread.user_id != current_user_id:
        log.warning(
            "forbidden_thread_access",
            extra={
                "thread_id": str(thread_id),
                "owner": str(thread.user_id),
                "user": str(current_user_id),
            },
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")
    return ThreadOut.model_validate(thread)


@router.delete("/threads/{thread_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_thread(
    thread_id: uuid.UUID,
    current_user_id: uuid.UUID = Depends(get_current_user_id),
    service: ChatService = Depends(get_chat_service),
) -> None:
    thread = await service.get_thread(thread_id)
    if not thread:
        log.info("delete_thread no-op", extra={"thread_id": str(thread_id)})
        return None
    if thread.user_id != current_user_id:
        log.warning(
            "delete_thread forbidden",
            extra={
                "thread_id": str(thread_id),
                "owner": str(thread.user_id),
                "user": str(current_user_id),
            },
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")
    await service.delete_thread(thread_id)
    return None


@router.post(
    "/threads/{thread_id}/messages", response_model=MessageOut, status_code=status.HTTP_201_CREATED
)
async def add_message(
    thread_id: uuid.UUID,
    payload: MessageCreate,
    current_user_id: uuid.UUID = Depends(get_current_user_id),
    service: ChatService = Depends(get_chat_service),
) -> MessageOut:
    thread = await service.get_thread(thread_id)
    if not thread:
        log.warning("add_message thread_not_found", extra={"thread_id": str(thread_id)})
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    if thread.user_id != current_user_id:
        log.warning(
            "add_message forbidden",
            extra={
                "thread_id": str(thread_id),
                "owner": str(thread.user_id),
                "user": str(current_user_id),
            },
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")
    message = await service.add_message(thread_id, payload.role, payload.content, payload.metadata)
    if should_log_success():
        log.info(
            "add_message_sampled",
            extra={"message_id": str(message.id), "thread_id": str(thread_id)},
        )
    return MessageOut.model_validate(message)


@router.get("/threads/{thread_id}/messages", response_model=PaginatedMessages)
async def list_messages(
    thread_id: uuid.UUID,
    limit: int = 50,
    offset: int = 0,
    current_user_id: uuid.UUID = Depends(get_current_user_id),
    service: ChatService = Depends(get_chat_service),
) -> PaginatedMessages:
    thread = await service.get_thread(thread_id)
    if not thread:
        log.warning("list_messages thread_not_found", extra={"thread_id": str(thread_id)})
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    if thread.user_id != current_user_id:
        log.warning(
            "list_messages forbidden",
            extra={
                "thread_id": str(thread_id),
                "owner": str(thread.user_id),
                "user": str(current_user_id),
            },
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")
    total, messages = await service.get_thread_messages(thread_id, limit=limit, offset=offset)
    if should_log_success():
        log.info("list_messages_sampled", extra={"total": total, "thread_id": str(thread_id)})
    return PaginatedMessages(total=total, items=[MessageOut.model_validate(m) for m in messages])
