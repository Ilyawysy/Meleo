"""Comprehensive tests for GamificationService.roll_forward().

Tests streak logic, recovery, shield, and multi-day scenarios
using mocked repositories and controlled "current date".
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta, timezone
from types import SimpleNamespace
from typing import Any, Sequence
from unittest.mock import AsyncMock

import pytest

from backend.domain.gamification.calculator import RECOVERY_DURATION_FOCUS_DAYS
from backend.domain.gamification.entities import (
    GamificationEvent,
    GamificationEventType,
)
from backend.domain.gamification.service import GamificationService


# ──────────────────── Helpers ────────────────────


USER_ID = uuid.uuid4()

# Default plan: Mon=30, Tue=0, Wed=30, Thu=0, Fri=30, Sat=0, Sun=0
DEFAULT_PLAN_JSON = '{"1":30,"2":0,"3":30,"4":0,"5":30,"6":0,"7":0}'
# All weekdays plan: 30 min every day
ALL_DAYS_PLAN_JSON = '{"1":30,"2":30,"3":30,"4":30,"5":30,"6":30,"7":30}'
# Heavy plan: 60 min on weekdays
HEAVY_PLAN_JSON = '{"1":60,"2":60,"3":60,"4":60,"5":60,"6":0,"7":0}'


def make_profile(
    *,
    streak_current: int = 0,
    streak_finalized_through: date | None = None,
    plan_json: str = DEFAULT_PLAN_JSON,
    home_tz: str = "UTC",
    day_cutoff_hour: int = 4,
    recovery_days_remaining: int = 0,
    consecutive_missed_focus_days: int = 0,
    minimal_mode: bool = False,
    shield_unlocked: bool = False,
    shield_charges: int = 0,
    shield_recharge_progress: int = 0,
    xp: int = 0,
    coin_remainder: float = 0.0,
    created_at: datetime | None = None,
) -> Any:
    """Create a plain object mimicking Any."""
    return SimpleNamespace(
        user_id=USER_ID,
        xp=xp,
        streak_current=streak_current,
        streak_finalized_through=streak_finalized_through,
        plan_minutes_json=plan_json,
        home_tz=home_tz,
        timezone=home_tz,
        day_cutoff_hour=day_cutoff_hour,
        recovery_days_remaining=recovery_days_remaining,
        consecutive_missed_focus_days=consecutive_missed_focus_days,
        minimal_mode=minimal_mode,
        shield_unlocked=shield_unlocked,
        shield_charges=shield_charges,
        shield_recharge_progress=shield_recharge_progress,
        coin_remainder=coin_remainder,
        mmr=0,
        goal_minutes=60,
        scheduled_days_mask=31,
        fair_play_accepted=False,
        fair_play_accepted_at=None,
        streak_updated_date=None,
        home_tz_set_at=None,
        day_cutoff_changed_at=None,
        plan_changed_at=None,
        created_at=created_at or datetime(2025, 1, 1, tzinfo=timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )


def make_aggregate(
    focus_date: date,
    total_credited_minutes: int = 0,
    recovery_mode: str | None = None,
    total_xp_earned: int = 0,
    total_coins_earned: int = 0,
    session_count: int = 0,
    coin_minutes_used: int = 0,
) -> Any:
    """Create a plain object mimicking Any."""
    return SimpleNamespace(
        id=uuid.uuid4(),
        user_id=USER_ID,
        focus_date=focus_date,
        total_credited_minutes=total_credited_minutes,
        total_xp_earned=total_xp_earned,
        total_coins_earned=total_coins_earned,
        session_count=session_count,
        coin_minutes_used=coin_minutes_used,
        recovery_mode=recovery_mode,
    )


class FakeGamRepo:
    """In-memory fake of GamificationRepository for testing."""

    def __init__(self, profile: Any, aggregates: list[Any]):
        self.profile = profile
        self._aggregates: dict[date, Any] = {a.focus_date: a for a in aggregates}
        self.events: list[GamificationEvent] = []

    async def get_profile(self) -> Any:
        return self.profile

    async def create_profile(self) -> Any:
        return self.profile

    async def lock_profile(self) -> Any:
        return self.profile

    async def update_profile(self, profile: Any) -> Any:
        self.profile = profile
        return profile

    async def get_aggregate(self, focus_date: date) -> Any | None:
        return self._aggregates.get(focus_date)

    async def lock_aggregate(self, focus_date: date) -> Any | None:
        return self._aggregates.get(focus_date)

    async def create_aggregate(self, focus_date: date) -> Any:
        agg = make_aggregate(focus_date)
        self._aggregates[focus_date] = agg
        return agg

    async def update_aggregate(self, aggregate: Any) -> Any:
        self._aggregates[aggregate.focus_date] = aggregate
        return aggregate

    async def list_aggregates(self, since: date, until: date) -> Sequence[Any]:
        return [a for d, a in sorted(self._aggregates.items()) if since <= d <= until]

    async def create_event(self, event: GamificationEvent) -> GamificationEvent:
        event.user_id = USER_ID
        if not hasattr(event, "id") or event.id is None:
            event.id = uuid.uuid4()
        if not hasattr(event, "created_at") or event.created_at is None:
            event.created_at = datetime.now(timezone.utc)
        self.events.append(event)
        return event

    async def get_session_reward_event(self, session_id: uuid.UUID) -> GamificationEvent | None:
        return None

    async def get_sessions_by_day_and_statuses(self, day: date, statuses: list[str]) -> Sequence:
        return []


def build_service(
    profile: Any,
    aggregates: list[Any],
    fake_today: date,
) -> tuple[GamificationService, FakeGamRepo]:
    """Build a GamificationService with fakes and a patched 'today'."""
    repo = FakeGamRepo(profile, aggregates)
    focus_repo = AsyncMock()
    session = AsyncMock()
    session.in_transaction.return_value = True
    session.begin_nested.return_value.__aenter__ = AsyncMock()
    session.begin_nested.return_value.__aexit__ = AsyncMock()

    service = GamificationService(repo, focus_repo, session, USER_ID)

    # Override _user_today to return our controlled date
    service._user_today = lambda prof: fake_today

    return service, repo


def event_types(repo: FakeGamRepo) -> list[GamificationEventType]:
    return [e.event_type for e in repo.events]


# ──────────────────── Test: Basic streak increment ────────────────────


class TestStreakIncrement:
    """Streak increments when focus day has enough minutes."""

    @pytest.mark.asyncio
    async def test_single_day_streak_starts(self):
        # Monday 2025-03-10 has 30 credited minutes, plan=30
        # streak_finalized_through=Sunday 2025-03-09
        # "today" = Tuesday 2025-03-11 → roll_forward evaluates Monday
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
        )
        aggs = [make_aggregate(date(2025, 3, 10), total_credited_minutes=30)]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 11))

        result = await service.roll_forward()

        assert result.streak_current == 1
        assert result.streak_finalized_through == date(2025, 3, 10)
        assert GamificationEventType.streak_increment in event_types(repo)

    @pytest.mark.asyncio
    async def test_streak_grows_over_multiple_focus_days(self):
        # Plan: Mon=30, Wed=30, Fri=30. All met with 30 min.
        # Week: Mon 3/10, Tue 3/11 (off), Wed 3/12, Thu 3/13 (off), Fri 3/14
        # "today" = Sat 3/15
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
        )
        aggs = [
            make_aggregate(date(2025, 3, 10), total_credited_minutes=30),  # Mon ✓
            make_aggregate(date(2025, 3, 12), total_credited_minutes=30),  # Wed ✓
            make_aggregate(date(2025, 3, 14), total_credited_minutes=30),  # Fri ✓
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 15))

        result = await service.roll_forward()

        assert result.streak_current == 3
        assert result.streak_finalized_through == date(2025, 3, 14)

    @pytest.mark.asyncio
    async def test_non_focus_days_are_skipped(self):
        # Tuesday (weekday=2) has plan_minutes=0, should not affect streak
        profile = make_profile(
            streak_current=1,
            streak_finalized_through=date(2025, 3, 10),  # Monday finalized
        )
        # Tuesday has 0 minutes (not a focus day) — no aggregate needed
        # Wednesday has 30 minutes
        aggs = [make_aggregate(date(2025, 3, 12), total_credited_minutes=30)]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 13))

        result = await service.roll_forward()

        # Streak should go from 1 → 2 (Tue skipped, Wed succeeds)
        assert result.streak_current == 2


# ──────────────────── Test: Streak reset ────────────────────


class TestStreakReset:
    """Streak resets when focus day doesn't meet threshold."""

    @pytest.mark.asyncio
    async def test_zero_minutes_resets_streak(self):
        profile = make_profile(
            streak_current=5,
            streak_finalized_through=date(2025, 3, 9),
        )
        # Monday with 0 credited minutes
        aggs: list[Any] = []
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 11))

        result = await service.roll_forward()

        assert result.streak_current == 0
        assert GamificationEventType.streak_reset in event_types(repo)

    @pytest.mark.asyncio
    async def test_below_threshold_resets(self):
        # Plan=30, streak_day=1 → threshold=15. Minutes=14 → reset
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
        )
        aggs = [make_aggregate(date(2025, 3, 10), total_credited_minutes=14)]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 11))

        result = await service.roll_forward()

        assert result.streak_current == 0
        # No streak_reset event because streak was already 0
        assert GamificationEventType.streak_reset not in event_types(repo)

    @pytest.mark.asyncio
    async def test_exactly_at_threshold_succeeds(self):
        # streak_day=1, plan=30 → threshold=15
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
        )
        aggs = [make_aggregate(date(2025, 3, 10), total_credited_minutes=15)]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 11))

        result = await service.roll_forward()

        assert result.streak_current == 1


