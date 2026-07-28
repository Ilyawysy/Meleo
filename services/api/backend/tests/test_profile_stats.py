"""Tests for the /api/v1/profile/stats endpoint and StatsService."""

from __future__ import annotations

import os
import uuid
from datetime import date, datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock

import pytest

os.environ.setdefault("DB_SSL_DISABLE", "1")

from fastapi import FastAPI
from starlette.testclient import TestClient

from backend.apps.api.routers import profile_stats as profile_stats_router
from backend.domain.gamification.stats_service import StatsService
from backend.infrastructure.database.session import get_session
from backend.infrastructure.security.auth import get_current_user_id

_USER_ID = uuid.uuid4()


def _make_app(authed: bool = True) -> FastAPI:
    app = FastAPI()
    app.include_router(profile_stats_router.router)

    async def _fake_session():
        session = AsyncMock()
        yield session

    async def _fake_user_id():
        return _USER_ID

    app.dependency_overrides[get_session] = _fake_session
    if authed:
        app.dependency_overrides[get_current_user_id] = _fake_user_id
    return app


# ── Auth ──


def test_requires_auth():
    app = _make_app(authed=False)
    client = TestClient(app, raise_server_exceptions=False)
    response = client.get("/api/v1/profile/stats")
    assert response.status_code == 401


# ── StatsService unit tests ──


class TestStatsServiceEmptyUser:
    @pytest.mark.asyncio
    async def test_empty_user_returns_zeros(self):
        session = AsyncMock()

        # all_focus_seconds → sum = 0
        result_sum = MagicMock()
        result_sum.scalar_one.return_value = 0

        # days_in_app → user created_at
        result_user = MagicMock()
        result_user.scalar_one_or_none.return_value = datetime(2026, 1, 1, tzinfo=timezone.utc)

        # profile (longest_streak)
        result_profile = MagicMock()
        result_profile.scalar_one_or_none.return_value = None

        # best_day, best_week, best_month → no rows
        result_none = MagicMock()
        result_none.first.return_value = None
        result_none.scalar_one.return_value = 0

        call_count = 0

        async def _execute(stmt: Any) -> Any:
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return result_profile
            if call_count == 2:
                return result_sum
            if call_count == 3:
                return result_user
            return result_none

        session.execute = _execute

        svc = StatsService(session, _USER_ID)
        data = await svc.get_profile_stats()

        assert data["all_focus_seconds"] == 0
        assert data["days_in_app"] >= 1
        assert data["longest_streak"] == 0
        assert data["best_day"] is None
        assert data["best_week"] is None
        assert data["best_month"] is None


class TestStatsServiceWithData:
    @pytest.mark.asyncio
    async def test_single_session_fills_best_day(self):
        session = AsyncMock()

        profile_mock = MagicMock()
        profile_mock.longest_streak = 5

        result_profile = MagicMock()
        result_profile.scalar_one_or_none.return_value = profile_mock

        result_sum = MagicMock()
        result_sum.scalar_one.return_value = 60

        result_user = MagicMock()
        result_user.scalar_one_or_none.return_value = datetime(2026, 1, 1, tzinfo=timezone.utc)

        focus_date = date(2026, 4, 1)
        best_day_row = MagicMock()
        best_day_row.focus_date = focus_date
        best_day_row.total_credited_minutes = 60
        best_day_row.session_count = 1

        result_best_day = MagicMock()
        result_best_day.first.return_value = best_day_row

        best_week_row = MagicMock()
        best_week_row.week_start = date(2026, 3, 30)
        best_week_row.total_minutes = 60

        result_best_week = MagicMock()
        result_best_week.first.return_value = best_week_row

        per_day_row = MagicMock()
        per_day_row.focus_date = focus_date
        per_day_row.total_credited_minutes = 60

        result_per_day = MagicMock()
        result_per_day.all.return_value = [per_day_row]

        best_month_row = MagicMock()
        best_month_row.month_start = date(2026, 4, 1)
        best_month_row.total_minutes = 60

        result_best_month = MagicMock()
        result_best_month.first.return_value = best_month_row

        result_heatmap_days = MagicMock()
        result_heatmap_days.all.return_value = [per_day_row]

        call_count = 0

        async def _execute(stmt: Any) -> Any:
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return result_profile
            if call_count == 2:
                return result_sum
            if call_count == 3:
                return result_user
            if call_count == 4:
                return result_best_day
            if call_count == 5:
                return result_best_week
            if call_count == 6:
                return result_per_day
            if call_count == 7:
                return result_best_month
            return result_heatmap_days

        session.execute = _execute

        svc = StatsService(session, _USER_ID)
        data = await svc.get_profile_stats()

        assert data["all_focus_seconds"] == 60 * 60
        assert data["longest_streak"] == 5
        assert data["best_day"] is not None
        assert data["best_day"]["seconds"] == 60 * 60
        assert data["best_day"]["session_count"] == 1
        assert data["best_week"] is not None
        assert data["best_week"]["total_seconds"] == 60 * 60
        assert len(data["best_week"]["per_day"]) == 7
        assert data["best_month"] is not None
        assert data["best_month"]["month"] == "2026-04"
        assert len(data["best_month"]["heatmap"]) == 5
        assert all(len(row) == 7 for row in data["best_month"]["heatmap"])


