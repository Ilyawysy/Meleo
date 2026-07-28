"""Tests for the settings feature:
- GamificationService.update_settings() with theme_mode
- deletion_service.delete_user_data() table coverage
- gamification router: ProfileUpdateRequest validation, theme_mode in response
- migration uu11: correct upgrade/downgrade ops
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from backend.domain.gamification.service import GamificationService


# ──────────────────── Helpers ────────────────────

USER_ID = uuid.uuid4()
DEFAULT_PLAN_JSON = '{"1":30,"2":0,"3":30,"4":0,"5":30,"6":0,"7":0}'


def make_profile(
    *,
    theme_mode: str = "system",
    minimal_mode: bool = False,
    home_tz: str = "UTC",
    home_tz_set_at=None,
    day_cutoff_hour: int = 4,
    day_cutoff_changed_at=None,
    plan_minutes_json: str = DEFAULT_PLAN_JSON,
    plan_changed_at=None,
    streak_current: int = 0,
    streak_finalized_through=None,
    recovery_days_remaining: int = 0,
    consecutive_missed_focus_days: int = 0,
    created_at: datetime | None = None,
) -> SimpleNamespace:
    return SimpleNamespace(
        user_id=USER_ID,
        xp=0,
        streak_current=streak_current,
        streak_finalized_through=streak_finalized_through,
        plan_minutes_json=plan_minutes_json,
        home_tz=home_tz,
        timezone=home_tz,
        day_cutoff_hour=day_cutoff_hour,
        recovery_days_remaining=recovery_days_remaining,
        consecutive_missed_focus_days=consecutive_missed_focus_days,
        minimal_mode=minimal_mode,
        theme_mode=theme_mode,
        shield_unlocked=False,
        shield_charges=0,
        shield_recharge_progress=0,
        coin_remainder=0.0,
        mmr=0,
        goal_minutes=60,
        scheduled_days_mask=31,
        fair_play_accepted=False,
        fair_play_accepted_at=None,
        home_tz_set_at=home_tz_set_at,
        day_cutoff_changed_at=day_cutoff_changed_at,
        plan_changed_at=plan_changed_at,
        created_at=created_at or datetime(2025, 1, 1, tzinfo=timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )


def make_service(profile: SimpleNamespace) -> tuple[GamificationService, AsyncMock]:
    gam_repo = AsyncMock()
    gam_repo.get_profile.return_value = profile
    gam_repo.update_profile.side_effect = lambda p: p

    focus_repo = AsyncMock()
    session = MagicMock()
    svc = GamificationService(gam_repo, focus_repo, session, USER_ID)
    return svc, gam_repo


# ──────────────────── update_settings: theme_mode ────────────────────


class TestUpdateSettingsThemeMode:
    @pytest.mark.asyncio
    async def test_set_theme_mode_light(self):
        profile = make_profile(theme_mode="system")
        svc, repo = make_service(profile)

        result = await svc.update_settings(theme_mode="light")

        assert result.theme_mode == "light"
        repo.update_profile.assert_called_once()

    @pytest.mark.asyncio
    async def test_set_theme_mode_dark(self):
        profile = make_profile(theme_mode="system")
        svc, repo = make_service(profile)

        result = await svc.update_settings(theme_mode="dark")

        assert result.theme_mode == "dark"

    @pytest.mark.asyncio
    async def test_set_theme_mode_system(self):
        profile = make_profile(theme_mode="dark")
        svc, repo = make_service(profile)

        result = await svc.update_settings(theme_mode="system")

        assert result.theme_mode == "system"

    @pytest.mark.asyncio
    async def test_invalid_theme_mode_raises_value_error(self):
        profile = make_profile()
        svc, _ = make_service(profile)

        with pytest.raises(ValueError, match="theme_mode must be one of"):
            await svc.update_settings(theme_mode="invalid")

    @pytest.mark.asyncio
    async def test_invalid_theme_mode_amoled_raises(self):
        profile = make_profile()
        svc, _ = make_service(profile)

        with pytest.raises(ValueError, match="theme_mode must be one of"):
            await svc.update_settings(theme_mode="amoled")

    @pytest.mark.asyncio
    async def test_none_theme_mode_does_not_modify_profile(self):
        profile = make_profile(theme_mode="dark")
        svc, repo = make_service(profile)

        result = await svc.update_settings(theme_mode=None)

        assert result.theme_mode == "dark"

    @pytest.mark.asyncio
    async def test_theme_mode_does_not_affect_minimal_mode(self):
        profile = make_profile(theme_mode="system", minimal_mode=False)
        svc, _ = make_service(profile)

        result = await svc.update_settings(theme_mode="dark")

        assert result.minimal_mode is False

    @pytest.mark.asyncio
    async def test_update_both_theme_and_minimal_mode(self):
        profile = make_profile(theme_mode="system", minimal_mode=False)
        # Give streak_finalized_through so reset branch runs
        profile.streak_finalized_through = None
        svc, _ = make_service(profile)

        result = await svc.update_settings(theme_mode="light", minimal_mode=True)

        assert result.theme_mode == "light"
        assert result.minimal_mode is True


# ──────────────────── update_settings: minimal_mode side-effects ────────────────────


class TestUpdateSettingsMinimalMode:
    @pytest.mark.asyncio
    async def test_disable_minimal_mode_resets_streak_state(self):
        profile = make_profile(
            minimal_mode=True,
            recovery_days_remaining=5,
            consecutive_missed_focus_days=3,
        )
        svc, _ = make_service(profile)

        result = await svc.update_settings(minimal_mode=False)

        assert result.minimal_mode is False
        assert result.recovery_days_remaining == 0
        assert result.consecutive_missed_focus_days == 0

    @pytest.mark.asyncio
    async def test_enable_minimal_mode_does_not_reset_streak_state(self):
        profile = make_profile(
            minimal_mode=False,
            recovery_days_remaining=5,
            consecutive_missed_focus_days=3,
        )
        svc, _ = make_service(profile)

        result = await svc.update_settings(minimal_mode=True)

        assert result.minimal_mode is True
        # Recovery state is NOT reset when enabling minimal mode
        assert result.recovery_days_remaining == 5
        assert result.consecutive_missed_focus_days == 3


# ──────────────────── update_settings: plan_minutes validation ────────────────────


class TestUpdateSettingsPlanMinutes:
    @pytest.mark.asyncio
    async def test_plan_minutes_all_zero_raises(self):
        profile = make_profile()
        svc, _ = make_service(profile)

        with pytest.raises(ValueError, match="at least one day"):
            await svc.update_settings(plan_minutes={1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0})

    @pytest.mark.asyncio
    async def test_plan_minutes_value_not_multiple_of_10_raises(self):
        profile = make_profile()
        svc, _ = make_service(profile)

        with pytest.raises(ValueError, match="steps of 10"):
            await svc.update_settings(plan_minutes={1: 25})

    @pytest.mark.asyncio
    async def test_plan_minutes_value_exceeds_480_raises(self):
        profile = make_profile()
        svc, _ = make_service(profile)

        with pytest.raises(ValueError, match="0-480"):
            await svc.update_settings(plan_minutes={1: 490})

    @pytest.mark.asyncio
    async def test_plan_minutes_valid_saves(self):
        profile = make_profile()
        svc, _ = make_service(profile)

        result = await svc.update_settings(plan_minutes={1: 30, 2: 0, 3: 60})

        saved = json.loads(result.plan_minutes_json)
        assert saved["1"] == 30
        assert saved["3"] == 60


# ──────────────────── Router DTO: ProfileUpdateRequest validation ────────────────────


class TestProfileUpdateRequestValidation:
    def test_valid_theme_modes_accepted(self):
        from backend.apps.api.routers.gamification import ProfileUpdateRequest

        for mode in ("light", "dark", "system"):
            req = ProfileUpdateRequest(theme_mode=mode)
            assert req.theme_mode == mode

    def test_none_theme_mode_accepted(self):
        from backend.apps.api.routers.gamification import ProfileUpdateRequest

        req = ProfileUpdateRequest(theme_mode=None)
        assert req.theme_mode is None

    def test_plan_minutes_invalid_key_rejected(self):
        from pydantic import ValidationError

        from backend.apps.api.routers.gamification import ProfileUpdateRequest

        with pytest.raises(ValidationError):
            ProfileUpdateRequest(plan_minutes={"8": 30})

    def test_plan_minutes_invalid_value_not_multiple_of_10_rejected(self):
        from pydantic import ValidationError

        from backend.apps.api.routers.gamification import ProfileUpdateRequest

        with pytest.raises(ValidationError):
            ProfileUpdateRequest(plan_minutes={"1": 25})

    def test_day_cutoff_hour_out_of_range_rejected(self):
        from pydantic import ValidationError

        from backend.apps.api.routers.gamification import ProfileUpdateRequest

        with pytest.raises(ValidationError):
            ProfileUpdateRequest(day_cutoff_hour=13)


# ──────────────────── Router DTO: GamificationProfileOut ────────────────────


class TestGamificationProfileOut:
    def test_theme_mode_field_defaults_to_system(self):
        from backend.apps.api.routers.gamification import GamificationProfileOut

        out = GamificationProfileOut(
            xp=0,
            level=1,
            xp_to_next_level=100,
            streak_current=0,
            plan_minutes={1: 30},
            home_tz="UTC",
            day_cutoff_hour=4,
            recovery_days_remaining=0,
            minimal_mode=False,
            coins=0.0,
        )
        assert out.theme_mode == "system"

    def test_theme_mode_field_set_to_dark(self):
        from backend.apps.api.routers.gamification import GamificationProfileOut

        out = GamificationProfileOut(
            xp=0,
            level=1,
            xp_to_next_level=100,
            streak_current=0,
            plan_minutes={1: 30},
            home_tz="UTC",
            day_cutoff_hour=4,
            recovery_days_remaining=0,
            minimal_mode=False,
            coins=0.0,
            theme_mode="dark",
        )
        assert out.theme_mode == "dark"


# ──────────────────── deletion_service: table coverage ────────────────────


class TestDeleteUserDataTableCoverage:
    """Verify all expected tables are deleted in the correct FK-safe order."""

    @pytest.mark.asyncio
    async def test_all_expected_tables_deleted(self):
        from backend.domain.users.deletion_service import delete_user_data

        executed_sqls: list[str] = []

        class FakeSession:
            async def execute(self, stmt, params=None):
                # Capture the SQL text
                executed_sqls.append(str(stmt))

        await delete_user_data(FakeSession(), USER_ID)

        combined = " ".join(executed_sqls)
        expected_tables = [
            "focus_task_segments",
            "gamification_events",
            "daily_focus_aggregate",
            "user_gamification_profile",
            "user_shop_items",
            "user_balance",
            "focus_sessions",
            "checklist_items",
            "tasks",
            "chat_messages",
            "chat_threads",
            "notifications",
            "user_announcement_reads",
            "user_state_version",
            "idempotency_keys",
            "users",
        ]
        for table in expected_tables:
            assert table in combined, f"Table '{table}' not found in executed DELETE statements"

    @pytest.mark.asyncio
    async def test_focus_task_segments_deleted_before_focus_sessions(self):
        """FK constraint: segments reference sessions, so must be deleted first."""
        from backend.domain.users.deletion_service import delete_user_data

        delete_order: list[str] = []

        class FakeSession:
            async def execute(self, stmt, params=None):
                delete_order.append(str(stmt))

        await delete_user_data(FakeSession(), USER_ID)

        segments_idx = next(
            (i for i, s in enumerate(delete_order) if "DELETE FROM focus_task_segments" in s), -1
        )
        # Search for "DELETE FROM focus_sessions" to avoid matching the subquery
        # in the focus_task_segments delete ("SELECT id FROM focus_sessions WHERE ...")
        sessions_idx = next(
            (i for i, s in enumerate(delete_order) if "DELETE FROM focus_sessions" in s), -1
        )
        assert segments_idx < sessions_idx, (
            "focus_task_segments must be deleted before focus_sessions due to FK constraint"
        )

    @pytest.mark.asyncio
    async def test_users_deleted_last(self):
        """users table must be deleted after all referencing tables."""
        from backend.domain.users.deletion_service import delete_user_data

        delete_order: list[str] = []

        class FakeSession:
            async def execute(self, stmt, params=None):
                delete_order.append(str(stmt))

        await delete_user_data(FakeSession(), USER_ID)

        assert "users" in delete_order[-1], "users table must be the last DELETE"


# ──────────────────── Migration uu11 structural checks ────────────────────


class TestMigrationUu11:
    """Validate the migration file structure without actually running Alembic."""

    def test_revision_chain_is_correct(self):
        from backend.alembic.versions import uu11_add_theme_mode_to_user_gamification_profile as m

        assert m.revision == "uu11"
        assert m.down_revision == "tt11"

    def test_upgrade_adds_theme_mode_column(self):
        """upgrade() should call add_column on user_gamification_profile."""
        ops: list[tuple[str, str]] = []

        class FakeOp:
            @staticmethod
            def add_column(table, col):
                ops.append(("add_column", table, str(col.name)))

            @staticmethod
            def drop_column(table, col_name):
                ops.append(("drop_column", table, col_name))

        import backend.alembic.versions.uu11_add_theme_mode_to_user_gamification_profile as m

        original_op = m.op
        m.op = FakeOp()
        try:
            m.upgrade()
        finally:
            m.op = original_op

        assert any(
            op[0] == "add_column" and op[1] == "user_gamification_profile" and op[2] == "theme_mode"
            for op in ops
        ), f"Expected add_column('user_gamification_profile', 'theme_mode'), got: {ops}"

    def test_downgrade_drops_theme_mode_column(self):
        """downgrade() should call drop_column on user_gamification_profile."""
        ops: list[tuple] = []

        class FakeOp:
            @staticmethod
            def add_column(table, col):
                ops.append(("add_column", table))

            @staticmethod
            def drop_column(table, col_name):
                ops.append(("drop_column", table, col_name))

        import backend.alembic.versions.uu11_add_theme_mode_to_user_gamification_profile as m

        original_op = m.op
        m.op = FakeOp()
        try:
            m.downgrade()
        finally:
            m.op = original_op

        assert any(
            op[0] == "drop_column"
            and op[1] == "user_gamification_profile"
            and op[2] == "theme_mode"
            for op in ops
        ), f"Expected drop_column('user_gamification_profile', 'theme_mode'), got: {ops}"


# ──────────────────── auth.py: delete_account authentication ────────────────────


class TestDeleteAccountAuthentication:
    """Verify the delete_account endpoint uses get_current_user_id dependency."""

    def test_delete_account_has_user_id_dependency(self):
        """The endpoint signature must include user_id: uuid.UUID = Depends(get_current_user_id)."""
        import inspect

        from backend.apps.api.routers.auth import delete_account
        from backend.infrastructure.security.auth import get_current_user_id

        sig = inspect.signature(delete_account)
        params = sig.parameters

        assert "user_id" in params, "delete_account must have a user_id parameter"
        default = params["user_id"].default
        # FastAPI Depends wraps the callable
        assert hasattr(default, "dependency"), "user_id must use Depends()"
        assert default.dependency is get_current_user_id