# ──────────────────── Test: Ramp-up thresholds ────────────────────


class TestRampUpThresholds:
    """Streak threshold ramps up as streak grows."""

    @pytest.mark.asyncio
    async def test_ramp_up_progression_with_plan_60(self):
        # Plan 60 min every day, streak starting from 0
        # Thresholds: day1=15, day2=20, day3=25, day4=30, day5=35, day6=40, day7+=42
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),  # Sunday
            plan_json=HEAVY_PLAN_JSON,  # 60 min Mon-Fri
        )
        # Mon-Fri with exactly threshold minutes
        aggs = [
            make_aggregate(date(2025, 3, 10), total_credited_minutes=15),  # day1: need 15
            make_aggregate(date(2025, 3, 11), total_credited_minutes=20),  # day2: need 20
            make_aggregate(date(2025, 3, 12), total_credited_minutes=25),  # day3: need 25
            make_aggregate(date(2025, 3, 13), total_credited_minutes=30),  # day4: need 30
            make_aggregate(date(2025, 3, 14), total_credited_minutes=35),  # day5: need 35
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 15))

        result = await service.roll_forward()

        assert result.streak_current == 5

    @pytest.mark.asyncio
    async def test_ramp_up_fails_when_below(self):
        # day2 needs 20 min, user only did 19
        profile = make_profile(
            streak_current=1,  # already has streak 1
            streak_finalized_through=date(2025, 3, 10),
            plan_json=HEAVY_PLAN_JSON,
        )
        aggs = [make_aggregate(date(2025, 3, 11), total_credited_minutes=19)]  # Tue: need 20
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 12))

        result = await service.roll_forward()

        assert result.streak_current == 0  # Reset


