from __future__ import annotations

from typing import Optional
from pathlib import Path

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Determine backend directory (where this file is located)
_backend_dir = Path(__file__).resolve().parent.parent
_env_file = _backend_dir / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(_env_file), env_file_encoding="utf-8", extra="ignore"
    )

    # Environment
    ENV: str
    LOG_LEVEL: str

    # Database
    DATABASE_URL: str
    DB_POOL_SIZE: int
    DB_MAX_OVERFLOW: int
    DB_LOG_QUERIES: bool = False  # Enable SQL query logging via SQLAlchemy events
    DB_POOL_PRE_PING: bool = True  # Verify connections before checkout (detects stale conns)
    DB_POOL_RECYCLE: int = 300  # Recycle connections after N seconds (avoid server-side timeouts)

    # Supabase
    SUPABASE_URL: str
    SUPABASE_ANON_KEY: Optional[str] = None
    SUPABASE_SERVICE_ROLE_KEY: str
    SUPABASE_JWT_SECRET: Optional[str] = None

    # CORS
    CORS_ORIGINS: list[str] = ["http://localhost:3001"]

    # HTTP
    REQUEST_TIMEOUT_S: int

    # Redis Coordination (noeviction — rate limit, semaphore)
    REDIS_COORDINATION_HOST: str = "localhost"
    REDIS_COORDINATION_PORT: int = 6380

    # Redis Cache (allkeys-lru — ETag, cursor, gamification)
    REDIS_CACHE_HOST: str = "localhost"
    REDIS_CACHE_PORT: int = 6381

    # Sync cursor HMAC signing
    CURSOR_SECRET: str = "change-me-in-production"

    # Agent (LLM)
    AGENT_MODEL: Optional[str] = None  # Model name for agent LLM
    BASE_URL: Optional[str] = None  # Base URL for LLM API (e.g., OpenRouter)
    OPENROUTER_API_KEY: Optional[str] = None  # API key for OpenRouter or other LLM provider
    HELP_AGENT_MODEL: Optional[str] = None  # Model for help-flow agent; falls back to AGENT_MODEL
    BACKEND_API_URL: Optional[str] = (
        None  # Backend API URL for agent tools (defaults to internal URL)
    )
    AGENT_TOOL_TIMEOUT_S: int = 60  # Timeout for agent tool calls in seconds

    # Load testing
    LOADTEST_MODE: bool = False  # Bypass rate limiting for load tests (dev only)

    # PostHog (admin analytics proxy)
    POSTHOG_PROJECT_ID: str = ""
    POSTHOG_PERSONAL_API_KEY: str = ""
    POSTHOG_HOST: str = "https://us.i.posthog.com"

    @model_validator(mode="after")
    def _check_jwt_secret(self) -> "Settings":
        if self.SUPABASE_URL and not self.SUPABASE_JWT_SECRET:
            raise ValueError("SUPABASE_JWT_SECRET is required when SUPABASE_URL is set")
        return self


settings = Settings()  # type: ignore[misc]
