"""Tests for the /api/v1/plan router."""

from __future__ import annotations

import os
import uuid
from typing import Any
from unittest.mock import AsyncMock, MagicMock

import pytest

os.environ.setdefault("DB_SSL_DISABLE", "1")

from fastapi import FastAPI
from pydantic import ValidationError
from starlette.testclient import TestClient

from backend.apps.api.routers import plan as plan_router
from backend.infrastructure.database.session import get_session
from backend.infrastructure.security.auth import get_current_user_id

_USER_ID = uuid.uuid4()


def _make_app(authed: bool = True) -> FastAPI:
    app = FastAPI()
    app.include_router(plan_router.router)

    async def _fake_session():
        session = AsyncMock()
        session.commit = AsyncMock()
        yield session

    async def _fake_user_id():
        return _USER_ID

    app.dependency_overrides[get_session] = _fake_session
    if authed:
        app.dependency_overrides[get_current_user_id] = _fake_user_id
    return app


def _fake_profile(**overrides: Any) -> Any:
    profile = MagicMock()
    profile.plan_hours_per_day = None
    profile.plan_hours_changed_at = None
    profile.growth_target_hours = None
    profile.growth_speed = None
    profile.growth_started_at = None
    for k, v in overrides.items():
        setattr(profile, k, v)
    return profile


# ── PlanUpdate schema validation ──


class TestPlanUpdateSchema:
    def test_hours_per_day_wrong_length_raises(self):
        from backend.apps.api.routers.plan import PlanUpdate

        with pytest.raises(ValidationError):
            PlanUpdate(hours_per_day=[1, 2, 3])

    def test_hours_per_day_value_over_24_raises(self):
        from backend.apps.api.routers.plan import PlanUpdate

        with pytest.raises(ValidationError):
            PlanUpdate(hours_per_day=[25, 0, 0, 0, 0, 0, 0])

    def test_growth_speed_invalid_enum_raises(self):
        from backend.apps.api.routers.plan import PlanUpdate

        with pytest.raises(ValidationError):
            PlanUpdate(growth_speed="turbo")

    def test_valid_payload_accepted(self):
        from backend.apps.api.routers.plan import PlanUpdate

        p = PlanUpdate(
            hours_per_day=[2, 2, 2, 2, 2, 0, 0],
            growth_target_hours=100,
            growth_speed="steady",
        )
        assert p.hours_per_day == [2, 2, 2, 2, 2, 0, 0]
        assert p.growth_speed == "steady"

    def test_none_values_accepted(self):
        from backend.apps.api.routers.plan import PlanUpdate

        p = PlanUpdate(hours_per_day=None, growth_speed=None)
        assert p.hours_per_day is None

    def test_growth_target_hours_over_limit_raises(self):
        from backend.apps.api.routers.plan import PlanUpdate

        with pytest.raises(ValidationError):
            PlanUpdate(growth_target_hours=10001)


# ── GET /api/v1/plan/ ──


class TestGetPlan:
    def test_requires_auth(self):
        app = _make_app(authed=False)
        client = TestClient(app, raise_server_exceptions=False)
        response = client.get("/api/v1/plan/")
        assert response.status_code == 401

    def test_returns_none_fields_when_no_plan_set(self, monkeypatch: pytest.MonkeyPatch):
        profile = _fake_profile()

        async def _fake_get_profile(self_repo: Any) -> Any:
            return profile

        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "get_profile", _fake_get_profile
        )

        app = _make_app()
        client = TestClient(app)
        response = client.get("/api/v1/plan/")
        assert response.status_code == 200
        data = response.json()
        assert data["hours_per_day"] is None
        assert data["growth_target_hours"] is None
        assert data["growth_speed"] is None
        assert data["growth_started_at"] is None

    def test_returns_404_when_profile_missing(self, monkeypatch: pytest.MonkeyPatch):
        async def _fake_get_profile(self_repo: Any) -> None:
            return None

        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "get_profile", _fake_get_profile
        )

        app = _make_app()
        client = TestClient(app, raise_server_exceptions=False)
        response = client.get("/api/v1/plan/")
        assert response.status_code == 404


# ── PATCH /api/v1/plan/ ──


