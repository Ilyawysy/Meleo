"""Gamification plan rework: plan_minutes_json replaces plan_day_minutes + streak_days_json

Revision ID: tt11
Revises: ss11
Create Date: 2026-03-08
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import text
from sqlalchemy.dialects.postgresql import UUID as PGUUID

revision = "tt11"
down_revision = "ss11"
branch_labels = None
depends_on = None

_DEFAULT_PLAN_JSON = '{"1":30,"2":0,"3":30,"4":0,"5":30,"6":0,"7":0}'


def upgrade() -> None:
    # Add new columns
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "plan_minutes_json",
            sa.Text(),
            nullable=False,
            server_default=_DEFAULT_PLAN_JSON,
        ),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "recovery_days_remaining",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "consecutive_missed_focus_days",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "plan_changed_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    # Data migration: build plan_minutes_json from streak_days_json + plan_day_minutes
    op.execute(
        text(
            """
            UPDATE user_gamification_profile
            SET plan_minutes_json = (
                SELECT
                    jsonb_build_object(
                        '1', CASE WHEN 1 = ANY(days_arr) THEN plan_day_minutes ELSE 0 END,
                        '2', CASE WHEN 2 = ANY(days_arr) THEN plan_day_minutes ELSE 0 END,
                        '3', CASE WHEN 3 = ANY(days_arr) THEN plan_day_minutes ELSE 0 END,
                        '4', CASE WHEN 4 = ANY(days_arr) THEN plan_day_minutes ELSE 0 END,
                        '5', CASE WHEN 5 = ANY(days_arr) THEN plan_day_minutes ELSE 0 END,
                        '6', CASE WHEN 6 = ANY(days_arr) THEN plan_day_minutes ELSE 0 END,
                        '7', CASE WHEN 7 = ANY(days_arr) THEN plan_day_minutes ELSE 0 END
                    )::text
                FROM (
                    SELECT
                        plan_day_minutes,
                        ARRAY(
                            SELECT jsonb_array_elements_text(
                                COALESCE(streak_days_json::jsonb, '[1,3,5]'::jsonb)
                            )::int
                        ) AS days_arr
                ) sub
            )
            """
        )
    )

    # Copy streak_days_changed_at → plan_changed_at
    op.execute(
        text("UPDATE user_gamification_profile SET plan_changed_at = streak_days_changed_at")
    )

    # Drop old columns
    op.drop_column("user_gamification_profile", "plan_day_minutes")
    op.drop_column("user_gamification_profile", "streak_days_json")
    op.drop_column("user_gamification_profile", "streak_days_changed_at")
    op.drop_column("user_gamification_profile", "missed_planned_no_focus_days")

    # Drop streak_plan_history table
    op.drop_table("streak_plan_history")


def downgrade() -> None:
    # Recreate streak_plan_history
    op.create_table(
        "streak_plan_history",
        sa.Column("id", PGUUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            PGUUID(as_uuid=True),
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
    )
    op.create_unique_constraint(
        "uq_streak_plan_history_user_date",
        "streak_plan_history",
        ["user_id", "effective_from_focus_date"],
    )
    op.create_index(
        "ix_streak_plan_history_user_date",
        "streak_plan_history",
        ["user_id", "effective_from_focus_date"],
    )

    # Re-add old columns
    op.add_column(
        "user_gamification_profile",
        sa.Column("plan_day_minutes", sa.Integer(), nullable=False, server_default="30"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "streak_days_json",
            sa.Text(),
            nullable=False,
            server_default="[1,3,5]",
        ),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "streak_days_changed_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "missed_planned_no_focus_days",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )

    # Data migration: reverse plan_minutes_json → plan_day_minutes + streak_days_json
    op.execute(
        text(
            """
            UPDATE user_gamification_profile
            SET
                plan_day_minutes = (
                    SELECT GREATEST(
                        COALESCE((plan_minutes_json::jsonb->>'1')::int, 0),
                        COALESCE((plan_minutes_json::jsonb->>'2')::int, 0),
                        COALESCE((plan_minutes_json::jsonb->>'3')::int, 0),
                        COALESCE((plan_minutes_json::jsonb->>'4')::int, 0),
                        COALESCE((plan_minutes_json::jsonb->>'5')::int, 0),
                        COALESCE((plan_minutes_json::jsonb->>'6')::int, 0),
                        COALESCE((plan_minutes_json::jsonb->>'7')::int, 0),
                        30
                    )
                ),
                streak_days_json = (
                    SELECT json_agg(k::int ORDER BY k::int)::text
                    FROM jsonb_each_text(plan_minutes_json::jsonb) kv(k, v)
                    WHERE v::int > 0
                ),
                streak_days_changed_at = plan_changed_at,
                missed_planned_no_focus_days = consecutive_missed_focus_days
            """
        )
    )

    # Drop new columns
    op.drop_column("user_gamification_profile", "plan_minutes_json")
    op.drop_column("user_gamification_profile", "recovery_days_remaining")
    op.drop_column("user_gamification_profile", "consecutive_missed_focus_days")
    op.drop_column("user_gamification_profile", "plan_changed_at")
