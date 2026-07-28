from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from backend.domain.focus.entities import FocusSession, FocusSessionStatus, UserBalance
from backend.domain.focus.repository import FocusRepository
from backend.domain.gamification.calculator import (
    RECOVERY_DURATION_FOCUS_DAYS,
    RECOVERY_TRIGGER_MISSED_FOCUS_DAYS,
    SHIELD_RECHARGE_SUCCESS_DAYS,
    SHIELD_UNLOCK_STREAK_LEN,
    compute_mode_multiplier,
    compute_session_rewards,
    focus_date,
    get_plan_for_weekday,
    is_focus_day,
    parse_plan_minutes,
    streak_threshold,
)
from backend.domain.gamification.entities import (
    GamificationEvent,
    GamificationEventType,
    UserGamificationProfile,
)
from backend.domain.gamification.repository import GamificationRepository
from backend.infrastructure.logging import get_logger

PLAN_MINUTES_STEP = 10


class GamificationService:
    def __init__(
        self,
        gamification_repo: GamificationRepository,
        focus_repo: FocusRepository,
        session,
        user_id: uuid.UUID,
    ) -> None:
        self._gam_repo = gamification_repo
        self._focus_repo = focus_repo
        self._session = session
        self._user_id = user_id
        self._logger = get_logger("gamification_service")

    def _transaction_ctx(self):
        return (
            self._session.begin_nested()
            if self._session.in_transaction()
            else self._session.begin()
        )

    # ── Timezone helpers ──

    def _user_today(self, profile: UserGamificationProfile) -> date:
        return focus_date(
            datetime.now(timezone.utc),
            profile.home_tz,
            profile.day_cutoff_hour,
        )

    # ── Profile ──

    async def get_or_create_profile(self) -> UserGamificationProfile:
        profile = await self._gam_repo.get_profile()
        if profile is None:
            profile = await self._gam_repo.create_profile()
        return profile

    async def update_settings(
        self,
        plan_minutes: dict[int, int] | None = None,
        home_tz: str | None = None,
        day_cutoff_hour: int | None = None,
        minimal_mode: bool | None = None,
        theme_mode: str | None = None,
        focus_duration_min: int | None = None,
        short_break_min: int | None = None,
        long_break_min: int | None = None,
        sessions_before_long_break: int | None = None,
        auto_start_break: bool | None = None,
        auto_start_next_session: bool | None = None,
        adjust_duration_after_session: bool | None = None,
        stat_widget_config: str | None = None,
    ) -> UserGamificationProfile:
        profile = await self.get_or_create_profile()
        now = datetime.now(timezone.utc)

        if plan_minutes is not None:
            # Validate keys 1-7, values 0-480 in steps of 10, at least one > 0
            if not all(k in range(1, 8) for k in plan_minutes):
                raise ValueError("plan_minutes keys must be integers 1-7")
            if not all(0 <= v <= 480 and v % PLAN_MINUTES_STEP == 0 for v in plan_minutes.values()):
                raise ValueError("plan_minutes values must be 0-480 in steps of 10")
            if not any(v > 0 for v in plan_minutes.values()):
                raise ValueError("plan_minutes must have at least one day > 0")

            # 14-day cooldown
            if profile.plan_changed_at is not None:
                profile_age_days = (now - profile.created_at).days
                if profile_age_days >= 7:
                    days_since_change = (now - profile.plan_changed_at).days
                    if days_since_change < 14:
                        raise ValueError("Plan can only be changed once every 14 days")

            full_plan = {d: plan_minutes.get(d, 0) for d in range(1, 8)}
            profile.plan_minutes_json = json.dumps(full_plan)
            profile.plan_changed_at = now

        if home_tz is not None:
            try:
                ZoneInfo(home_tz)
            except (KeyError, Exception) as exc:
                raise ValueError(f"Invalid timezone: {home_tz}") from exc
            if profile.home_tz_set_at is not None:
                profile_age_days = (now - profile.created_at).days
                if profile_age_days >= 7:
                    days_since_change = (now - profile.home_tz_set_at).days
                    if days_since_change < 30:
                        raise ValueError("HomeTZ can only be changed once every 30 days")
                else:
                    raise ValueError("HomeTZ can only be changed once during the first 7 days")
            profile.home_tz = home_tz
            profile.timezone = home_tz
            profile.home_tz_set_at = now

        if day_cutoff_hour is not None:
            if profile.day_cutoff_changed_at is not None:
                profile_age_days = (now - profile.created_at).days
                if profile_age_days >= 7:
                    days_since_change = (now - profile.day_cutoff_changed_at).days
                    if days_since_change < 30:
                        raise ValueError("DayCutoffTime can only be changed once every 30 days")
                else:
                    raise ValueError(
                        "DayCutoffTime can only be changed once during the first 7 days"
                    )
            profile.day_cutoff_hour = day_cutoff_hour
            profile.day_cutoff_changed_at = now

        if minimal_mode is not None:
            profile.minimal_mode = minimal_mode
            if not minimal_mode:
                today = self._user_today(profile)
                profile.streak_finalized_through = today - timedelta(days=1)
                profile.consecutive_missed_focus_days = 0
                profile.recovery_days_remaining = 0

        if theme_mode is not None:
            if theme_mode not in ("light", "dark", "system"):
                raise ValueError("theme_mode must be one of: light, dark, system")
            profile.theme_mode = theme_mode

        if focus_duration_min is not None:
            profile.focus_duration_min = focus_duration_min
        if short_break_min is not None:
            profile.short_break_min = short_break_min
        if long_break_min is not None:
            profile.long_break_min = long_break_min
        if sessions_before_long_break is not None:
            profile.sessions_before_long_break = sessions_before_long_break
        if auto_start_break is not None:
            profile.auto_start_break = auto_start_break
        if auto_start_next_session is not None:
            profile.auto_start_next_session = auto_start_next_session
        if adjust_duration_after_session is not None:
            profile.adjust_duration_after_session = adjust_duration_after_session
        if stat_widget_config is not None:
            profile.stat_widget_config = stat_widget_config

        return await self._gam_repo.update_profile(profile)

    # ── Reward calculation ──

    async def calculate_and_award_session(
        self,
        focus_session: FocusSession,
        credited_minutes: int,
        balance: UserBalance,
    ) -> tuple[int, int, dict]:
        """Calculate and apply rewards. Returns (earned_xp, earned_subcoins, breakdown)."""
        async with self._transaction_ctx():
            profile = await self._gam_repo.lock_profile()
            if profile is None:
                profile = await self._gam_repo.create_profile()

            today = self._user_today(profile)
            session_day = focus_session.session_day or today

            agg = await self._gam_repo.lock_aggregate(session_day)
            if agg is None:
                agg = await self._gam_repo.create_aggregate(session_day)

            recovery_active = agg.recovery_mode is not None
            mode_mult = compute_mode_multiplier(
                recovery_active=recovery_active, streak_len=profile.streak_current
            )

            earned_xp, earned_subcoins, new_remainder, breakdown = compute_session_rewards(
                credited_minutes=credited_minutes,
                coin_minutes_used_today=agg.coin_minutes_used,
                coin_remainder=profile.coin_remainder,
                mode_multiplier=mode_mult,
                minimal_mode=profile.minimal_mode,
            )

            focus_session.credited_minutes = credited_minutes
            focus_session.earned_xp = earned_xp
            focus_session.earned_coins = earned_subcoins
            focus_session.status = FocusSessionStatus.finished

            balance.coins += earned_subcoins

            profile.xp += earned_xp
            breakdown["coin_remainder_before"] = profile.coin_remainder
            profile.coin_remainder = new_remainder

            agg.total_credited_minutes += credited_minutes
            agg.total_xp_earned += earned_xp
            agg.total_coins_earned += earned_subcoins
            if not profile.minimal_mode:
                agg.coin_minutes_used += min(
                    credited_minutes,
                    max(0, 480 - agg.coin_minutes_used),
                )
            agg.session_count += 1

            await self._focus_repo.update_balance(balance)
            await self._gam_repo.update_profile(profile)
            await self._gam_repo.update_aggregate(agg)

            event = GamificationEvent(
                session_id=focus_session.id,
                event_type=GamificationEventType.session_reward,
                credited_minutes=credited_minutes,
                xp_earned=earned_xp,
                coins_earned=earned_subcoins,
                multiplier_breakdown=breakdown,
            )
            await self._gam_repo.create_event(event)

            self._logger.info(
                "gamification_session_awarded",
                session_id=str(focus_session.id),
                credited_minutes=credited_minutes,
                earned_xp=earned_xp,
                earned_subcoins=earned_subcoins,
            )

        return earned_xp, earned_subcoins, breakdown

    # ── Toggle minimal mode ──

    async def toggle_minimal_mode(self, enabled: bool) -> UserGamificationProfile:
        profile = await self.get_or_create_profile()
        profile.minimal_mode = enabled
        if not enabled:
            today = self._user_today(profile)
            profile.streak_finalized_through = today - timedelta(days=1)
            profile.consecutive_missed_focus_days = 0
            profile.recovery_days_remaining = 0
        return await self._gam_repo.update_profile(profile)

    # ── Roll-forward (lazy streak evaluation) ──

    async def roll_forward(self) -> UserGamificationProfile:
        """Evaluate all days from streak_finalized_through+1 to yesterday."""
        profile = await self.get_or_create_profile()
        today = self._user_today(profile)
        yesterday = today - timedelta(days=1)

        if (
            profile.streak_finalized_through is not None
            and profile.streak_finalized_through >= yesterday
        ):
            await self._set_today_recovery(profile, today)
            return profile

        start_date = (
            profile.streak_finalized_through + timedelta(days=1)
            if profile.streak_finalized_through is not None
            else yesterday
        )

        if start_date > yesterday:
            await self._set_today_recovery(profile, today)
            return profile

        plan_minutes = parse_plan_minutes(profile.plan_minutes_json)
        aggregates = await self._gam_repo.list_aggregates(since=start_date, until=yesterday)
        agg_map = {a.focus_date: a for a in aggregates}

        non_final_statuses = [
            FocusSessionStatus.running.value,
        ]

        current = start_date
        while current <= yesterday:
            blocking_sessions = await self._gam_repo.get_sessions_by_day_and_statuses(
                current, non_final_statuses
            )
            if blocking_sessions:
                break

            agg = agg_map.get(current)
            credited = agg.total_credited_minutes if agg else 0
            weekday = current.isoweekday()
            focus_day = is_focus_day(plan_minutes, weekday)
            plan_mins = get_plan_for_weekday(plan_minutes, weekday)

            # Recovery tracking (only for focus days)
            if not profile.minimal_mode and focus_day:
                if credited == 0:
                    profile.consecutive_missed_focus_days += 1
                else:
                    profile.consecutive_missed_focus_days = 0

                # Trigger recovery if threshold reached and not already in recovery
                if (
                    profile.consecutive_missed_focus_days >= RECOVERY_TRIGGER_MISSED_FOCUS_DAYS
                    and profile.recovery_days_remaining == 0
                ):
                    profile.recovery_days_remaining = RECOVERY_DURATION_FOCUS_DAYS

                # Decrement recovery for every focus day during recovery period,
                # but only if recovery was already active before this iteration
                elif profile.recovery_days_remaining > 0:
                    profile.recovery_days_remaining -= 1

            # Streak evaluation (only for focus days, not minimal mode)
            if not profile.minimal_mode and focus_day:
                streak_day = profile.streak_current + 1
                threshold = streak_threshold(plan_mins, streak_day)

                if credited >= threshold:
                    # Streak success
                    profile.streak_current += 1

                    # Shield recharge progress
                    if profile.shield_charges == 0 and profile.shield_unlocked:
                        profile.shield_recharge_progress = min(
                            SHIELD_RECHARGE_SUCCESS_DAYS,
                            profile.shield_recharge_progress + 1,
                        )
                    else:
                        profile.shield_recharge_progress = 0

                    # Shield unlock
                    if (
                        profile.streak_current >= SHIELD_UNLOCK_STREAK_LEN
                        and not profile.shield_unlocked
                    ):
                        profile.shield_unlocked = True
                        profile.shield_charges = 1
                        profile.shield_recharge_progress = 0

                    # Shield recharge check
                    if (
                        profile.shield_unlocked
                        and profile.shield_charges == 0
                        and profile.shield_recharge_progress >= SHIELD_RECHARGE_SUCCESS_DAYS
                    ):
                        profile.shield_charges = 1
                        profile.shield_recharge_progress = 0

                        recharge_event = GamificationEvent(
                            event_type=GamificationEventType.shield_recharge,
                            multiplier_breakdown={
                                "date": str(current),
                                "streak": profile.streak_current,
                            },
                        )
                        await self._gam_repo.create_event(recharge_event)

                    event = GamificationEvent(
                        event_type=GamificationEventType.streak_increment,
                        multiplier_breakdown={
                            "date": str(current),
                            "streak": profile.streak_current,
                        },
                    )
                    await self._gam_repo.create_event(event)
                else:
                    # Streak day failure
                    if profile.shield_unlocked and profile.shield_charges >= 1:
                        profile.shield_charges = 0
                        profile.shield_recharge_progress = 0

                        shield_event = GamificationEvent(
                            event_type=GamificationEventType.shield_spend,
                            multiplier_breakdown={
                                "date": str(current),
                                "streak": profile.streak_current,
                            },
                        )
                        await self._gam_repo.create_event(shield_event)
                    else:
                        old_streak = profile.streak_current
                        profile.streak_current = 0
                        profile.shield_recharge_progress = 0

                        if old_streak > 0:
                            event = GamificationEvent(
                                event_type=GamificationEventType.streak_reset,
                                multiplier_breakdown={
                                    "previous_streak": old_streak,
                                    "date": str(current),
                                },
                            )
                            await self._gam_repo.create_event(event)

            profile.streak_finalized_through = current
            current += timedelta(days=1)

        await self._set_today_recovery(profile, today)
        await self._gam_repo.update_profile(profile)
        return profile

    async def _set_today_recovery(self, profile: UserGamificationProfile, today: date) -> None:
        """Set recovery_mode on today's aggregate based on recovery_days_remaining."""
        if profile.minimal_mode:
            return

        recovery = "recovery" if profile.recovery_days_remaining > 0 else None

        today_agg = await self._gam_repo.get_aggregate(today)
        if today_agg is None:
            today_agg = await self._gam_repo.create_aggregate(today)
        if today_agg.recovery_mode is None and today_agg.total_credited_minutes == 0:
            today_agg.recovery_mode = recovery
            await self._gam_repo.update_aggregate(today_agg)

            if recovery:
                event = GamificationEvent(
                    event_type=GamificationEventType.recovery_activated,
                    multiplier_breakdown={
                        "mode": recovery,
                        "recovery_days_remaining": profile.recovery_days_remaining,
                        "date": str(today),
                    },
                )
                await self._gam_repo.create_event(event)

    # ── Daily stats ──

    async def get_daily_stats(self, days: int = 7) -> list[dict]:
        profile = await self.get_or_create_profile()
        today = self._user_today(profile)
        since = today - timedelta(days=days - 1)

        plan_minutes = parse_plan_minutes(profile.plan_minutes_json)
        aggregates = await self._gam_repo.list_aggregates(since=since, until=today)
        agg_map = {a.focus_date: a for a in aggregates}

        result = []
        current = since
        while current <= today:
            weekday = current.isoweekday()
            is_streak = is_focus_day(plan_minutes, weekday)
            agg = agg_map.get(current)

            credited = agg.total_credited_minutes if agg else 0
            recovery = agg.recovery_mode if agg else None

            result.append(
                {
                    "date": str(current),
                    "credited_minutes": credited,
                    "xp_earned": agg.total_xp_earned if agg else 0,
                    "coins_earned": agg.total_coins_earned if agg else 0,
                    "session_count": agg.session_count if agg else 0,
                    "is_streak_day": is_streak,
                    "recovery_mode": recovery,
                }
            )
            current += timedelta(days=1)

        return result
