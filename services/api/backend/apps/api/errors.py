from __future__ import annotations

import structlog.contextvars
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError

from backend.infrastructure.logging import get_logger

logger = get_logger("errors")


class AppError(Exception):
    def __init__(self, code: str, message: str, details: object | None = None):
        self.code = code
        self.message = message
        self.details = details


def _get_request_id(request: Request) -> str | None:
    """
    Получает request_id из contextvars (если доступен) или из заголовка запроса.
    Гарантирует, что request_id будет получен даже если ошибка произошла до установки заголовка.
    """
    context_vars = structlog.contextvars.get_contextvars()
    request_id = context_vars.get("request_id")
    if request_id:
        return request_id
    return request.headers.get("X-Request-ID")


def _safe_errors(errors: list[dict]) -> list[dict]:
    """
    Делает список ошибок от Pydantic/FASTAPI сериализуемым:
    - выбрасываем несериализуемые поля (например 'input' с ORM-объектом),
    - оставляем только loc/msg/type.
    """
    safe: list[dict] = []
    for e in errors:
        safe.append({
            "loc": e.get("loc"),
            "msg": e.get("msg"),
            "type": e.get("type"),
        })
    return safe


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _handle_app_error(request: Request, exc: AppError):  # type: ignore[no-redef]
        request_id = _get_request_id(request)
        logger.error("app_error", code=exc.code, message=exc.message, details=exc.details, request_id=request_id)
        return JSONResponse(
            status_code=400,
            content={"error": {"code": exc.code, "message": exc.message, "details": exc.details}, "request_id": request_id},
        )

    @app.exception_handler(RequestValidationError)
    async def _handle_request_validation_error(request: Request, exc: RequestValidationError):  # type: ignore[no-redef]
        request_id = _get_request_id(request)
        logger.warning("validation_error", errors=_safe_errors(exc.errors()), request_id=request_id)
        return JSONResponse(
            status_code=422,
            content={"error": {"code": "validation_error", "message": "Validation failed", "details": _safe_errors(exc.errors())}, "request_id": request_id},
        )

    @app.exception_handler(ValidationError)
    async def _handle_validation_error(request: Request, exc: ValidationError):  # type: ignore[no-redef]
        request_id = _get_request_id(request)
        logger.warning("pydantic_validation_error", errors=_safe_errors(exc.errors()), request_id=request_id)
        return JSONResponse(
            status_code=422,
            content={"error": {"code": "validation_error", "message": "Validation failed", "details": _safe_errors(exc.errors())}, "request_id": request_id},
        )

    @app.exception_handler(HTTPException)
    async def _handle_http_exception(request: Request, exc: HTTPException):  # type: ignore[no-redef]
        request_id = _get_request_id(request)
        logger.warning("http_exception", status_code=exc.status_code, detail=exc.detail, request_id=request_id)
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": {"code": "http_error", "message": exc.detail, "details": None}, "request_id": request_id},
        )

    @app.exception_handler(Exception)
    async def _handle_unexpected_error(request: Request, exc: Exception):  # type: ignore[no-redef]
        request_id = _get_request_id(request)
        logger.error("unexpected_error", error=str(exc), error_type=type(exc).__name__, request_id=request_id, exc_info=True)
        return JSONResponse(
            status_code=500,
            content={"error": {"code": "internal_error", "message": "Internal server error", "details": None}, "request_id": request_id},
        )
