from __future__ import annotations

import logging
import os
import random
import sys

import structlog

SERVICE_NAME = os.getenv("SERVICE_NAME", "api")


def _add_agent_flag(logger, method_name, event_dict):
    """Добавляет поле agent: true для всех логов агента"""
    import structlog.contextvars

    context_vars = structlog.contextvars.get_contextvars()
    source = event_dict.get("source") or context_vars.get("source")

    if source == "agent":
        event_dict["agent"] = True

    return event_dict


def _drop_unsampled_info(logger, method_name, event_dict):
    if event_dict.get("level") != "info":
        return event_dict

    logger_name = event_dict.get("logger")
    event = event_dict.get("event")
    source = event_dict.get("source")

    if logger_name == "request":
        return event_dict
    if logger_name == "database":
        return event_dict
    if source == "agent":
        return event_dict
    if isinstance(event, str) and event.endswith("_sampled"):
        return event_dict

    raise structlog.DropEvent


def configure_logging(level: str = "INFO") -> None:
    logging.basicConfig(
        stream=sys.stdout,
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(message)s",
    )
    # Disable Uvicorn access logs to avoid duplication with our middleware
    logging.getLogger("uvicorn.access").disabled = True
    processors = [
        structlog.contextvars.merge_contextvars,  # Add context variables (request_id, user_id, source)
        structlog.stdlib.add_logger_name,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", key="timestamp"),
        _add_agent_flag,  # Добавляем agent: true для логов агента
        _drop_unsampled_info,
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer(),  # JSON output for Loki
    ]
    structlog.configure(
        processors=processors,
        wrapper_class=structlog.make_filtering_bound_logger(
            getattr(logging, level.upper(), logging.INFO)
        ),
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
        context_class=dict,
    )


def get_logger(name: str) -> structlog.stdlib.BoundLogger:
    """Get a logger instance with service context."""
    logger = structlog.get_logger(name)
    # Добавляем только service - это единственное поле, которое будет меткой в Loki
    logger = logger.bind(service=SERVICE_NAME)
    return logger


SAMPLE_RATE_SUCCESS = 0.05  # 5% of successful requests


def should_log_success() -> bool:
    """Sampling: log only ~5% of successful request/response pairs."""
    return random.random() < SAMPLE_RATE_SUCCESS


def get_log_context() -> dict[str, str | None]:
    """Get request_id and user_id from structlog contextvars."""
    import structlog.contextvars

    context_vars = structlog.contextvars.get_contextvars()
    request_id = context_vars.get("request_id")
    return {
        "request_id": request_id,
        "user_id": context_vars.get("user_id"),
        "req_short": request_id[:8] if request_id else None,  # Short version for readability
    }
