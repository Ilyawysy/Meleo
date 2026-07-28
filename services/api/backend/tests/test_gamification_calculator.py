from __future__ import annotations

from datetime import date, datetime, timezone

import pytest

from backend.domain.gamification.calculator import (
    COIN_REWARD_LIMIT_MINUTES,
    DEFAULT_DAY_CUTOFF_HOUR,
    MIN_REWARD_MINUTES,
    RECOVERY_COIN_MULT,
    compute_mode_multiplier,
    compute_session_rewards,
    compute_streak_multiplier,
    compute_xp_level,
    cumulative_xp_for_level,
    focus_date,
    is_focus_day,
    parse_plan_minutes,
    ramp_up_minutes,
    streak_threshold,
    subcoins_to_display,
    xp_for_level,
    xp_to_next_level,
)


# ──────────────────── Streak multiplier ────────────────────


class TestStreakMultiplier:
    @pytest.mark.parametrize(
        "streak, expected",
        [
            (-1, 1.0),
            (0, 1.0),
            (1, 1.00),
            (2, 1.05),
            (3, 1.10),
            (4, 1.15),
            (5, 1.20),
            (6, 1.25),
            (7, 1.30),
            (8, 1.35),
            (9, 1.38),
            (10, 1.41),
            (11, 1.44),
            (12, 1.47),
            (13, 1.49),
            (14, 1.50),
            (15, 1.50),
            (50, 1.50),
            (100, 1.50),
        ],
    )
    def test_streak_brackets(self, streak: int, expected: float):
        assert compute_streak_multiplier(streak) == pytest.approx(expected)


# ──────────────────── Ramp-up minutes ────────────────────


class TestRampUpMinutes:
    @pytest.mark.parametrize(
        "day, expected",
        [(1, 15), (2, 20), (3, 25), (4, 30), (5, 35), (6, 40), (7, 45), (8, 45), (50, 45)],
    )
    def test_ramp_up_table(self, day: int, expected: int):
        assert ramp_up_minutes(day) == expected


# ──────────────────── Streak threshold ────────────────────


class TestStreakThreshold:
    def test_plan_30_day1(self):
        # ramp_up(1)=15, int(30*0.70)=21 → min(15,21)=15, max(10,15)=15
        assert streak_threshold(30, streak_day=1) == 15

    def test_plan_30_day4(self):
        # ramp_up(4)=30, int(30*0.70)=21 → min(30,21)=21
        assert streak_threshold(30, streak_day=4) == 21

    def test_plan_30_day7(self):
        # ramp_up(7)=45, int(30*0.70)=21 → min(45,21)=21
        assert streak_threshold(30, streak_day=7) == 21

    def test_plan_100_day1(self):
        # ramp_up(1)=15, int(100*0.70)=70 → min(15,70)=15
        assert streak_threshold(100, streak_day=1) == 15

    def test_plan_100_day7(self):
        # ramp_up(7)=45, int(100*0.70)=70 → min(45,70)=45
        assert streak_threshold(100, streak_day=7) == 45

    def test_plan_100_day10(self):
        # ramp_up(10)=45 (7+ cap), int(100*0.70)=70 → min(45,70)=45
        assert streak_threshold(100, streak_day=10) == 45

    def test_plan_0(self):
        assert streak_threshold(0) == 0

    def test_plan_negative(self):
        assert streak_threshold(-1) == 0

    def test_default_streak_day(self):
        # default streak_day=1, ramp_up=15, int(60*0.70)=42 → min(15,42)=15
        assert streak_threshold(60) == 15

    def test_ramp_up_progression(self):
        # With plan=60 (percent=42), ramp-up grows: 15,20,25,30,35,40,42(capped by percent)
        expected = [15, 20, 25, 30, 35, 40, 42]
        for day, exp in enumerate(expected, start=1):
            assert streak_threshold(60, streak_day=day) == exp

    def test_small_plan_abs_min_applies(self):
        # plan=10, percent=7. min(ramp_up, 7)=7, but abs min=10 → 10
        for day in range(1, 10):
            assert streak_threshold(10, streak_day=day) == 10


# ──────────────────── Mode multiplier ────────────────────


class TestModeMultiplier:
    def test_no_recovery_no_streak(self):
        assert compute_mode_multiplier(recovery_active=False, streak_len=0) == pytest.approx(1.0)

    def test_streak_only(self):
        assert compute_mode_multiplier(recovery_active=False, streak_len=5) == pytest.approx(1.20)

    def test_recovery_active(self):
        assert compute_mode_multiplier(recovery_active=True, streak_len=0) == pytest.approx(
            RECOVERY_COIN_MULT
        )

    def test_recovery_beats_streak(self):
        assert compute_mode_multiplier(recovery_active=True, streak_len=14) == pytest.approx(
            RECOVERY_COIN_MULT
        )

    def test_streak_1_no_recovery(self):
        assert compute_mode_multiplier(recovery_active=False, streak_len=1) == pytest.approx(1.0)

    def test_no_recovery_high_streak(self):
        assert compute_mode_multiplier(recovery_active=False, streak_len=14) == pytest.approx(1.50)


