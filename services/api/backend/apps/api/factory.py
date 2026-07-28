from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.infrastructure.config import settings
from backend.infrastructure.logging import configure_logging, get_logger
from backend.apps.api.errors import install_error_handlers
from backend.apps.api.middleware import request_id_middleware, rate_limit_middleware
from backend.infrastructure.metrics import metrics_middleware

from backend.apps.api.routers import notifications as notifications_router
from backend.apps.api.routers import announcements as announcements_router
from backend.apps.api.routers import auth as auth_router
from backend.apps.api.routers import chat as chat_router
from backend.apps.api.routers import agent as agent_router
from backend.apps.api.routers import focus as focus_router
from backend.apps.api.routers import focus_rooms as focus_rooms_router
from backend.apps.api.routers import gamification as gamification_router
from backend.apps.api.routers import mascot_skins as mascot_skins_router
from backend.apps.api.routers import sync as sync_router
from backend.apps.api.routers import admin as admin_router
from backend.apps.api.routers import users as users_router
from backend.apps.api.routers import plan as plan_router
from backend.apps.api.routers import profile_stats as profile_stats_router
from backend.apps.api.routers import help as help_router

logger = get_logger("app.lifespan")


@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncIterator[None]:
    logger.info("startup")
    yield
    # Graceful shutdown: dispose DB engine to close all pooled connections
    from backend.infrastructure.database.session import engine

    logger.info("shutdown_disposing_db_engine")
    await engine.dispose()
    logger.info("shutdown_complete")


def create_app() -> FastAPI:
    configure_logging(settings.LOG_LEVEL)
    app = FastAPI(
        title="Meleo API",
        version="0.1.0",
        docs_url="/docs" if settings.ENV == "dev" else None,
        openapi_url="/openapi.json" if settings.ENV == "dev" else None,
        lifespan=_lifespan,
    )

    # CORS — должен идти сразу после app = FastAPI(), до include_router
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],  # или ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
        allow_headers=["*"],
    )

    # Middleware (applied in reverse order — last added runs first)
    app.middleware("http")(request_id_middleware)
    app.middleware("http")(rate_limit_middleware)
    app.middleware("http")(metrics_middleware)

    # Errors
    install_error_handlers(app)

    # Routers
    app.include_router(auth_router.router)
    app.include_router(notifications_router.router)
    app.include_router(announcements_router.router)
    app.include_router(chat_router.router)
    app.include_router(agent_router.router)
    app.include_router(focus_router.router)
    app.include_router(focus_rooms_router.router)
    app.include_router(gamification_router.router)
    app.include_router(mascot_skins_router.router)
    app.include_router(sync_router.router)
    app.include_router(admin_router.router)
    app.include_router(users_router.router, prefix="/api/v1")
    app.include_router(plan_router.router)
    app.include_router(profile_stats_router.router)
    app.include_router(help_router.router)

    # Health check endpoints
    @app.get("/")
    async def root():
        return {"status": "ok"}

    @app.get("/health")
    async def health():
        return {"status": "ok"}

    # Prometheus metrics endpoint
    from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
    from fastapi.responses import Response as FastAPIResponse

    @app.get("/metrics", include_in_schema=False)
    async def prometheus_metrics():
        return FastAPIResponse(
            content=generate_latest(),
            media_type=CONTENT_TYPE_LATEST,
        )

    return app
