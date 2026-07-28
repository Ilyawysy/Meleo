from __future__ import annotations

import uuid
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from backend.apps.agent.help.context import (
    NoActiveRoomError,
    ProfileMissingError,
    build_help_app_context,
)
from backend.apps.agent.help.fallback import FALLBACK_CARD, FALLBACK_QUESTION
from backend.apps.agent.help.llm import HelpLLMError, call_help_llm
from backend.apps.agent.help.prompts import (
    SYSTEM_CARD,
    SYSTEM_QUESTION,
    build_card_user_message,
    build_question_user_message,
)
from backend.apps.agent.help.topics import validate_topic_subtopic
from backend.infrastructure.database.session import get_session
from backend.infrastructure.logging import get_logger
from backend.infrastructure.security.auth import get_current_user_id

router = APIRouter(prefix="/api/v1/help", tags=["help"])
log = get_logger("api.help")


# ── Pydantic models ──


class HelpQuestionIn(BaseModel):
    topic_id: str
    subtopic_id: str


class HelpQuestionOut(BaseModel):
    question: str
    options: list[str]


class HelpCardPrev(BaseModel):
    messages: list[str]
    action_label: str


class HelpCardIn(BaseModel):
    topic_id: str
    subtopic_id: str
    question: str
    answer: str = Field(max_length=2000)
    prev_card: HelpCardPrev | None = None
    feedback: str | None = Field(default=None, max_length=2000)


class HelpAction(BaseModel):
    label: str
    type: Literal["focus", "exit"]
    duration_minutes: int | None = None


class HelpCardOut(BaseModel):
    messages: list[str]
    action: HelpAction
    feedback_options: list[str]


# ── Helpers ──


def _validate_question_shape(data: dict) -> bool:
    question = data.get("question")
    options = data.get("options")
    if not isinstance(question, str) or not question.strip():
        return False
    if not isinstance(options, list) or not (3 <= len(options) <= 6):
        return False
    if not all(isinstance(o, str) for o in options):
        return False
    return True


def _validate_card_shape(data: dict) -> bool:
    messages = data.get("messages")
    action = data.get("action")
    feedback_options = data.get("feedback_options")
    if not isinstance(messages, list) or not (1 <= len(messages) <= 3):
        return False
    if not all(isinstance(m, str) for m in messages):
        return False
    if not isinstance(action, dict):
        return False
    if action.get("type") not in ("focus", "exit"):
        return False
    if not isinstance(feedback_options, list) or not (3 <= len(feedback_options) <= 5):
        return False
    if not all(isinstance(o, str) for o in feedback_options):
        return False
    return True


# ── Endpoints ──


@router.post("/question", response_model=HelpQuestionOut)
async def get_help_question(
    body: HelpQuestionIn,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> HelpQuestionOut:
    log.info(
        "help_question_start user_id=%s topic_id=%s subtopic_id=%s",
        current_user_id,
        body.topic_id,
        body.subtopic_id,
    )

    try:
        topic_label, subtopic_label = validate_topic_subtopic(body.topic_id, body.subtopic_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    try:
        app_context = await build_help_app_context(session, current_user_id)
    except NoActiveRoomError:
        raise HTTPException(status_code=400, detail="No active room")
    except ProfileMissingError:
        raise HTTPException(status_code=400, detail="User profile not found")

    user_msg = build_question_user_message(topic_label, subtopic_label, app_context)

    try:
        result = await call_help_llm(SYSTEM_QUESTION, user_msg)
        if not _validate_question_shape(result):
            raise ValueError("Invalid shape")
    except (HelpLLMError, ValueError) as e:
        log.warning("help_question_fallback user_id=%s reason=%s", current_user_id, e)
        result = dict(FALLBACK_QUESTION)
    except Exception:
        log.exception("help_question_unexpected user_id=%s", current_user_id)
        result = dict(FALLBACK_QUESTION)

    log.info("help_question_done user_id=%s", current_user_id)
    return HelpQuestionOut(
        question=result["question"],
        options=result["options"],
    )


@router.post("/card", response_model=HelpCardOut)
async def get_help_card(
    body: HelpCardIn,
    session: AsyncSession = Depends(get_session),
    current_user_id: uuid.UUID = Depends(get_current_user_id),
) -> HelpCardOut:
    log.info(
        "help_card_start user_id=%s topic_id=%s subtopic_id=%s has_feedback=%s",
        current_user_id,
        body.topic_id,
        body.subtopic_id,
        body.feedback is not None,
    )

    try:
        topic_label, subtopic_label = validate_topic_subtopic(body.topic_id, body.subtopic_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    try:
        app_context = await build_help_app_context(session, current_user_id)
    except NoActiveRoomError:
        raise HTTPException(status_code=400, detail="No active room")
    except ProfileMissingError:
        raise HTTPException(status_code=400, detail="User profile not found")

    prev_card_dict: dict | None = None
    if body.prev_card is not None:
        prev_card_dict = {
            "messages": body.prev_card.messages,
            "action_label": body.prev_card.action_label,
        }

    user_msg = build_card_user_message(
        topic_label=topic_label,
        subtopic_label=subtopic_label,
        question=body.question,
        answer=body.answer,
        app_context=app_context,
        prev_card=prev_card_dict,
        feedback=body.feedback,
    )

    try:
        result = await call_help_llm(SYSTEM_CARD, user_msg)
        if not _validate_card_shape(result):
            raise ValueError("Invalid card shape")
    except (HelpLLMError, ValueError) as e:
        log.warning("help_card_fallback user_id=%s reason=%s", current_user_id, e)
        result = dict(FALLBACK_CARD)
    except Exception:
        log.exception("help_card_unexpected user_id=%s", current_user_id)
        result = dict(FALLBACK_CARD)

    action_data = result["action"]
    dur = action_data.get("duration_minutes")
    if dur is not None:
        dur = max(5, min(90, int(dur)))
    action = HelpAction(
        label=action_data["label"],
        type=action_data["type"],
        duration_minutes=dur,
    )

    log.info("help_card_done user_id=%s action_type=%s", current_user_id, action.type)
    return HelpCardOut(
        messages=result["messages"],
        action=action,
        feedback_options=result["feedback_options"],
    )