# ──────────────────── is_focus_day ────────────────────


class TestIsFocusDay:
    def test_weekday_match(self):
        plan = {1: 30, 2: 30, 3: 30, 4: 30, 5: 30, 6: 0, 7: 0}
        # 2025-03-10 is Monday (isoweekday() = 1)
        assert is_focus_day(plan, 1) is True
        assert is_focus_day(plan, 2) is True
        assert is_focus_day(plan, 6) is False
        assert is_focus_day(plan, 7) is False

    def test_weekend_plan(self):
        plan = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 30, 7: 30}
        assert is_focus_day(plan, 1) is False
        assert is_focus_day(plan, 6) is True
        assert is_focus_day(plan, 7) is True

    def test_all_days(self):
        plan = {1: 30, 2: 30, 3: 30, 4: 30, 5: 30, 6: 30, 7: 30}
        for d in range(1, 8):
            assert is_focus_day(plan, d) is True

    def test_no_focus_days(self):
        plan = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0}
        for d in range(1, 8):
            assert is_focus_day(plan, d) is False

    def test_missing_key(self):
        plan = {1: 30}
        assert is_focus_day(plan, 2) is False


# ──────────────────── parse_plan_minutes ────────────────────


class TestParsePlanMinutes:
    def test_default_plan(self):
        result = parse_plan_minutes('{"1":30,"2":0,"3":30,"4":0,"5":30,"6":0,"7":0}')
        assert result == {1: 30, 2: 0, 3: 30, 4: 0, 5: 30, 6: 0, 7: 0}

    def test_int_keys(self):
        result = parse_plan_minutes('{"1":45,"2":45,"3":0,"4":0,"5":0,"6":0,"7":0}')
        assert isinstance(list(result.keys())[0], int)


# ──────────────────── Session rewards ────────────────────


