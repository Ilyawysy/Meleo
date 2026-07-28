from __future__ import annotations

import json
import math
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

# ──────────────────────── Constants ────────────────────────

MIN_REWARD_MINUTES: int = 0

XP_PER_MIN: int = 1
BASE_COIN_RATE: float = 0.1  # display-coins per minute (= 1 subcoin per min)
COIN_SUBCOINS_PER_MIN: int = 1

COIN_REWARD_LIMIT_MINUTES: int = 480
PLAN_DAY_MINUTES_STEP: int = 10
DEFAULT_DAY_CUTOFF_HOUR: int = 4

# ── Streak threshold constants ──
STREAK_PERCENT: float = 0.70
STREAK_ABS_MIN_MINUTES: int = 10

# ── Ramp-up table: streak_day → minimum minutes ──
STREAK_RAMP_UP: list[tuple[int, int]] = [
    (1, 15),
    (2, 20),
    (3, 25),
    (4, 30),
    (5, 35),
    (6, 40),
    # 7+ → 45
]
STREAK_RAMP_UP_MAX: int = 45

# ── Streak multiplier table (spec 6.3) ──
STREAK_MULT_TABLE: list[tuple[int, float]] = [
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
    # 14+ → 1.50
]

# ── Shield constants (spec 7) ──
SHIELD_UNLOCK_STREAK_LEN: int = 3
SHIELD_MAX_CHARGES: int = 1
SHIELD_RECHARGE_SUCCESS_DAYS: int = 2

# ── Recovery constants ──
RECOVERY_TRIGGER_MISSED_FOCUS_DAYS: int = 3
RECOVERY_DURATION_FOCUS_DAYS: int = 2
RECOVERY_COIN_MULT: float = 2.0

# ── XP level curve (spec 3.1) ──
# Tier boundaries: levels 1-5 → +120 per level, 6-15 → +300, 16-30 → +600, 31+ → +1000
LEVEL_CURVE_TIERS: list[tuple[int, int, int]] = [
    (1, 5, 120),
    (6, 15, 300),
    (16, 30, 600),
    (31, 999_999, 1000),
]


# ──────────────────────── Pure functions ────────────────────────


def compute_streak_multiplier(streak_len: int) -> float:
    """Return the streak multiplier for a given streak length."""
    if streak_len <= 0:
        return 1.0
    if streak_len >= 14:
        return 1.50
    for day, mult in STREAK_MULT_TABLE:
        if streak_len == day:
            return mult
    return 1.0


def ramp_up_minutes(streak_day: int) -> int:
    """Return ramp-up minutes for a given streak day (1-based)."""
    for day, minutes in STREAK_RAMP_UP:
        if streak_day == day:
            return minutes
    return STREAK_RAMP_UP_MAX


def streak_threshold(plan_minutes_for_day: int, streak_day: int = 1) -> int:
    """Return the minimum credited minutes needed to count a streak for this day's plan.

    Uses ramp-up: early streak days have a lower bar that grows gradually.
    The requirement is min(ramp_up, plan * STREAK_PERCENT).
    """
    if plan_minutes_for_day <= 0:
        return 0
    ramp_up = ramp_up_minutes(streak_day)
    percent_threshold = int(plan_minutes_for_day * STREAK_PERCENT)
    return max(STREAK_ABS_MIN_MINUTES, min(ramp_up, percent_threshold))


def parse_plan_minutes(json_str: str) -> dict[int, int]:
    """Parse plan_minutes_json string to {weekday: minutes} dict with int keys."""
    raw: dict[str, int] = json.loads(json_str)
    return {int(k): v for k, v in raw.items()}


def is_focus_day(plan_minutes: dict[int, int], weekday: int) -> bool:
    """Return True if weekday is a focus day (plan_minutes > 0)."""
    return plan_minutes.get(weekday, 0) > 0


def get_plan_for_weekday(plan_minutes: dict[int, int], weekday: int) -> int:
    """Return planned minutes for weekday."""
    return plan_minutes.get(weekday, 0)


def compute_mode_multiplier(
    recovery_active: bool,
    streak_len: int,
) -> float:
    """Return the effective mode multiplier.

    If recovery_active return RECOVERY_COIN_MULT, else return streak multiplier.
    """
    if recovery_active:
        return RECOVERY_COIN_MULT
    streak_mult = compute_streak_multiplier(streak_len)
    return max(streak_mult, 1.0)