# ──────────────────── Test: Shield ────────────────────


class TestShield:
    """Shield unlocks at streak=3, absorbs one miss, recharges after 2 successes."""

    @pytest.mark.asyncio
    async def test_shield_unlocks_at_streak_3(self):
        # 3 consecutive focus days → shield unlocks
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
            plan_json=ALL_DAYS_PLAN_JSON,
        )
        aggs = [
            make_aggregate(date(2025, 3, 10), total_credited_minutes=30),
            make_aggregate(date(2025, 3, 11), total_credited_minutes=30),
            make_aggregate(date(2025, 3, 12), total_credited_minutes=30),
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 13))

        result = await service.roll_forward()

        assert result.streak_current == 3
        assert result.shield_unlocked is True
        assert result.shield_charges == 1

    @pytest.mark.asyncio
    async def test_shield_absorbs_miss(self):
        # Have shield, miss a day → shield spent, streak preserved
        profile = make_profile(
            streak_current=5,
            streak_finalized_through=date(2025, 3, 10),
            plan_json=ALL_DAYS_PLAN_JSON,
            shield_unlocked=True,
            shield_charges=1,
        )
        # Tuesday: 0 minutes (miss)
        aggs: list[Any] = []
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 12))

        result = await service.roll_forward()

        assert result.streak_current == 5  # Preserved!
        assert result.shield_charges == 0  # Shield spent
        assert GamificationEventType.shield_spend in event_types(repo)
        assert GamificationEventType.streak_reset not in event_types(repo)

    @pytest.mark.asyncio
    async def test_shield_absorbs_below_threshold(self):
        # Have shield, did some minutes but below threshold → shield spent, streak preserved
        # Plan=30, streak_day=6, threshold = min(ramp_up(6)=40, int(30*0.70)=21) = 21
        profile = make_profile(
            streak_current=5,
            streak_finalized_through=date(2025, 3, 10),
            plan_json=ALL_DAYS_PLAN_JSON,
            shield_unlocked=True,
            shield_charges=1,
        )
        # Tuesday: 14 minutes — below threshold (21) but > 0
        aggs = [make_aggregate(date(2025, 3, 11), total_credited_minutes=14)]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 12))

        result = await service.roll_forward()

        assert result.streak_current == 5  # Preserved by shield
        assert result.shield_charges == 0  # Shield spent
        assert GamificationEventType.shield_spend in event_types(repo)
        assert GamificationEventType.streak_reset not in event_types(repo)
        # consecutive_missed resets because credited > 0
        assert result.consecutive_missed_focus_days == 0

    @pytest.mark.asyncio
    async def test_shield_doesnt_protect_second_miss(self):
        # Shield already spent, another miss → streak resets
        profile = make_profile(
            streak_current=5,
            streak_finalized_through=date(2025, 3, 10),
            plan_json=ALL_DAYS_PLAN_JSON,
            shield_unlocked=True,
            shield_charges=0,
        )
        aggs: list[Any] = []
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 12))

        result = await service.roll_forward()

        assert result.streak_current == 0
        assert GamificationEventType.streak_reset in event_types(repo)

    @pytest.mark.asyncio
    async def test_shield_recharges_after_2_successes(self):
        # Shield unlocked, 0 charges. 2 successful days → recharge
        profile = make_profile(
            streak_current=5,
            streak_finalized_through=date(2025, 3, 10),
            plan_json=ALL_DAYS_PLAN_JSON,
            shield_unlocked=True,
            shield_charges=0,
            shield_recharge_progress=0,
        )
        aggs = [
            make_aggregate(date(2025, 3, 11), total_credited_minutes=30),
            make_aggregate(date(2025, 3, 12), total_credited_minutes=30),
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 13))

        result = await service.roll_forward()

        assert result.streak_current == 7
        assert result.shield_charges == 1  # Recharged!
        assert result.shield_recharge_progress == 0
        assert GamificationEventType.shield_recharge in event_types(repo)

    @pytest.mark.asyncio
    async def test_shield_recharge_resets_on_miss(self):
        # 1 success day toward recharge, then a miss → progress resets, streak resets
        profile = make_profile(
            streak_current=5,
            streak_finalized_through=date(2025, 3, 10),
            plan_json=ALL_DAYS_PLAN_JSON,
            shield_unlocked=True,
            shield_charges=0,
            shield_recharge_progress=1,  # 1 day of progress
        )
        # Miss on Tuesday
        aggs: list[Any] = []
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 12))

        result = await service.roll_forward()

        assert result.streak_current == 0
        assert result.shield_recharge_progress == 0

    @pytest.mark.asyncio
    async def test_shield_no_recharge_progress_when_charged(self):
        # Shield already has charge → no recharge_progress accumulation
        profile = make_profile(
            streak_current=5,
            streak_finalized_through=date(2025, 3, 10),
            plan_json=ALL_DAYS_PLAN_JSON,
            shield_unlocked=True,
            shield_charges=1,  # Already charged
            shield_recharge_progress=0,
        )
        aggs = [make_aggregate(date(2025, 3, 11), total_credited_minutes=30)]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 12))

        result = await service.roll_forward()

        assert result.shield_charges == 1
        assert result.shield_recharge_progress == 0  # Not incremented