class TestSessionRewards:
    def test_below_min_reward(self):
        xp, coins, rem, breakdown = compute_session_rewards(
            credited_minutes=0,
            coin_minutes_used_today=0,
            coin_remainder=0.0,
            mode_multiplier=1.0,
            minimal_mode=False,
        )
        assert xp == 0
        assert coins == 0
        assert rem == 0.0
        assert breakdown["reason"] == "below_min_reward"

    def test_one_minute_earns_rewards(self):
        xp, coins, rem, breakdown = compute_session_rewards(
            credited_minutes=1,
            coin_minutes_used_today=0,
            coin_remainder=0.0,
            mode_multiplier=1.0,
            minimal_mode=False,
        )
        assert xp == 1  # 1 * 1 XP
        # coins: floor(0.1 * 1.0 * 1 * 10) = floor(1) = 1 subcoin
        assert coins == 1
        assert breakdown["earned_xp"] == 1

    def test_exactly_min_reward(self):
        xp, coins, rem, breakdown = compute_session_rewards(
            credited_minutes=MIN_REWARD_MINUTES,
            coin_minutes_used_today=0,
            coin_remainder=0.0,
            mode_multiplier=1.0,
            minimal_mode=False,
        )
        # MIN_REWARD_MINUTES is now 0, so 0 credited_minutes → below_min_reward
        assert xp == 0
        assert coins == 0
        assert breakdown["reason"] == "below_min_reward"

    def test_xp_no_multiplier(self):
        """XP should always be 1:1 with credited_minutes, regardless of mode_multiplier."""
        xp, _, _, _ = compute_session_rewards(
            credited_minutes=30,
            coin_minutes_used_today=0,
            coin_remainder=0.0,
            mode_multiplier=2.0,
            minimal_mode=False,
        )
        assert xp == 30

    def test_coin_multiplier_applied(self):
        """Coins should use mode_multiplier."""
        _, coins, _, breakdown = compute_session_rewards(
            credited_minutes=10,
            coin_minutes_used_today=0,
            coin_remainder=0.0,
            mode_multiplier=2.0,
            minimal_mode=False,
        )
        # raw_coin_value = 0.1 * 2.0 * 10 = 2.0 display coins
        # subcoins = floor(2.0 * 10) = 20
        assert coins == 20
        assert breakdown["mode_multiplier"] == pytest.approx(2.0)

    def test_coin_limit_reached(self):
        """No more coin minutes after COIN_REWARD_LIMIT_MINUTES."""
        xp, coins, _, _ = compute_session_rewards(
            credited_minutes=60,
            coin_minutes_used_today=COIN_REWARD_LIMIT_MINUTES,
            coin_remainder=0.0,
            mode_multiplier=1.5,
            minimal_mode=False,
        )
        assert xp == 60  # XP still awarded
        assert coins == 0  # No coin minutes left

    def test_coin_limit_partial(self):
        """Partial coin minutes when approaching limit."""
        xp, coins, _, breakdown = compute_session_rewards(
            credited_minutes=60,
            coin_minutes_used_today=COIN_REWARD_LIMIT_MINUTES - 20,
            coin_remainder=0.0,
            mode_multiplier=1.0,
            minimal_mode=False,
        )
        assert xp == 60
        # Only 20 coin minutes allowed
        # raw = 0.1 * 1.0 * 20 = 2.0 → subcoins = 20
        assert coins == 20
        assert breakdown["coin_minutes_allowed"] == 20

    def test_remainder_carries_over(self):
        """Coin remainder from previous session should carry over."""
        _, coins1, rem1, _ = compute_session_rewards(
            credited_minutes=7,
            coin_minutes_used_today=0,
            coin_remainder=0.0,
            mode_multiplier=1.0,
            minimal_mode=False,
        )
        # raw = 0.1 * 1.0 * 7 + 0 = 0.7 → subcoins = floor(0.7 * 10) = 7
        # remainder = 0.7 - 0.7 = 0.0
        assert coins1 == 7

        # Now use with remainder
        _, coins2, rem2, _ = compute_session_rewards(
            credited_minutes=7,
            coin_minutes_used_today=7,
            coin_remainder=0.05,
            mode_multiplier=1.0,
            minimal_mode=False,
        )
        # raw = 0.1 * 1.0 * 7 + 0.05 = 0.75 → subcoins = floor(7.5) = 7
        assert coins2 == 7

    def test_minimal_mode_no_coins(self):
        """Minimal mode: XP earned, 0 coins."""
        xp, coins, rem, breakdown = compute_session_rewards(
            credited_minutes=30,
            coin_minutes_used_today=0,
            coin_remainder=0.5,
            mode_multiplier=2.0,
            minimal_mode=True,
        )
        assert xp == 30
        assert coins == 0
        assert rem == 0.5  # remainder unchanged
        assert breakdown["minimal_mode"] is True

    def test_zero_credited(self):
        xp, coins, rem, _ = compute_session_rewards(
            credited_minutes=0,
            coin_minutes_used_today=0,
            coin_remainder=0.0,
            mode_multiplier=1.0,
            minimal_mode=False,
        )
        assert xp == 0
        assert coins == 0

    def test_large_session_coin_cap(self):
        """480 min session at streak 14 multiplier."""
        xp, coins, _, breakdown = compute_session_rewards(
            credited_minutes=480,
            coin_minutes_used_today=0,
            coin_remainder=0.0,
            mode_multiplier=1.50,
            minimal_mode=False,
        )
        assert xp == 480
        # coin_minutes_allowed = min(480, 480) = 480
        # raw = 0.1 * 1.5 * 480 = 72.0 display coins → 720 subcoins
        assert coins == 720
        assert breakdown["coin_minutes_allowed"] == 480

    def test_recovery_coin_mult(self):
        xp, coins, _, _ = compute_session_rewards(
            credited_minutes=10,
            coin_minutes_used_today=0,
            coin_remainder=0.0,
            mode_multiplier=RECOVERY_COIN_MULT,
            minimal_mode=False,
        )
        assert xp == 10
        # raw = 0.1 * 2.0 * 10 = 2.0 → 20 subcoins
        assert coins == 20


# ──────────────────── XP levels (new curve) ────────────────────