def compute_session_rewards(
    credited_minutes: int,
    coin_minutes_used_today: int,
    coin_remainder: float,
    mode_multiplier: float,
    minimal_mode: bool,
) -> tuple[int, int, float, dict]:
    """Compute rewards for a focus session.

    Returns (xp, subcoins, new_remainder, breakdown).
    - XP = credited_minutes (no multiplier)
    - Coins = floor(BASE_COIN_RATE * mode_multiplier * coin_minutes_allowed + coin_remainder)
    """
    if credited_minutes <= 0:
        return (
            0,
            0,
            coin_remainder,
            {
                "reason": "below_min_reward",
                "credited_minutes": credited_minutes,
            },
        )

    # XP — always 1:1 with credited minutes, no multiplier
    earned_xp = credited_minutes * XP_PER_MIN

    if minimal_mode:
        return (
            earned_xp,
            0,
            coin_remainder,
            {
                "credited_minutes": credited_minutes,
                "earned_xp": earned_xp,
                "earned_subcoins": 0,
                "mode_multiplier": round(mode_multiplier, 4),
                "minimal_mode": True,
            },
        )

    # Coin minutes allowed (capped by COIN_REWARD_LIMIT_MINUTES)
    coin_minutes_remaining = max(0, COIN_REWARD_LIMIT_MINUTES - coin_minutes_used_today)
    coin_minutes_allowed = min(credited_minutes, coin_minutes_remaining)

    # Raw coin value (in display coins) + remainder
    raw_coin_value = BASE_COIN_RATE * mode_multiplier * coin_minutes_allowed + coin_remainder
    earned_subcoins = math.floor(raw_coin_value * 10)  # convert to subcoins
    new_remainder = raw_coin_value - earned_subcoins / 10

    breakdown = {
        "credited_minutes": credited_minutes,
        "coin_minutes_allowed": coin_minutes_allowed,
        "coin_minutes_used_today": coin_minutes_used_today,
        "mode_multiplier": round(mode_multiplier, 4),
        "earned_xp": earned_xp,
        "earned_subcoins": earned_subcoins,
        "coin_remainder": round(new_remainder, 6),
    }
    return earned_xp, earned_subcoins, new_remainder, breakdown


# ──────────────────── XP levels ────────────────────


def xp_for_level(level: int) -> int:
    """XP needed to go from level-1 to level (i.e. the width of one level)."""
    if level <= 0:
        return 0
    for lo, hi, increment in LEVEL_CURVE_TIERS:
        if lo <= level <= hi:
            return increment
    return LEVEL_CURVE_TIERS[-1][2]


def cumulative_xp_for_level(level: int) -> int:
    """Total XP needed to reach *level* (sum of xp_for_level(1..level))."""
    if level <= 0:
        return 0
    total = 0
    for lvl in range(1, level + 1):
        total += xp_for_level(lvl)
    return total


def compute_xp_level(total_xp: int) -> int:
    """Current level for *total_xp* (0 if below level 1 threshold)."""
    if total_xp < xp_for_level(1):
        return 0
    level = 0
    cumulative = 0
    while True:
        next_level_xp = xp_for_level(level + 1)
        if cumulative + next_level_xp > total_xp:
            break
        cumulative += next_level_xp
        level += 1
    return level


def xp_to_next_level(total_xp: int) -> int:
    """XP remaining to the next level."""
    current_level = compute_xp_level(total_xp)
    return cumulative_xp_for_level(current_level + 1) - total_xp


# ──────────────────── FocusDate helpers ────────────────────


def focus_date(
    timestamp: datetime, home_tz: str, cutoff_hour: int = DEFAULT_DAY_CUTOFF_HOUR
) -> date:
    """Compute the FocusDate for a timestamp.

    If local time is before cutoff_hour, the focus date is the previous calendar day.
    """
    try:
        tz = ZoneInfo(home_tz)
    except (KeyError, Exception):
        tz = ZoneInfo("UTC")
    local_dt = timestamp.astimezone(tz)
    if local_dt.hour < cutoff_hour:
        return (local_dt - timedelta(days=1)).date()
    return local_dt.date()


# ──────────────────── Display helpers ────────────────────


def subcoins_to_display(subcoins: int) -> float:
    """Convert internal subcoins to display coins (e.g. 150 → 15.0)."""
    return subcoins / 10