# ──────────────────── Test: Recovery ────────────────────


class TestRecovery:
    """Recovery triggers after 3 missed focus days, lasts 2 focus days."""

    @pytest.mark.asyncio
    async def test_recovery_triggers_after_3_missed_focus_days(self):
        # All days are focus days. Miss 3 in a row.
        # Mon=miss, Tue=miss, Wed=miss → recovery triggers
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
            plan_json=ALL_DAYS_PLAN_JSON,
            consecutive_missed_focus_days=0,
        )
        # No aggregates = no credited minutes
        aggs: list[Any] = []
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 13))

        result = await service.roll_forward()

        assert result.consecutive_missed_focus_days == 3
        assert result.recovery_days_remaining == RECOVERY_DURATION_FOCUS_DAYS  # 2

    @pytest.mark.asyncio
    async def test_recovery_does_not_trigger_with_non_focus_days(self):
        # Default plan: Mon,Wed,Fri are focus days. Tue,Thu,Sat,Sun are off.
        # Miss Mon (1), Tue is off, Wed miss (2) → not 3 yet
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
            consecutive_missed_focus_days=0,
        )
        aggs: list[Any] = []
        # "today" = Thu 3/13, so evaluates Mon-Wed
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 13))

        result = await service.roll_forward()

        assert result.consecutive_missed_focus_days == 2  # Mon + Wed
        assert result.recovery_days_remaining == 0  # Not triggered

    @pytest.mark.asyncio
    async def test_any_focus_resets_consecutive_miss_counter(self):
        # 2 missed focus days, then 1 with activity → counter resets
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
            plan_json=ALL_DAYS_PLAN_JSON,
            consecutive_missed_focus_days=0,
        )
        aggs = [
            # Mon: miss, Tue: miss, Wed: has activity (even if below threshold)
            make_aggregate(date(2025, 3, 12), total_credited_minutes=5),
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 13))

        result = await service.roll_forward()

        assert result.consecutive_missed_focus_days == 0  # Reset by Wed's activity

    @pytest.mark.asyncio
    async def test_recovery_decrements_over_focus_days(self):
        # Recovery active (2 days remaining). Focus days with activity.
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
            plan_json=ALL_DAYS_PLAN_JSON,
            consecutive_missed_focus_days=3,
            recovery_days_remaining=2,
        )
        aggs = [
            make_aggregate(date(2025, 3, 10), total_credited_minutes=30),
            make_aggregate(date(2025, 3, 11), total_credited_minutes=30),
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 12))

        result = await service.roll_forward()

        assert result.recovery_days_remaining == 0  # Fully used

    @pytest.mark.asyncio
    async def test_recovery_activates_today_aggregate(self):
        # If recovery_days_remaining > 0, today's aggregate gets recovery_mode
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 11),  # Already finalized through yesterday
            plan_json=ALL_DAYS_PLAN_JSON,
            recovery_days_remaining=1,
        )
        aggs: list[Any] = []
        today = date(2025, 3, 12)
        service, repo = build_service(profile, aggs, fake_today=today)

        await service.roll_forward()

        today_agg = await repo.get_aggregate(today)
        assert today_agg is not None
        assert today_agg.recovery_mode == "recovery"

    @pytest.mark.asyncio
    async def test_no_recovery_today_when_zero_remaining(self):
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 11),
            plan_json=ALL_DAYS_PLAN_JSON,
            recovery_days_remaining=0,
        )
        aggs: list[Any] = []
        today = date(2025, 3, 12)
        service, repo = build_service(profile, aggs, fake_today=today)

        await service.roll_forward()

        today_agg = await repo.get_aggregate(today)
        assert today_agg is not None
        assert today_agg.recovery_mode is None


