"""add gamification tables, columns, shop cleanup, subcoin conversion

Revision ID: gg22_gamif
Revises: gg11_await
Create Date: 2026-02-07 12:01:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "gg22_gamif"
down_revision = "gg11_await"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# ── 1. Create new enums ──
	op.execute(
		"""
		DO $$
		BEGIN
			IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'gamification_event_type') THEN
				CREATE TYPE gamification_event_type AS ENUM (
					'session_reward', 'freeze_purchase', 'freeze_use', 'streak_reset', 'streak_increment'
				);
			END IF;
		END$$;
		"""
	)

	# ── 2. Add new values to shop_item_category enum ──
	op.execute("COMMIT")
	op.execute("ALTER TYPE shop_item_category ADD VALUE IF NOT EXISTS 'theme'")
	op.execute("ALTER TYPE shop_item_category ADD VALUE IF NOT EXISTS 'freeze'")
	op.execute("BEGIN")

	# ── 3. Create user_gamification_profile table ──
	op.create_table(
		"user_gamification_profile",
		sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), primary_key=True),
		sa.Column("xp", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("streak_current", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("streak_updated_date", sa.Date(), nullable=True),
		sa.Column("mmr", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("goal_minutes", sa.Integer(), nullable=False, server_default="60"),
		sa.Column("scheduled_days_mask", sa.Integer(), nullable=False, server_default="31"),
		sa.Column("timezone", sa.String(length=50), nullable=False, server_default="UTC"),
		sa.Column("freeze_count", sa.Integer(), nullable=False, server_default="10"),
		sa.Column("auto_freeze_enabled", sa.Boolean(), nullable=False, server_default="false"),
		sa.Column("fair_play_accepted", sa.Boolean(), nullable=False, server_default="false"),
		sa.Column("fair_play_accepted_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
		sa.Column(
			"updated_at",
			sa.DateTime(timezone=True),
			nullable=False,
			server_default=sa.func.now(),
		),
	)

	# ── 4. Create daily_focus_aggregate table ──
	op.create_table(
		"daily_focus_aggregate",
		sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
		sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
		sa.Column("focus_date", sa.Date(), nullable=False),
		sa.Column("total_credited_minutes", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("total_xp_earned", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("total_coins_earned", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("session_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("freeze_applied", sa.Boolean(), nullable=False, server_default="false"),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
		sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
		sa.UniqueConstraint("user_id", "focus_date", name="uq_daily_focus_aggregate_user_id_focus_date"),
	)
	op.create_index(
		"ix_daily_focus_aggregate_user_date",
		"daily_focus_aggregate",
		["user_id", "focus_date"],
	)

	# ── 5. Create gamification_events table ──
	op.create_table(
		"gamification_events",
		sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
		sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
		sa.Column("session_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("focus_sessions.id"), nullable=True),
		sa.Column(
			"event_type",
			postgresql.ENUM(
				"session_reward",
				"freeze_purchase",
				"freeze_use",
				"streak_reset",
				"streak_increment",
				name="gamification_event_type",
				create_type=False,
			),
			nullable=False,
		),
		sa.Column("credited_minutes", sa.Integer(), nullable=True),
		sa.Column("xp_earned", sa.Integer(), nullable=True),
		sa.Column("coins_earned", sa.Integer(), nullable=True),
		sa.Column("multiplier_breakdown", postgresql.JSONB(), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
	)
	op.create_index(
		"ix_gamification_events_user_created",
		"gamification_events",
		["user_id", "created_at"],
	)

	# ── 6. Add columns to focus_sessions ──
	op.add_column("focus_sessions", sa.Column("credited_minutes", sa.Integer(), nullable=True))
	op.add_column(
		"focus_sessions",
		sa.Column("earned_xp", sa.Integer(), nullable=False, server_default="0"),
	)

	# ── 7. Data migration: convert to subcoins (×10) ──
	op.execute("UPDATE user_balance SET coins = coins * 10")
	op.execute("UPDATE shop_items SET price = price * 10")
	op.execute("UPDATE focus_sessions SET earned_coins = earned_coins * 10")

	# ── 8. Backfill credited_minutes for completed sessions ──
	op.execute(
		"""
		UPDATE focus_sessions
		SET credited_minutes = active_elapsed_sec / 60
		WHERE status = 'completed' AND credited_minutes IS NULL
		"""
	)

	# ── 9. Backfill earned_xp for completed sessions that had rewards ──
	op.execute(
		"""
		UPDATE focus_sessions
		SET earned_xp = COALESCE(credited_minutes, 0)
		WHERE status = 'completed' AND earned_coins > 0 AND earned_xp = 0
		"""
	)

	# ── 10. Shop cleanup: delete old cosmetic items ──
	op.execute("DELETE FROM user_shop_items")
	op.execute("DELETE FROM shop_items")


def downgrade() -> None:
	# ── Reverse shop cleanup: re-seed old items ──
	# Note: IDs will be different, old user purchases are lost.
	op.execute(
		"""
		INSERT INTO shop_items (id, name, category, price, created_at, updated_at) VALUES
		(gen_random_uuid(), 'Шапка бини', 'hat', 50, now(), now()),
		(gen_random_uuid(), 'Кепка', 'hat', 70, now(), now()),
		(gen_random_uuid(), 'Худи', 'top', 120, now(), now()),
		(gen_random_uuid(), 'Футболка', 'top', 60, now(), now()),
		(gen_random_uuid(), 'Джинсы', 'bottom', 110, now(), now()),
		(gen_random_uuid(), 'Шорты', 'bottom', 80, now(), now()),
		(gen_random_uuid(), 'Кроссовки', 'shoes', 150, now(), now()),
		(gen_random_uuid(), 'Ботинки', 'shoes', 180, now(), now()),
		(gen_random_uuid(), 'Очки', 'accessory', 90, now(), now()),
		(gen_random_uuid(), 'Рюкзак', 'accessory', 140, now(), now())
		"""
	)

	# ── Reverse subcoin conversion (÷10) ──
	op.execute("UPDATE focus_sessions SET earned_coins = earned_coins / 10")
	op.execute("UPDATE shop_items SET price = price / 10")
	op.execute("UPDATE user_balance SET coins = coins / 10")

	# ── Remove added columns ──
	op.drop_column("focus_sessions", "earned_xp")
	op.drop_column("focus_sessions", "credited_minutes")

	# ── Drop gamification tables ──
	op.drop_index("ix_gamification_events_user_created", table_name="gamification_events")
	op.drop_table("gamification_events")

	op.drop_index("ix_daily_focus_aggregate_user_date", table_name="daily_focus_aggregate")
	op.drop_table("daily_focus_aggregate")

	op.drop_table("user_gamification_profile")

	# ── Drop new enum (cannot remove values from existing enums) ──
	op.execute("DROP TYPE IF EXISTS gamification_event_type")