class TestXPLevels:
    def test_xp_for_level_tiers(self):
        # Levels 1-5: 120 each
        assert xp_for_level(1) == 120
        assert xp_for_level(5) == 120
        # Levels 6-15: 300 each
        assert xp_for_level(6) == 300
        assert xp_for_level(15) == 300
        # Levels 16-30: 600 each
        assert xp_for_level(16) == 600
        assert xp_for_level(30) == 600
        # Levels 31+: 1000 each
        assert xp_for_level(31) == 1000
        assert xp_for_level(50) == 1000

    def test_xp_for_level_zero(self):
        assert xp_for_level(0) == 0
        assert xp_for_level(-1) == 0

    def test_cumulative_xp(self):
        assert cumulative_xp_for_level(0) == 0
        assert cumulative_xp_for_level(1) == 120
        assert cumulative_xp_for_level(2) == 240
        assert cumulative_xp_for_level(5) == 600  # 5 * 120
        assert cumulative_xp_for_level(6) == 900  # 600 + 300
        assert (
            cumulative_xp_for_level(10) == 2100
        )  # 600 + 4*300 (wait: 6,7,8,9,10 = 5*300=1500) → 600+1500=2100
        assert cumulative_xp_for_level(15) == 3600  # 600 + 10*300
        assert cumulative_xp_for_level(16) == 4200  # 3600 + 600
        assert cumulative_xp_for_level(30) == 12600  # 3600 + 15*600
        assert cumulative_xp_for_level(31) == 13600  # 12600 + 1000

    def test_level_from_xp(self):
        assert compute_xp_level(0) == 0
        assert compute_xp_level(119) == 0
        assert compute_xp_level(120) == 1
        assert compute_xp_level(239) == 1
        assert compute_xp_level(240) == 2
        assert compute_xp_level(599) == 4
        assert compute_xp_level(600) == 5
        assert compute_xp_level(899) == 5
        assert compute_xp_level(900) == 6
        assert compute_xp_level(3600) == 15
        assert compute_xp_level(4200) == 16
        assert compute_xp_level(12600) == 30
        assert compute_xp_level(13600) == 31

    def test_xp_to_next(self):
        assert xp_to_next_level(0) == 120  # need 120 for level 1
        assert xp_to_next_level(120) == 120  # at level 1, need 240 for level 2
        assert xp_to_next_level(200) == 40  # need 240 for level 2
        assert xp_to_next_level(600) == 300  # at level 5, need 900 for level 6

    def test_high_level(self):
        # Level 31 requires 13600 XP
        assert compute_xp_level(13600) == 31
        # Level 32 requires 13600 + 1000 = 14600
        assert compute_xp_level(14600) == 32


# ──────────────────── FocusDate ────────────────────


class TestFocusDate:
    def test_normal_daytime(self):
        """10:00 AM → same calendar day."""
        ts = datetime(2025, 3, 15, 10, 0, 0, tzinfo=timezone.utc)
        assert focus_date(ts, "UTC") == date(2025, 3, 15)

    def test_before_cutoff(self):
        """3:00 AM → previous calendar day (cutoff=4)."""
        ts = datetime(2025, 3, 15, 3, 0, 0, tzinfo=timezone.utc)
        assert focus_date(ts, "UTC") == date(2025, 3, 14)

    def test_exactly_at_cutoff(self):
        """4:00 AM → same calendar day."""
        ts = datetime(2025, 3, 15, 4, 0, 0, tzinfo=timezone.utc)
        assert focus_date(ts, "UTC") == date(2025, 3, 15)

    def test_midnight(self):
        """0:00 AM → previous calendar day."""
        ts = datetime(2025, 3, 15, 0, 0, 0, tzinfo=timezone.utc)
        assert focus_date(ts, "UTC") == date(2025, 3, 14)

    def test_custom_cutoff(self):
        """Custom cutoff hour=6."""
        ts = datetime(2025, 3, 15, 5, 0, 0, tzinfo=timezone.utc)
        assert focus_date(ts, "UTC", cutoff_hour=6) == date(2025, 3, 14)
        ts2 = datetime(2025, 3, 15, 6, 0, 0, tzinfo=timezone.utc)
        assert focus_date(ts2, "UTC", cutoff_hour=6) == date(2025, 3, 15)

    def test_timezone_conversion(self):
        """UTC timestamp at 2 AM, but 5 AM in Europe/Moscow (UTC+3)."""
        ts = datetime(2025, 3, 15, 2, 0, 0, tzinfo=timezone.utc)
        # Moscow time = 5 AM → ≥ cutoff(4) → same day
        assert focus_date(ts, "Europe/Moscow") == date(2025, 3, 15)

    def test_timezone_before_cutoff(self):
        """UTC 0:30 AM → Moscow 3:30 AM → before cutoff → previous day."""
        ts = datetime(2025, 3, 15, 0, 30, 0, tzinfo=timezone.utc)
        assert focus_date(ts, "Europe/Moscow") == date(2025, 3, 14)

    def test_invalid_timezone_falls_to_utc(self):
        ts = datetime(2025, 3, 15, 10, 0, 0, tzinfo=timezone.utc)
        assert focus_date(ts, "Invalid/TZ") == date(2025, 3, 15)


# ──────────────────── Constants sanity ────────────────────


class TestConstants:
    def test_recovery_constants(self):
        assert RECOVERY_COIN_MULT == pytest.approx(2.0)

    def test_coin_limit(self):
        assert COIN_REWARD_LIMIT_MINUTES == 480

    def test_default_cutoff(self):
        assert DEFAULT_DAY_CUTOFF_HOUR == 4


# ──────────────────── Display helpers ────────────────────


class TestHelpers:
    def test_subcoins_to_display(self):
        assert subcoins_to_display(0) == pytest.approx(0.0)
        assert subcoins_to_display(10) == pytest.approx(1.0)
        assert subcoins_to_display(15) == pytest.approx(1.5)
        assert subcoins_to_display(300) == pytest.approx(30.0)
        assert subcoins_to_display(720) == pytest.approx(72.0)