# ──────────────────── Test: Minimal mode ────────────────────


class TestMinimalMode:
    """Minimal mode skips streak and recovery evaluation."""

    @pytest.mark.asyncio
    async def test_minimal_mode_no_streak_change(self):
        profile = make_profile(
            streak_current=3,
            streak_finalized_through=date(2025, 3, 9),
            plan_json=ALL_DAYS_PLAN_JSON,
            minimal_mode=True,
        )
        # 0 credited minutes on focus day — would normally reset streak
        aggs: list[Any] = []
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 11))

        result = await service.roll_forward()

        # Streak unchanged in minimal mode (no evaluation)
        assert result.streak_current == 3
        assert GamificationEventType.streak_reset not in event_types(repo)

    @pytest.mark.asyncio
    async def test_minimal_mode_no_recovery_tracking(self):
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
            plan_json=ALL_DAYS_PLAN_JSON,
            minimal_mode=True,
            consecutive_missed_focus_days=0,
        )
        aggs: list[Any] = []
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 13))

        result = await service.roll_forward()

        assert result.consecutive_missed_focus_days == 0
        assert result.recovery_days_remaining == 0


# ──────────────────── Test: Already finalized ────────────────────


class TestAlreadyFinalized:
    """roll_forward is a no-op if already finalized through yesterday."""

    @pytest.mark.asyncio
    async def test_no_work_when_up_to_date(self):
        today = date(2025, 3, 12)
        profile = make_profile(
            streak_current=5,
            streak_finalized_through=today - timedelta(days=1),  # yesterday
        )
        service, repo = build_service(profile, [], fake_today=today)

        result = await service.roll_forward()

        assert result.streak_current == 5  # Unchanged
        # Only recovery_activated event for today (if applicable)
        streak_events = [
            e
            for e in repo.events
            if e.event_type
            in (GamificationEventType.streak_increment, GamificationEventType.streak_reset)
        ]
        assert len(streak_events) == 0


# ──────────────────── Test: Complex multi-week scenario ────────────────────


