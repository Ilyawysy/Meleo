from __future__ import annotations

import uuid

import structlog.contextvars
import jwt
from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from backend.infrastructure.database.session import get_session
from backend.infrastructure.logging import get_logger
from backend.infrastructure.repositories import SqlAlchemyUserRepository
from backend.infrastructure.security.supabase_auth import get_supabase_auth_service


# In-memory revoked token hashes (cleared on restart; for prod use Redis)
import hashlib
import threading
import time as _time

_revoked_tokens: dict[str, float] = {}  # token_hash -> expiry timestamp
_revoked_lock = threading.Lock()

# In-memory cache: supabase_user_id (str) -> (internal_user_id: UUID, expires_at: float)
_USER_CACHE_TTL = 300  # 5 minutes
_user_cache: dict[str, tuple[uuid.UUID, float]] = {}
_user_cache_lock = threading.Lock()


def _cache_user(supabase_uid: str, internal_id: uuid.UUID) -> None:
    with _user_cache_lock:
        _user_cache[supabase_uid] = (internal_id, _time.time() + _USER_CACHE_TTL)


def _get_cached_user(supabase_uid: str) -> uuid.UUID | None:
    with _user_cache_lock:
        entry = _user_cache.get(supabase_uid)
        if entry is None:
            return None
        internal_id, expires_at = entry
        if expires_at < _time.time():
            del _user_cache[supabase_uid]
            return None
        return internal_id


def revoke_token(token: str, ttl: int = 3600) -> None:
    """Add a token hash to the revoked set. TTL defaults to 1 hour."""
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    with _revoked_lock:
        _revoked_tokens[token_hash] = _time.time() + ttl
        # Cleanup expired entries
        now = _time.time()
        expired = [k for k, v in _revoked_tokens.items() if v < now]
        for k in expired:
            del _revoked_tokens[k]


def is_token_revoked(token: str) -> bool:
    """Check if a token has been revoked."""
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    with _revoked_lock:
        expiry = _revoked_tokens.get(token_hash)
        if expiry is None:
            return False
        if expiry < _time.time():
            del _revoked_tokens[token_hash]
            return False
        return True


def _bind_authenticated_identity(
    request: Request,
    *,
    user_id: uuid.UUID,
    supabase_user_id: str | None = None,
) -> uuid.UUID:
    user_id_str = str(user_id)
    structlog.contextvars.bind_contextvars(user_id=user_id_str)
    request.state.user_id = user_id_str

    if supabase_user_id:
        supabase_user_id_str = str(supabase_user_id)
        structlog.contextvars.bind_contextvars(supabase_user_id=supabase_user_id_str)
        request.state.supabase_user_id = supabase_user_id_str

    return user_id


def verify_user_token(token: str, verify_expiry: bool = True) -> dict:
    """
    Верификация JWT токена пользователя (Supabase HS256).

    Args:
            token: JWT токен
            verify_expiry: Если False, игнорирует истечение токена (для logout)
    """
    logger_instance = get_logger("auth")
    logger_instance.debug("verifying_supabase_token", verify_expiry=verify_expiry)
    try:
        supabase_service = get_supabase_auth_service()

        # Для logout используем verify_token_skip_expiry
        if not verify_expiry:
            try:
                import jwt

                # Декодируем токен без проверки expiry
                unverified_header = jwt.get_unverified_header(token)
                alg = unverified_header.get("alg")

                if alg == "HS256":
                    if not supabase_service._jwt_secret:
                        raise HTTPException(
                            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                            detail="SUPABASE_JWT_SECRET is not configured",
                        )
                    payload = jwt.decode(
                        token,
                        supabase_service._jwt_secret,
                        algorithms=["HS256"],
                        options={"verify_exp": False},
                        audience="authenticated",
                        issuer=f"{supabase_service._supabase_url}/auth/v1",
                    )
                elif alg in {"RS256", "ES256"}:
                    if supabase_service._jwks_client is None:
                        import jwt

                        supabase_service._jwks_client = jwt.PyJWKClient(supabase_service._jwks_url)
                    signing_key = supabase_service._jwks_client.get_signing_key_from_jwt(token)
                    payload = jwt.decode(
                        token,
                        signing_key.key,
                        algorithms=[alg],
                        options={"verify_exp": False},
                        audience="authenticated",
                        issuer=f"{supabase_service._supabase_url}/auth/v1",
                    )
                else:
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token"
                    )

                logger_instance.debug(
                    "supabase_token_verified_skip_expiry", user_id=payload.get("sub")
                )
                return payload
            except jwt.InvalidTokenError:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token"
                )

        # Обычная верификация с проверкой expiry
        payload = supabase_service.verify_token(token)
        logger_instance.debug("supabase_token_verified", user_id=payload.get("sub"))
        return payload
    except HTTPException as e:
        # Best-effort decode without verifying signature to help debug token origin
        try:
            decoded = jwt.decode(
                token,
                options={"verify_signature": False, "verify_aud": False},
            )
            logger_instance.warning(
                "supabase_token_invalid_debug",
                iss=decoded.get("iss"),
                aud=decoded.get("aud"),
                has_sub=bool(decoded.get("sub")),
            )
        except Exception as debug_error:
            logger_instance.warning(
                "supabase_token_invalid_debug_failed",
                error=str(debug_error),
                error_type=type(debug_error).__name__,
            )
        # Supabase сервис уже выбросил HTTPException с правильным статусом
        # Get request_id from contextvars if available
        import structlog.contextvars

        context_vars = structlog.contextvars.get_contextvars()
        request_id = context_vars.get("request_id")
        log_data = {
            "status_code": e.status_code,
            "detail": e.detail,
        }
        if request_id:
            log_data["request_id"] = request_id
            log_data["req_short"] = request_id[:8] if len(request_id) > 8 else request_id
        logger_instance.warning("supabase_token_verification_http_exception", **log_data)
        raise
    except Exception as e:
        logger_instance.error(
            "supabase_token_verification_failed", error=str(e), error_type=type(e).__name__
        )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")


