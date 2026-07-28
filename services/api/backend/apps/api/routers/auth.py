from __future__ import annotations

import importlib
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
import re

from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy.ext.asyncio import AsyncSession

from backend.domain.users.deletion_service import delete_user_data
from backend.infrastructure.database.session import get_session
from backend.infrastructure.logging import get_logger
from backend.infrastructure.repositories import SqlAlchemyUserRepository
from backend.infrastructure.security.auth import (
    get_current_user_id,
    verify_user_token,
    revoke_token,
)
from backend.infrastructure.security.logging_utils import mask_sensitive_fields
from backend.infrastructure.security.supabase_auth import get_supabase_auth_service

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])
logger = get_logger("auth")


def _get_auth_api_error_type():
    try:
        module = importlib.import_module("gotrue.errors")
        return getattr(module, "AuthApiError", None)
    except Exception:
        return None


# Pydantic схемы
class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)

    @field_validator("password")
    @classmethod
    def password_complexity(cls, v: str) -> str:
        if not re.search(r"[a-zA-Z]", v):
            raise ValueError("Password must contain at least one letter")
        if not re.search(r"[\d\W_]", v):
            raise ValueError("Password must contain at least one digit or special character")
        return v


class RegisterResponse(BaseModel):
    message: str
    supabase_user_id: str
    supabaseUserId: str
    email_verification_required: bool = True


async def _resolve_supabase_user(
    supabase_service,
    email: str,
    password: str,
) -> tuple[uuid.UUID, bool, bool]:
    """
    Зарегистрировать пользователя в Supabase (с отправкой OTP по email).

    Возвращает (supabase_user_id, email_confirmed, identities_empty):
        email_confirmed=True   — email уже подтверждён ранее (повторная регистрация
                                  существующего юзера); OTP отправлять не нужно.
        identities_empty=True  — Supabase вернул "фейкового" юзера: email уже занят
                                  с другим паролем. Письмо НЕ отправлено.
    """
    try:
        result = supabase_service.sign_up_user(email=email, password=password)
        return (
            uuid.UUID(str(result["id"])),
            bool(result.get("email_confirmed")),
            bool(result.get("identities_empty")),
        )
    except HTTPException as e:
        if e.status_code != status.HTTP_409_CONFLICT:
            raise
        existing_user = supabase_service.find_user_by_email(email)
        if not existing_user or not existing_user.get("id"):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="User already exists in Supabase but ID could not be resolved",
            )
        email_confirmed = bool(
            existing_user.get("email_confirmed_at") or existing_user.get("confirmed_at")
        )
        return uuid.UUID(str(existing_user["id"])), email_confirmed, False


@router.post("/register", response_model=RegisterResponse, status_code=status.HTTP_201_CREATED)
async def register(
    request: RegisterRequest,
):
    """
    Регистрация нового пользователя.

    Создаёт пользователя в Supabase Auth через публичный sign_up.
    Supabase отправляет OTP на email; пользователь подтверждает код через
    клиентский SDK (verifyOtp). Локальная запись в БД создаётся лениво
    в get_current_user_id при первом авторизованном запросе.
    """
    # Маскируем пароль для логирования
    masked_request = mask_sensitive_fields(request.model_dump())
    logger.info("register_request", **masked_request)

    try:
        supabase_service = get_supabase_auth_service()

        supabase_user_id, email_confirmed, identities_empty = await _resolve_supabase_user(
            supabase_service=supabase_service,
            email=request.email,
            password=request.password,
        )

        # Email уже занят другим паролем — Supabase вернул "фейкового" юзера,
        # письмо НЕ отправлено. Отбиваем явным 409, чтобы клиент перевёл юзера
        # на экран логина вместо ожидания кода, который никогда не придёт.
        if identities_empty:
            logger.info(
                "register_email_already_taken",
                email=request.email,
                supabase_user_id=supabase_user_id,
            )
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email is already registered. Please sign in instead.",
            )

        verification_required = not email_confirmed

        logger.info(
            "user_registered",
            email=request.email,
            supabase_user_id=supabase_user_id,
            email_confirmed=email_confirmed,
            verification_required=verification_required,
        )

        if verification_required:
            message = "Verification code sent"
        else:
            message = "Email already verified, please sign in"

        payload = RegisterResponse(
            message=message,
            supabase_user_id=str(supabase_user_id),
            supabaseUserId=str(supabase_user_id),
            email_verification_required=verification_required,
        )
        if email_confirmed:
            return JSONResponse(status_code=status.HTTP_200_OK, content=payload.model_dump())
        return payload

    except HTTPException:
        raise
    except Exception as e:
        logger.error(
            "registration_failed", email=request.email, error=str(e), error_type=type(e).__name__
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Registration failed"
        )


@router.post("/logout")
async def logout(request: Request):
    """
    Server-side logout: revoke user sessions in Supabase via Admin API.
    Client logout should be done in mobile via end-session and local token clear.

    Note: Accepts expired tokens (verifies signature only) to allow logout
    even after token expiry.
    """
    logger.info("logout_request")

    auth = request.headers.get("Authorization") or request.headers.get("authorization")
    if not auth or not auth.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    token = auth.split(" ", 1)[1].strip()
    # Верифицируем токен без проверки expiry (разрешаем logout с истекшими токенами)
    payload = verify_user_token(token, verify_expiry=False)
    supabase_user_id = payload.get("sub")
    if not supabase_user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    # Revoke token in local cache
    revoke_token(token)

    supabase_service = get_supabase_auth_service()
    supabase_service.sign_out(token)

    logger.info("logout_sessions_revoked", supabase_user_id=supabase_user_id)
    return {"message": "User sessions revoked"}


@router.delete("/account", status_code=status.HTTP_200_OK)
async def delete_account(
    user_id: uuid.UUID = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    user_repo = SqlAlchemyUserRepository(session)
    user = await user_repo.get_by_id(user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    supabase_user_id = user.supabase_user_id

    await delete_user_data(session, user_id)

    supabase_service = get_supabase_auth_service()
    try:
        if supabase_user_id is not None:
            supabase_service.delete_user(str(supabase_user_id))
    except Exception as exc:
        logger.error("supabase_delete_failed", user_id=str(user_id), error=str(exc))

    logger.info("account_deleted", user_id=str(user_id))
    return {"message": "Account deleted"}