class TestPatchPlan:
    def test_valid_patch_returns_updated_plan(self, monkeypatch: pytest.MonkeyPatch):
        profile = _fake_profile()

        async def _fake_get_profile(self_repo: Any) -> Any:
            return profile

        async def _fake_update_profile(self_repo: Any, p: Any) -> Any:
            return p

        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "get_profile", _fake_get_profile
        )
        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "update_profile", _fake_update_profile
        )

        app = _make_app()
        client = TestClient(app)
        payload = {
            "hours_per_day": [2, 2, 2, 2, 2, 0, 0],
            "growth_target_hours": 200,
            "growth_speed": "faster",
        }
        response = client.patch("/api/v1/plan/", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert data["hours_per_day"] == [2, 2, 2, 2, 2, 0, 0]
        assert data["growth_target_hours"] == 200
        assert data["growth_speed"] == "faster"

    def test_patch_hours_per_day_sets_changed_at(self, monkeypatch: pytest.MonkeyPatch):
        profile = _fake_profile()

        async def _fake_get_profile(self_repo: Any) -> Any:
            return profile

        async def _fake_update_profile(self_repo: Any, p: Any) -> Any:
            return p

        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "get_profile", _fake_get_profile
        )
        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "update_profile", _fake_update_profile
        )

        app = _make_app()
        client = TestClient(app)
        response = client.patch("/api/v1/plan/", json={"hours_per_day": [1, 1, 1, 1, 1, 0, 0]})
        assert response.status_code == 200
        assert profile.plan_hours_changed_at is not None

    def test_patch_hours_per_day_wrong_length_returns_422(self):
        app = _make_app()
        client = TestClient(app, raise_server_exceptions=False)
        response = client.patch("/api/v1/plan/", json={"hours_per_day": [1, 2, 3]})
        assert response.status_code == 422

    def test_patch_hours_over_24_returns_422(self):
        app = _make_app()
        client = TestClient(app, raise_server_exceptions=False)
        response = client.patch("/api/v1/plan/", json={"hours_per_day": [25, 0, 0, 0, 0, 0, 0]})
        assert response.status_code == 422

    def test_patch_invalid_growth_speed_returns_422(self):
        app = _make_app()
        client = TestClient(app, raise_server_exceptions=False)
        response = client.patch("/api/v1/plan/", json={"growth_speed": "turbo"})
        assert response.status_code == 422

    def test_patch_null_clears_fields(self, monkeypatch: pytest.MonkeyPatch):
        profile = _fake_profile(
            plan_hours_per_day=[1, 1, 1, 1, 1, 0, 0],
            growth_speed="steady",
        )

        async def _fake_get_profile(self_repo: Any) -> Any:
            return profile

        async def _fake_update_profile(self_repo: Any, p: Any) -> Any:
            return p

        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "get_profile", _fake_get_profile
        )
        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "update_profile", _fake_update_profile
        )

        app = _make_app()
        client = TestClient(app)
        response = client.patch("/api/v1/plan/", json={"hours_per_day": None, "growth_speed": None})
        assert response.status_code == 200
        data = response.json()
        assert data["hours_per_day"] is None
        assert data["growth_speed"] is None

    def test_patch_null_hours_also_sets_changed_at(self, monkeypatch: pytest.MonkeyPatch):
        profile = _fake_profile(plan_hours_per_day=[1, 1, 1, 1, 1, 0, 0])

        async def _fake_get_profile(self_repo: Any) -> Any:
            return profile

        async def _fake_update_profile(self_repo: Any, p: Any) -> Any:
            return p

        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "get_profile", _fake_get_profile
        )
        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "update_profile", _fake_update_profile
        )

        app = _make_app()
        client = TestClient(app)
        response = client.patch("/api/v1/plan/", json={"hours_per_day": None})
        assert response.status_code == 200
        assert profile.plan_hours_changed_at is not None

    def test_patch_404_when_profile_missing(self, monkeypatch: pytest.MonkeyPatch):
        async def _fake_get_profile(self_repo: Any) -> None:
            return None

        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "get_profile", _fake_get_profile
        )

        app = _make_app()
        client = TestClient(app, raise_server_exceptions=False)
        response = client.patch("/api/v1/plan/", json={})
        assert response.status_code == 404

    def test_patch_empty_body_is_noop(self, monkeypatch: pytest.MonkeyPatch):
        profile = _fake_profile(
            plan_hours_per_day=[3, 3, 3, 3, 3, 0, 0],
            growth_target_hours=100,
            growth_speed="steady",
        )
        original_hours = [3, 3, 3, 3, 3, 0, 0]

        async def _fake_get_profile(self_repo: Any) -> Any:
            return profile

        async def _fake_update_profile(self_repo: Any, p: Any) -> Any:
            return p

        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "get_profile", _fake_get_profile
        )
        monkeypatch.setattr(
            plan_router.SqlAlchemyGamificationRepository, "update_profile", _fake_update_profile
        )

        app = _make_app()
        client = TestClient(app)
        response = client.patch("/api/v1/plan/", json={})
        assert response.status_code == 200
        data = response.json()
        assert data["hours_per_day"] == original_hours
        assert data["growth_target_hours"] == 100
        assert data["growth_speed"] == "steady"
