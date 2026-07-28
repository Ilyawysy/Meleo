from __future__ import annotations

import asyncio
import os
from pathlib import Path
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context


config = context.config

# Load .env so Alembic sees DATABASE_URL without manual export
# Find .env relative to project root (where alembic.ini is located)
try:
    from dotenv import load_dotenv  # type: ignore

    # Determine backend directory: env.py is at backend/alembic/env.py, so go up 2 levels
    backend_dir = Path(__file__).resolve().parent.parent
    env_file = backend_dir / os.getenv("ALEMBIC_ENV_FILE", ".env")

    # Also try to get from alembic.ini location if available (for compatibility)
    if config.config_file_name:
        try:
            alembic_ini_path = Path(config.config_file_name).resolve()
            if alembic_ini_path.exists():
                project_root_from_ini = alembic_ini_path.parent
                env_file_from_ini = (
                    project_root_from_ini / "backend" / os.getenv("ALEMBIC_ENV_FILE", ".env")
                )
                if env_file_from_ini.exists():
                    env_file = env_file_from_ini
        except Exception:
            pass

    override_existing_env = os.getenv("ALEMBIC_ENV_OVERRIDE", "").lower() in ("1", "true", "yes")

    # Load the .env file with absolute path
    if env_file.exists():
        load_dotenv(dotenv_path=str(env_file), override=override_existing_env)
    else:
        # Fallback: try loading from current working directory
        load_dotenv(override=override_existing_env)
except ImportError:
    # python-dotenv is not installed
    pass
except Exception:
    # Any other error - try simple load_dotenv() as last resort
    try:
        from dotenv import load_dotenv  # type: ignore

        override_existing_env = os.getenv("ALEMBIC_ENV_OVERRIDE", "").lower() in (
            "1",
            "true",
            "yes",
        )
        load_dotenv(override=override_existing_env)
    except Exception:
        pass

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

from backend.infrastructure.database.base import Base
from backend.domain.chat import entities as _chat_entities
from backend.domain.gamification import entities as _gamification_entities
from backend.domain.announcements import entities as _announcements_entities
from backend.domain.users import state_version as _state_version  # noqa: F401
from backend.domain.focus_rooms import entities as _focus_rooms_entities  # noqa: F401, E402
from backend.domain.focus_rooms import task_entities as _task_entities  # noqa: F401, E402
from backend.domain.focus_rooms import checklist_entities as _checklist_entities  # noqa: F401, E402
from backend.domain.focus import entities as _focus_entities  # noqa: F401, E402
from backend.domain.notifications import entities as _notifications_entities  # noqa: F401, E402
from backend.domain.mascot_skins import entities as _mascot_skins_entities  # noqa: F401, E402

target_metadata = Base.metadata


# backend/alembic/env.py
def get_url() -> str:
    # 1) allow override via `alembic -x url=...`
    x_args = context.get_x_argument(as_dictionary=True)
    if isinstance(x_args, dict):
        maybe_url = x_args.get("url")
        if maybe_url:
            return maybe_url

    # 2) fall back to env vars
    url = os.getenv("DATABASE_URL")
    if url is None:
        raise ValueError(
            "DATABASE_URL environment variable is not set. "
            "Please set it in your .env file or as an environment variable."
        )
    # Normalize to async driver if the URL is sync
    if url.startswith("postgresql://") and "+asyncpg" not in url:
        url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
    if url.startswith("postgres://") and "+asyncpg" not in url:
        url = url.replace("postgres://", "postgresql+asyncpg://", 1)
    return url


from backend.infrastructure.database.asyncpg_ssl import build_asyncpg_ssl


def run_migrations_offline() -> None:
    url = get_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    url = get_url()
    if url.startswith("postgresql+asyncpg://"):
        ssl_ctx = build_asyncpg_ssl()
        connect_args = {"ssl": ssl_ctx} if ssl_ctx is not None else {}
        # Disable asyncpg prepared statement cache for Supavisor/PgBouncer compatibility
        connect_args["statement_cache_size"] = 0
    else:
        connect_args = {}
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
        url=url,
        connect_args=connect_args,
    )

    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)

    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
