"""gamification v0.10.2: shield, recovery, undo, new level curve, remove freeze/boost/mmr

Revision ID: mm11_gam_v102
Revises: ll55mm66nn77
Create Date: 2026-02-25 12:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "mm11_gam_v102"
down_revision = "ll55mm66nn77"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 1. Add new enum values to focus_session_status ──
    op.execute("COMMIT")
    op.execute("ALTER TYPE focus_session_status ADD VALUE IF NOT EXISTS 'stopped_pending_credit'")
    op.execute("ALTER TYPE focus_session_status ADD VALUE IF NOT EXISTS 'credited_undoable'")
    op.execute("ALTER TYPE focus_session_status ADD VALUE IF NOT EXISTS 'credited_final'")
    op.execute("ALTER TYPE focus_session_status ADD VALUE IF NOT EXISTS 'cancelled'")
    op.execute("BEGIN")

    # ── 2. Add new enum values to gamification_event_type ──
    op.execute("COMMIT")
    op.execute("ALTER TYPE gamification_event_type ADD VALUE IF NOT EXISTS 'shield_spend'")
    op.execute("ALTER TYPE gamification_event_type ADD VALUE IF NOT EXISTS 'shield_recharge'")
    op.execute("ALTER TYPE gamification_event_type ADD VALUE IF NOT EXISTS 'recovery_activated'")
    op.execute("ALTER TYPE gamification_event_type ADD VALUE IF NOT EXISTS 'session_undo'")
    op.execute("BEGIN")

    # ── 3. Add v0.10.2 columns to user_gamification_profile ──
    op.add_column(
        "user_gamification_profile",
        sa.Column("home_tz", sa.String(50), nullable=False, server_default="UTC"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("home_tz_set_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("day_cutoff_hour", sa.Integer(), nullable=False, server_default="4"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("day_cutoff_changed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("plan_day_minutes", sa.Integer(), nullable=False, server_default="30"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("streak_days_json", sa.Text(), nullable=False, server_default="[1,2,3,4,5]"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("streak_days_changed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("shield_unlocked", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("shield_charges", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("shield_recharge_progress", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("missed_planned_no_focus_days", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("coin_remainder", sa.Float(), nullable=False, server_default="0.0"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("minimal_mode", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("streak_finalized_through", sa.Date(), nullable=True),
    )

    # ── 4. Add v0.10.2 columns to daily_focus_aggregate ──
    op.add_column(
        "daily_focus_aggregate",
        sa.Column("coin_minutes_used", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "daily_focus_aggregate",
        sa.Column("recovery_mode", sa.String(10), nullable=True),
    )

    # ── 5. Add v0.10.2 columns to focus_sessions ──
    op.add_column(
        "focus_sessions",
        sa.Column("session_day", sa.Date(), nullable=True),
    )
    op.add_column(
        "focus_sessions",
        sa.Column("undo_deadline_at", sa.DateTime(timezone=True), nullable=True),
    )

    # ── 6. Create streak_plan_history table ──
    op.create_table(
        "streak_plan_history",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id"),
            nullable=False,
        ),
        sa.Column("effective_from_focus_date", sa.Date(), nullable=False),
        sa.Column("streak_days", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.UniqueConstraint(
            "user_id",
            "effective_from_focus_date",
            name="uq_streak_plan_history_user_date",
        ),
    )
    op.create_index(
        "ix_streak_plan_history_user_date",
        "streak_plan_history",
        ["user_id", "effective_from_focus_date"],
    )

    # ── 7. Data migration ──
    # 7a. Copy timezone → home_tz
    op.execute("UPDATE user_gamification_profile SET home_tz = timezone")

    # 7b. Convert scheduled_days_mask bitmask → streak_days_json array
    # Bitmask: bit 0 = Monday, bit 1 = Tuesday, ..., bit 6 = Sunday
    # Spec weekdays: 1 = Monday, 2 = Tuesday, ..., 7 = Sunday
    op.execute(
        """
		UPDATE user_gamification_profile
		SET streak_days_json = (
			SELECT COALESCE(
				'[' || string_agg(d::text, ',' ORDER BY d) || ']',
				'[]'
			)
			FROM generate_series(0, 6) AS s(bit_pos),
			     LATERAL (SELECT bit_pos + 1 AS d) AS mapped
			WHERE (scheduled_days_mask & (1 << bit_pos)) != 0
		)
		"""
    )

    # 7c. goal_minutes → plan_day_minutes (round to nearest 10)
    op.execute(
        """
		UPDATE user_gamification_profile
		SET plan_day_minutes = GREATEST(10, (ROUND(goal_minutes::numeric / 10) * 10)::integer)
		"""
    )

    # 7d. streak_updated_date → streak_finalized_through
    op.execute(
        "UPDATE user_gamification_profile SET streak_finalized_through = streak_updated_date"
    )

    # 7e. Create initial streak_plan_history from current streak_days
    op.execute(
        """
		INSERT INTO streak_plan_history (id, user_id, effective_from_focus_date, streak_days, created_at)
		SELECT gen_random_uuid(), user_id, COALESCE(created_at::date, CURRENT_DATE), streak_days_json, NOW()
		FROM user_gamification_profile
		"""
    )

    # 7f. Convert awaiting_confirm → stopped_pending_credit
    op.execute(
        """
		UPDATE focus_sessions
		SET status = 'stopped_pending_credit'
		WHERE status = 'awaiting_confirm'
		"""
    )

    # 7g. Convert completed (with credited_minutes > 0) → credited_final
    op.execute(
        """
		UPDATE focus_sessions
		SET status = 'credited_final'
		WHERE status = 'completed' AND credited_minutes IS NOT NULL AND credited_minutes > 0
		"""
    )

    # 7h. Convert completed (with credited_minutes = 0 or NULL) → cancelled
    op.execute(
        """
		UPDATE focus_sessions
		SET status = 'cancelled'
		WHERE status = 'completed' AND (credited_minutes IS NULL OR credited_minutes = 0)
		"""
    )

    # 7i. Shield: unlock for users with streak_current >= 3
    op.execute(
        """
		UPDATE user_gamification_profile
		SET shield_unlocked = true
		WHERE streak_current >= 3
		"""
    )


def downgrade() -> None:
    # ── Reverse data migration ──
    # Convert new statuses back to old
    op.execute(
        "UPDATE focus_sessions SET status = 'awaiting_confirm' WHERE status = 'stopped_pending_credit'"
    )
    op.execute("UPDATE focus_sessions SET status = 'completed' WHERE status = 'credited_final'")
    op.execute("UPDATE focus_sessions SET status = 'completed' WHERE status = 'credited_undoable'")
    op.execute("UPDATE focus_sessions SET status = 'completed' WHERE status = 'cancelled'")

    # ── Drop streak_plan_history ──
    op.drop_index("ix_streak_plan_history_user_date", table_name="streak_plan_history")
    op.drop_table("streak_plan_history")

    # ── Drop focus_sessions columns ──
    op.drop_column("focus_sessions", "undo_deadline_at")
    op.drop_column("focus_sessions", "session_day")

    # ── Drop daily_focus_aggregate columns ──
    op.drop_column("daily_focus_aggregate", "recovery_mode")
    op.drop_column("daily_focus_aggregate", "coin_minutes_used")

    # ── Drop user_gamification_profile v0.10.2 columns ──
    op.drop_column("user_gamification_profile", "streak_finalized_through")
    op.drop_column("user_gamification_profile", "minimal_mode")
    op.drop_column("user_gamification_profile", "coin_remainder")
    op.drop_column("user_gamification_profile", "missed_planned_no_focus_days")
    op.drop_column("user_gamification_profile", "shield_recharge_progress")
    op.drop_column("user_gamification_profile", "shield_charges")
    op.drop_column("user_gamification_profile", "shield_unlocked")
    op.drop_column("user_gamification_profile", "streak_days_changed_at")
    op.drop_column("user_gamification_profile", "streak_days_json")
    op.drop_column("user_gamification_profile", "plan_day_minutes")
    op.drop_column("user_gamification_profile", "day_cutoff_changed_at")
    op.drop_column("user_gamification_profile", "day_cutoff_hour")
    op.drop_column("user_gamification_profile", "home_tz_set_at")
    op.drop_column("user_gamification_profile", "home_tz")

    # Note: Cannot remove enum values from PostgreSQL. The new values
    # (stopped_pending_credit, credited_undoable, credited_final, cancelled,
    # shield_spend, shield_recharge, recovery_activated, session_undo)
    # will remain but be unused after downgrade.