# ── Router integration tests ──


class TestProfileStatsEndpoint:
    def test_returns_200_with_zeros_for_empty_user(self, monkeypatch: pytest.MonkeyPatch):
        async def _fake_get_stats(self_svc: Any) -> dict:
            return {
                "all_focus_seconds": 0,
                "days_in_app": 1,
                "longest_streak": 0,
                "best_day": None,
                "best_week": None,
                "best_month": None,
            }

        monkeypatch.setattr(StatsService, "get_profile_stats", _fake_get_stats)

        app = _make_app()
        client = TestClient(app)
        response = client.get("/api/v1/profile/stats")
        assert response.status_code == 200
        data = response.json()
        assert data["all_focus_seconds"] == 0
        assert data["days_in_app"] == 1
        assert data["longest_streak"] == 0
        assert data["best_day"] is None
        assert data["best_week"] is None
        assert data["best_month"] is None

    def test_returns_200_with_populated_data(self, monkeypatch: pytest.MonkeyPatch):
        async def _fake_get_stats(self_svc: Any) -> dict:
            return {
                "all_focus_seconds": 3600,
                "days_in_app": 30,
                "longest_streak": 10,
                "best_day": {
                    "date": date(2026, 4, 1),
                    "seconds": 3600,
                    "session_count": 2,
                },
                "best_week": {
                    "week_start": date(2026, 3, 30),
                    "total_seconds": 3600,
                    "per_day": [0, 3600, 0, 0, 0, 0, 0],
                },
                "best_month": {
                    "month": "2026-04",
                    "total_seconds": 3600,
                    "heatmap": [[0] * 7 for _ in range(5)],
                },
            }

        monkeypatch.setattr(StatsService, "get_profile_stats", _fake_get_stats)

        app = _make_app()
        client = TestClient(app)
        response = client.get("/api/v1/profile/stats")
        assert response.status_code == 200
        data = response.json()
        assert data["all_focus_seconds"] == 3600
        assert data["longest_streak"] == 10
        assert data["best_day"]["seconds"] == 3600
        assert data["best_week"]["per_day"] == [0, 3600, 0, 0, 0, 0, 0]
        assert data["best_month"]["month"] == "2026-04"
        assert len(data["best_month"]["heatmap"]) == 5


# ── Heatmap structure test ──


