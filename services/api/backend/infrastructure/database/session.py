from __future__ import annotations

import hashlib
import os
import time
from typing import AsyncIterator

from sqlalchemy import event
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from backend.infrastructure.logging import get_logger
from backend.infrastructure.config import settings

# Load .env if available so local runs pick up DATABASE_URL
try:
    from dotenv import load_dotenv  # type: ignore
    from pathlib import Path

    # Try to load from backend/.env first
    backend_dir = Path(__file__).resolve().parent.parent
    env_file = backend_dir / ".env"
    if env_file.exists():
        load_dotenv(dotenv_path=str(env_file), override=False)
    else:
        # Fallback: try loading from current working directory
        load_dotenv(override=False)
except Exception:
    pass


def _normalize_asyncpg_url(url: str) -> str:
    if url.startswith("postgresql://") and "+asyncpg" not in url:
        return url.replace("postgresql://", "postgresql+asyncpg://", 1)
    if url.startswith("postgres://") and "+asyncpg" not in url:
        return url.replace("postgres://", "postgresql+asyncpg://", 1)
    return url


from backend.infrastructure.database.asyncpg_ssl import build_asyncpg_ssl


def get_database_url() -> str:
    url = os.getenv("DATABASE_URL")
    if not url:
        raise ValueError("DATABASE_URL environment variable is not set")
    return _normalize_asyncpg_url(url)


def _setup_query_instrumentation(engine: AsyncEngine) -> None:
    """Setup SQLAlchemy event listeners for Prometheus metrics and optional structured logging."""
    from backend.infrastructure.metrics import db_query_duration_seconds, db_queries_total

    log_queries = settings.DB_LOG_QUERIES
    logger = None
    if log_queries:
        logger = get_logger("database")
        logger = logger.bind(service="db")

    sync_engine = engine.sync_engine

    @event.listens_for(sync_engine, "before_cursor_execute")
    def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
        """Record query start time; optionally log query start."""
        conn.info.setdefault("query_start_time", []).append(time.perf_counter())

        if logger:
            import structlog.contextvars

            context_vars = structlog.contextvars.get_contextvars()
            request_id = context_vars.get("request_id")
            user_id = context_vars.get("user_id")

            statement_hash = hashlib.sha256(statement.encode("utf-8")).hexdigest()[:16]

            log_data = {
                "event": "db_query_start",
                "statement_hash": statement_hash,
                "statement_length": len(statement),
                "truncated": len(statement) > 500,
            }
            if request_id:
                log_data["request_id"] = request_id
                log_data["req_short"] = request_id[:8] if len(request_id) > 8 else request_id
            if user_id:
                log_data["user_id"] = user_id

            logger.debug(**log_data)

    @event.listens_for(sync_engine, "after_cursor_execute")
    def after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
        """Record Prometheus metrics; optionally log query completion."""
        import re

        # --- Timing ---
        query_start_times = conn.info.get("query_start_time", [])
        if query_start_times:
            start_time = query_start_times.pop()
            duration_ms = (time.perf_counter() - start_time) * 1000
        else:
            duration_ms = None

        # --- Extract op & entity (needed for both metrics and logging) ---
        statement_upper = statement.strip().upper()
        op = None
        if statement_upper.startswith("SELECT"):
            op = "select"
        elif statement_upper.startswith("INSERT"):
            op = "insert"
        elif statement_upper.startswith("UPDATE"):
            op = "update"
        elif statement_upper.startswith("DELETE"):
            op = "delete"

        entity = None
        if op == "select":
            match = re.search(r"\bFROM\s+(?:\w+\.)?(\w+)", statement_upper)
            if match:
                entity = match.group(1).lower()
        elif op in ("insert", "update"):
            match = re.search(r"\b(?:INTO|UPDATE)\s+(?:\w+\.)?(\w+)", statement_upper)
            if match:
                entity = match.group(1).lower()
        elif op == "delete":
            match = re.search(r"\bFROM\s+(?:\w+\.)?(\w+)", statement_upper)
            if match:
                entity = match.group(1).lower()

        # --- Prometheus metrics (always) ---
        op_label = op or "other"
        entity_label = entity or "unknown"
        db_queries_total.labels(op=op_label, entity=entity_label).inc()
        if duration_ms is not None:
            db_query_duration_seconds.labels(op=op_label, entity=entity_label).observe(
                duration_ms / 1000
            )

        # --- Structured logging (opt-in via DB_LOG_QUERIES) ---
        if logger:
            import structlog.contextvars

            context_vars = structlog.contextvars.get_contextvars()
            request_id = context_vars.get("request_id")
            user_id = context_vars.get("user_id")

            rows = None
            try:
                if hasattr(cursor, "rowcount") and cursor.rowcount is not None:
                    rows = cursor.rowcount
            except Exception:
                pass

            statement_hash = hashlib.sha256(statement.encode("utf-8")).hexdigest()[:16]

            log_data = {
                "event": "db_query_completed",
                "statement_hash": statement_hash,
                "statement_length": len(statement),
                "truncated": len(statement) > 500,
            }
            if duration_ms is not None:
                log_data["duration_ms"] = round(duration_ms, 2)
            if op:
                log_data["op"] = op
            if entity:
                log_data["entity"] = entity
                log_data["table"] = entity
            if rows is not None:
                log_data["rows"] = rows
            if request_id:
                log_data["request_id"] = request_id
                log_data["req_short"] = request_id[:8] if len(request_id) > 8 else request_id
            if user_id:
                log_data["user_id"] = user_id

            logger.info(**log_data)


def create_engine() -> AsyncEngine:
    url = get_database_url()
    if url.startswith("postgresql+asyncpg://"):
        ssl_ctx = build_asyncpg_ssl()
        connect_args: dict = {"ssl": ssl_ctx} if ssl_ctx is not None else {}
        # Disable asyncpg prepared statement cache for Supavisor/PgBouncer compatibility.
        connect_args["statement_cache_size"] = 0
        # Enable raw SQL mode on Supavisor to prevent named prepared statement collisions
        # under concurrent load. Without this, asyncpg creates __asyncpg_stmt_N__ statements
        # that collide when PgBouncer reassigns backend connections between transactions.
        if "pooler.supabase" in url:
            connect_args.setdefault("server_settings", {})["raw_sql_session_mode"] = "true"
    else:
        connect_args = {}
    engine = create_async_engine(
        url,
        echo=False,  # We use custom event listeners instead
        pool_size=int(os.getenv("DB_POOL_SIZE", "10")),
        max_overflow=int(os.getenv("DB_MAX_OVERFLOW", "5")),
        pool_pre_ping=os.getenv("DB_POOL_PRE_PING", "true").lower() in ("1", "true", "yes"),
        pool_recycle=int(os.getenv("DB_POOL_RECYCLE", "300")),
        connect_args=connect_args,
    )

    # Setup Prometheus metrics + optional query logging
    _setup_query_instrumentation(engine)

    return engine


engine: AsyncEngine = create_engine()
SessionLocal = async_sessionmaker(bind=engine, expire_on_commit=False, class_=AsyncSession)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