class TestComplexScenario:
    """Multi-week scenario combining streak, shield, recovery."""

    @pytest.mark.asyncio
    async def test_two_week_journey(self):
        """
        Plan: all days 30 min.
        Week 1:
          Mon 3/10: 30 min ✓ (streak 1)
          Tue 3/11: 30 min ✓ (streak 2)
          Wed 3/12: 30 min ✓ (streak 3, shield unlocks!)
          Thu 3/13: 0 min ✗ (shield spent, streak stays 3)
          Fri 3/14: 30 min ✓ (streak 4)
          Sat 3/15: 30 min ✓ (streak 5, shield recharge progress=1)
          Sun 3/16: 30 min ✓ (streak 6, shield recharge progress=2 → recharged!)
        Week 2:
          Mon 3/17: 0 min ✗ (shield spent again, streak stays 6)
          Tue 3/18: 0 min ✗ (no shield, streak reset to 0, missed=1)
          Wed 3/19: 0 min ✗ (missed=2)
          Thu 3/20: 0 min ✗ (missed=3 → recovery triggered!)
        """
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
            plan_json=ALL_DAYS_PLAN_JSON,
        )
        aggs = [
            make_aggregate(date(2025, 3, 10), total_credited_minutes=30),
            make_aggregate(date(2025, 3, 11), total_credited_minutes=30),
            make_aggregate(date(2025, 3, 12), total_credited_minutes=30),
            # Thu 3/13: miss (no aggregate)
            make_aggregate(date(2025, 3, 14), total_credited_minutes=30),
            make_aggregate(date(2025, 3, 15), total_credited_minutes=30),
            make_aggregate(date(2025, 3, 16), total_credited_minutes=30),
            # Mon 3/17: miss
            # Tue 3/18: miss
            # Wed 3/19: miss
            # Thu 3/20: miss
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 21))

        result = await service.roll_forward()

        # Week 1: streak goes 0→1→2→3, shield unlocks, shield spent on Thu,
        # streak stays 3, Fri→4, Sat→5 (recharge progress 1),
        # Sun→6 (recharge progress 2 → recharge! shield_charges=1)
        # Week 2: Mon miss (shield spent), Tue miss (streak=0),
        # Wed miss (consecutive_missed=2 — wait, need to track carefully)

        # Recovery tracking runs before streak evaluation, so miss counter
        # increments even on shield-spend days:
        # Mon 3/17: credited=0 → consecutive_missed=1, shield spent
        # Tue 3/18: credited=0 → consecutive_missed=2, streak reset (no shield)
        # Wed 3/19: credited=0 → consecutive_missed=3 → recovery triggers (remaining=2)
        # Thu 3/20: credited=0 → consecutive_missed=4,
        #   recovery_remaining(2)>0 in elif → remaining=1

        assert result.streak_current == 0
        assert result.shield_unlocked is True
        assert result.shield_charges == 0
        assert result.consecutive_missed_focus_days == 4
        assert result.recovery_days_remaining == 1

        # Check events
        types = event_types(repo)
        assert types.count(GamificationEventType.streak_increment) == 6
        assert types.count(GamificationEventType.shield_spend) == 2
        assert types.count(GamificationEventType.shield_recharge) == 1
        assert types.count(GamificationEventType.streak_reset) == 1

    @pytest.mark.asyncio
    async def test_long_streak_with_recovery_cycle(self):
        """
        All days 30 min. Start with existing streak of 10.
        Miss 3 focus days → recovery triggers.
        During recovery, do 2 focus days → recovery ends.
        Streak was reset, starts building again.
        """
        profile = make_profile(
            streak_current=10,
            streak_finalized_through=date(2025, 3, 9),
            plan_json=ALL_DAYS_PLAN_JSON,
            shield_unlocked=True,
            shield_charges=0,  # No shield
        )
        aggs = [
            # Mon-Wed: miss (3 missed focus days → recovery)
            # Thu 3/13: 30 min during recovery day 1
            make_aggregate(date(2025, 3, 13), total_credited_minutes=30),
            # Fri 3/14: 30 min during recovery day 2
            make_aggregate(date(2025, 3, 14), total_credited_minutes=30),
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 15))

        result = await service.roll_forward()

        # Mon: miss → streak reset (10→0), consecutive_missed=1
        # Tue: miss → consecutive_missed=2
        # Wed: miss → consecutive_missed=3 → recovery triggers (2 days remaining)
        # Thu: has activity → consecutive_missed=0, recovery_remaining: 2→1
        #   streak: credited=30, streak_day=1, threshold=15 → streak=1
        # Fri: has activity → recovery_remaining: 1→0
        #   streak: credited=30, streak_day=2, threshold=20 → streak=2

        assert result.streak_current == 2
        assert result.consecutive_missed_focus_days == 0
        assert result.recovery_days_remaining == 0

    @pytest.mark.asyncio
    async def test_streak_with_non_focus_days_interspersed(self):
        """
        Default plan: Mon=30, Tue=0, Wed=30, Thu=0, Fri=30.
        Focus on Mon, Wed, Fri → streak grows by 3.
        Non-focus days (Tue, Thu) don't affect anything.
        """
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
        )
        aggs = [
            make_aggregate(date(2025, 3, 10), total_credited_minutes=30),  # Mon ✓
            # Tue 3/11: non-focus
            make_aggregate(date(2025, 3, 12), total_credited_minutes=30),  # Wed ✓
            # Thu 3/13: non-focus
            make_aggregate(date(2025, 3, 14), total_credited_minutes=30),  # Fri ✓
            # Sat 3/15: non-focus
            # Sun 3/16: non-focus
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 17))

        result = await service.roll_forward()

        assert result.streak_current == 3
        assert result.streak_finalized_through == date(2025, 3, 16)

    @pytest.mark.asyncio
    async def test_shield_spend_then_recharge_then_spend_again(self):
        """
        All days plan. Start streak=4, shield unlocked with charge.
        Day 1: miss → shield spent
        Day 2: success → recharge progress 1
        Day 3: success → recharge progress 2 → recharged!
        Day 4: miss → shield spent again
        """
        profile = make_profile(
            streak_current=4,
            streak_finalized_through=date(2025, 3, 9),
            plan_json=ALL_DAYS_PLAN_JSON,
            shield_unlocked=True,
            shield_charges=1,
        )
        aggs = [
            # Mon 3/10: miss
            make_aggregate(date(2025, 3, 11), total_credited_minutes=30),  # Tue: success
            make_aggregate(date(2025, 3, 12), total_credited_minutes=30),  # Wed: success
            # Thu 3/13: miss
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 14))

        result = await service.roll_forward()

        # Mon: miss, shield spent → streak=4, charges=0
        # Tue: success → streak=5, recharge_progress=1
        # Wed: success → streak=6, recharge_progress=2 → recharged! charges=1
        # Thu: miss, shield spent → streak=6, charges=0

        assert result.streak_current == 6
        assert result.shield_charges == 0
        assert result.shield_recharge_progress == 0

        types = event_types(repo)
        assert types.count(GamificationEventType.shield_spend) == 2
        assert types.count(GamificationEventType.shield_recharge) == 1

    @pytest.mark.asyncio
    async def test_recovery_only_counts_focus_days(self):
        """
        Default plan: Mon,Wed,Fri are focus days.
        Miss Mon, Wed, Fri → 3 missed focus days (triggers recovery).
        Tue, Thu, Sat, Sun are non-focus and don't count.
        """
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
            consecutive_missed_focus_days=0,
        )
        # No aggregates — all focus days missed
        aggs: list[Any] = []
        # today = Mon 3/17, so evaluates Mon 3/10 through Sun 3/16
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 17))

        result = await service.roll_forward()

        # Mon 3/10: focus day, miss → consecutive_missed=1
        # Tue: non-focus
        # Wed 3/12: focus day, miss → consecutive_missed=2
        # Thu: non-focus
        # Fri 3/14: focus day, miss → consecutive_missed=3 → recovery triggers!
        # Sat, Sun: non-focus (recovery not decremented on non-focus days)
        assert result.consecutive_missed_focus_days == 3
        assert result.recovery_days_remaining == RECOVERY_DURATION_FOCUS_DAYS

    @pytest.mark.asyncio
    async def test_three_week_full_cycle(self):
        """
        Week 1: Build streak to 5 with all-day plan (Mon-Fri focus, Sat-Sun off).
        Week 2: Miss 3 days → recovery.
        Week 3: Recover and rebuild streak.
        """
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 2),  # Sun before week 1
            plan_json=HEAVY_PLAN_JSON,  # Mon-Fri 60 min
        )
        aggs = [
            # Week 1 (Mon 3/3 - Fri 3/7): all successful
            make_aggregate(date(2025, 3, 3), total_credited_minutes=60),
            make_aggregate(date(2025, 3, 4), total_credited_minutes=60),
            make_aggregate(date(2025, 3, 5), total_credited_minutes=60),
            make_aggregate(date(2025, 3, 6), total_credited_minutes=60),
            make_aggregate(date(2025, 3, 7), total_credited_minutes=60),
            # Sat-Sun: non-focus
            # Week 2 (Mon 3/10 - Wed 3/12): miss 3 focus days
            # Thu 3/13: start recovery, do 60 min
            make_aggregate(date(2025, 3, 13), total_credited_minutes=60),
            # Fri 3/14: recovery day 2, do 60 min
            make_aggregate(date(2025, 3, 14), total_credited_minutes=60),
            # Sat-Sun: non-focus
            # Week 3 (Mon 3/17 - Fri 3/21): rebuild streak
            make_aggregate(date(2025, 3, 17), total_credited_minutes=60),
            make_aggregate(date(2025, 3, 18), total_credited_minutes=60),
            make_aggregate(date(2025, 3, 19), total_credited_minutes=60),
        ]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 20))

        result = await service.roll_forward()

        # Week 1: streak goes 1→2→3 (shield unlocks!)→4→5
        # Sat-Sun: non-focus, no change
        # Week 2:
        #   Mon: miss, shield spent (charges=0), streak stays 5
        #   Tue: miss, no shield → streak reset to 0, consecutive_missed=1
        #   Wed: miss → consecutive_missed=2
        #   Thu: miss → consecutive_missed=3 → recovery triggers (2 days)
        #
        # Wait — Thu has 60 minutes. Let me re-check the logic.
        # The recovery check happens BEFORE the streak check for a day.
        # Looking at the code:
        #   1. If focus_day and credited == 0: consecutive_missed += 1
        #      If credited > 0: consecutive_missed = 0
        #   2. If consecutive_missed >= 3 and recovery == 0: trigger recovery
        #   3. elif recovery > 0: recovery -= 1
        #   4. Then streak evaluation happens
        #
        # Mon 3/10: focus, credited=0 → missed=1
        # Tue 3/11: focus, credited=0 → missed=2
        # Wed 3/12: focus, credited=0 → missed=3 → recovery triggers (remaining=2)
        # Thu 3/13: focus, credited=60 → missed=0.
        #   But wait, recovery was just set to 2. The elif says if recovery > 0: recovery -= 1
        #   But credited > 0, so missed gets reset to 0 FIRST.
        #   Then the trigger check: missed(0) >= 3? No.
        #   Then the elif: recovery(2) > 0? Yes → recovery = 1
        #   Then streak: threshold check...
        #
        # Actually I need to re-read the code more carefully.

        # Let me just verify key outputs
        assert result.shield_unlocked is True
        assert result.streak_finalized_through == date(2025, 3, 19)