async def get_current_user_id(
    request: Request,
    session: AsyncSession = Depends(get_session),
) -> uuid.UUID:
    """
    Получение UUID текущего пользователя из JWT токена
    Токен должен быть Supabase HS256. Возвращает internal UUID пользователя.
    """
    auth = request.headers.get("Authorization") or request.headers.get("authorization")
    if not auth or not auth.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    token = auth.split(" ", 1)[1].strip()
    logger_instance = get_logger("auth")

    token_format = "jwt" if token.count(".") == 2 else "opaque"
    try:
        unverified_payload = jwt.decode(
            token,
            options={"verify_signature": False, "verify_aud": False},
        )
        logger_instance.debug(
            "received_auth_token",
            token_format=token_format,
            iss=unverified_payload.get("iss"),
            aud=unverified_payload.get("aud"),
            has_sub=bool(unverified_payload.get("sub")),
        )
    except Exception as decode_error:
        logger_instance.warning(
            "received_auth_token_unparseable",
            token_format=token_format,
            error=str(decode_error),
            error_type=type(decode_error).__name__,
        )

    # Check if token has been revoked
    if is_token_revoked(token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked"
        )

    # Верифицируем JWT токен пользователя
    payload = verify_user_token(token)
    supabase_user_id = payload.get("sub")
    try:
        supabase_user_uuid = uuid.UUID(str(supabase_user_id))
    except (TypeError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid user id in token"
        )

    logger_instance.debug("token_verified", supabase_user_id=supabase_user_id)

    # Для Supabase токенов: получаем или создаем пользователя в БД
    try:
        # Fast path: check in-memory cache before hitting DB
        cached_uid = _get_cached_user(str(supabase_user_id))
        if cached_uid is not None:
            logger_instance.debug("user_cache_hit", supabase_user_id=supabase_user_id)
            return _bind_authenticated_identity(
                request,
                user_id=cached_uid,
                supabase_user_id=str(supabase_user_id),
            )

        user_repo = SqlAlchemyUserRepository(session)

        try:
            user = await user_repo.get_by_supabase_user_id(supabase_user_uuid)
            if user:
                context_vars = structlog.contextvars.get_contextvars()
                request_id = context_vars.get("request_id")
                logger_instance.info(
                    "user_found_by_supabase_user_id",
                    request_id=request_id,
                    supabase_user_id=supabase_user_id,
                    user_id=str(user.id),
                )
                _cache_user(str(supabase_user_id), user.id)
                return _bind_authenticated_identity(
                    request,
                    user_id=user.id,
                    supabase_user_id=str(supabase_user_id),
                )

            # Создаем нового пользователя
            # DEBUG: creating_new_user - только для dev/troubleshooting
            from backend.domain.users.entities import User
            from sqlalchemy.exc import IntegrityError

            try:
                user = User(
                    id=uuid.uuid4(),
                    email=f"{supabase_user_uuid}@placeholder.invalid",
                    supabase_user_id=supabase_user_uuid,
                    password_hash=None,
                )
                user = await user_repo.create(user)
                context_vars = structlog.contextvars.get_contextvars()
                request_id = context_vars.get("request_id")
                logger_instance.info(
                    "user_created",
                    request_id=request_id,
                    supabase_user_id=supabase_user_id,
                    user_id=str(user.id),
                )
                _cache_user(str(supabase_user_id), user.id)
                return _bind_authenticated_identity(
                    request,
                    user_id=user.id,
                    supabase_user_id=str(supabase_user_id),
                )
            except IntegrityError:
                await session.rollback()
                user = await user_repo.get_by_supabase_user_id(supabase_user_uuid)
                if user:
                    _cache_user(str(supabase_user_id), user.id)
                    return _bind_authenticated_identity(
                        request,
                        user_id=user.id,
                        supabase_user_id=str(supabase_user_id),
                    )
                raise
        except Exception as db_error:
            logger_instance.error(
                "database_error", error=str(db_error), error_type=type(db_error).__name__
            )
            # Проверяем, является ли это ошибкой подключения
            if "Connection refused" in str(db_error) or "Connection" in str(db_error):
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Internal server error"
                )
            raise
    except HTTPException:
        raise
    except Exception as e:
        logger_instance.error(
            "failed_to_get_or_create_user", error=str(e), error_type=type(e).__name__
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error"
        )


async def get_current_user_roles(request: Request) -> list[str]:
    """
    Получение ролей текущего пользователя из JWT токена
    Работает с Supabase токенами (HS256) и custom claims
    """
    auth = request.headers.get("Authorization") or request.headers.get("authorization")
    if not auth or not auth.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    token = auth.split(" ", 1)[1].strip()

    try:
        payload = verify_user_token(token)
        role = payload.get("role")
        roles = payload.get("roles")
        app_metadata = payload.get("app_metadata") or {}
        app_roles = app_metadata.get("roles")

        collected: list[str] = []
        if isinstance(role, str):
            collected.append(role)
        if isinstance(roles, list):
            collected.extend([r for r in roles if isinstance(r, str)])
        if isinstance(app_roles, list):
            collected.extend([r for r in app_roles if isinstance(r, str)])

        # Normalize roles: dedupe with stable order
        seen = set()
        normalized: list[str] = []
        for item in collected:
            if item not in seen:
                normalized.append(item)
                seen.add(item)
        return normalized
    except HTTPException:
        raise
    except Exception as e:
        logger = get_logger("auth")
        logger.warning("failed_to_extract_roles", error=str(e))
        return []