class TestHeatmapStructure:
    @pytest.mark.asyncio
    async def test_heatmap_is_5x7(self):
        """Heatmap must always be 5 rows x 7 columns regardless of month."""
        session = AsyncMock()

        profile_mock = MagicMock()
        profile_mock.longest_streak = 0

        result_profile = MagicMock()
        result_profile.scalar_one_or_none.return_value = profile_mock

        result_sum = MagicMock()
        result_sum.scalar_one.return_value = 60

        result_user = MagicMock()
        result_user.scalar_one_or_none.return_value = datetime(2026, 1, 1, tzinfo=timezone.utc)

        result_none = MagicMock()
        result_none.first.return_value = None

        best_month_row = MagicMock()
        best_month_row.month_start = date(2026, 4, 1)
        best_month_row.total_minutes = 60

        result_best_month = MagicMock()
        result_best_month.first.return_value = best_month_row

        result_heatmap_days = MagicMock()
        result_heatmap_days.all.return_value = []

        call_count = 0

        async def _execute(stmt: Any) -> Any:
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return result_profile
            if call_count == 2:
                return result_sum
            if call_count == 3:
                return result_user
            if call_count == 4:
                return result_none  # best_day
            if call_count == 5:
                return result_none  # best_week
            if call_count == 6:
                return result_best_month
            return result_heatmap_days

        session.execute = _execute

        svc = StatsService(session, _USER_ID)
        data = await svc.get_profile_stats()

        hm = data["best_month"]["heatmap"]
        assert len(hm) == 5
        for row in hm:
            assert len(row) == 7

    @pytest.mark.asyncio
    async def test_heatmap_6_week_month_folds_into_row_4(self):
        """May 2026: 1 May = Friday (ISO weekday 5).
        Grid anchor = Monday 27 Apr 2026.
        - 1 May (Fri) → row 0, col 4.
        - 31 May (Sun) → ISO week 6 relative to grid, clamped to row 4 via min(4, ...).
        All data from the 6th ISO week must appear in row 4, not overflow.
        """
        session = AsyncMock()

        profile_mock = MagicMock()
        profile_mock.longest_streak = 0

        result_profile = MagicMock()
        result_profile.scalar_one_or_none.return_value = profile_mock

        result_sum = MagicMock()
        result_sum.scalar_one.return_value = 120

        result_user = MagicMock()
        result_user.scalar_one_or_none.return_value = datetime(2026, 1, 1, tzinfo=timezone.utc)

        result_none = MagicMock()
        result_none.first.return_value = None

        best_month_row = MagicMock()
        best_month_row.month_start = date(2026, 5, 1)
        best_month_row.total_minutes = 120

        result_best_month = MagicMock()
        result_best_month.first.return_value = best_month_row

        # Provide data for 1 May and 31 May
        may1_row = MagicMock()
        may1_row.focus_date = date(2026, 5, 1)
        may1_row.total_credited_minutes = 60

        may31_row = MagicMock()
        may31_row.focus_date = date(2026, 5, 31)
        may31_row.total_credited_minutes = 60

        result_heatmap_days = MagicMock()
        result_heatmap_days.all.return_value = [may1_row, may31_row]

        call_count = 0

        async def _execute(stmt: Any) -> Any:
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return result_profile
            if call_count == 2:
                return result_sum
            if call_count == 3:
                return result_user
            if call_count == 4:
                return result_none  # best_day
            if call_count == 5:
                return result_none  # best_week
            if call_count == 6:
                return result_best_month
            return result_heatmap_days

        session.execute = _execute

        svc = StatsService(session, _USER_ID)
        data = await svc.get_profile_stats()

        hm = data["best_month"]["heatmap"]

        # Always 5×7
        assert len(hm) == 5
        for row in hm:
            assert len(row) == 7

        # 1 May 2026 is Friday (ISO weekday 5 → col index 4), row 0
        # grid_start = 27 Apr 2026 (Monday), (1 May - 27 Apr).days = 4, 4 // 7 = 0
        assert hm[0][4] == 60 * 60, "1 May should be at row 0, col 4"

        # 31 May 2026 is Sunday (ISO weekday 7 → col index 6)
        # grid_start = 27 Apr, (31 May - 27 Apr).days = 34, 34 // 7 = 4 → min(4,4) = row 4
        assert hm[4][6] == 60 * 60, "31 May should fold into row 4, col 6"