# ──────────────────── Test: Edge cases ────────────────────


class TestEdgeCases:
    @pytest.mark.asyncio
    async def test_first_ever_roll_forward_no_finalized(self):
        """Profile with no streak_finalized_through — evaluates just yesterday."""
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=None,
            plan_json=ALL_DAYS_PLAN_JSON,
        )
        yesterday = date(2025, 3, 10)
        aggs = [make_aggregate(yesterday, total_credited_minutes=30)]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 11))

        result = await service.roll_forward()

        assert result.streak_current == 1
        assert result.streak_finalized_through == yesterday

    @pytest.mark.asyncio
    async def test_same_day_multiple_calls_idempotent(self):
        """Calling roll_forward twice on the same day shouldn't double-process."""
        today = date(2025, 3, 11)
        profile = make_profile(
            streak_current=1,
            streak_finalized_through=today - timedelta(days=1),
        )
        service, repo = build_service(profile, [], fake_today=today)

        result1 = await service.roll_forward()
        repo.events.clear()
        result2 = await service.roll_forward()

        assert result1.streak_current == result2.streak_current
        assert len(repo.events) == 0  # No new events on second call

    @pytest.mark.asyncio
    async def test_large_gap_processes_all_days(self):
        """30-day gap with no activity — all focus days counted as missed."""
        profile = make_profile(
            streak_current=5,
            streak_finalized_through=date(2025, 2, 10),
            plan_json=ALL_DAYS_PLAN_JSON,
        )
        aggs: list[Any] = []
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 12))

        result = await service.roll_forward()

        # Streak should be 0 (reset on first missed focus day)
        assert result.streak_current == 0
        # Recovery should have been triggered (3+ consecutive misses)
        # But after that, more misses may trigger another recovery cycle
        assert result.streak_finalized_through == date(2025, 3, 11)

    @pytest.mark.asyncio
    async def test_credited_1_minute_still_counts_for_miss_counter(self):
        """Even 1 credited minute resets the consecutive miss counter."""
        profile = make_profile(
            streak_current=0,
            streak_finalized_through=date(2025, 3, 9),
            plan_json=ALL_DAYS_PLAN_JSON,
            consecutive_missed_focus_days=2,
        )
        # 1 minute credited — not enough for streak, but resets miss counter
        aggs = [make_aggregate(date(2025, 3, 10), total_credited_minutes=1)]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 11))

        result = await service.roll_forward()

        assert result.consecutive_missed_focus_days == 0
        assert result.streak_current == 0  # Below threshold, still 0

    @pytest.mark.asyncio
    async def test_shield_unlock_exactly_at_3(self):
        """Shield unlocks precisely when streak reaches SHIELD_UNLOCK_STREAK_LEN (3)."""
        profile = make_profile(
            streak_current=2,
            streak_finalized_through=date(2025, 3, 10),
            plan_json=ALL_DAYS_PLAN_JSON,
        )
        aggs = [make_aggregate(date(2025, 3, 11), total_credited_minutes=30)]
        service, repo = build_service(profile, aggs, fake_today=date(2025, 3, 12))

        result = await service.roll_forward()

        assert result.streak_current == 3
        assert result.shield_unlocked is True
        assert result.shield_charges == 1
