"""Add adaptive plan columns and longest_streak to user_gamification_profile

Revision ID: cccc_adaptive_plan_and_longest_streak
Revises: bbbb_focus_version_triggers
Create Date: 2026-04-22 00:00:00.000000
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision = "cccc_adaptive_plan_and_longest_streak"
down_revision = "bbbb_focus_version_triggers"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "user_gamification_profile",
        sa.Column("plan_hours_per_day", JSONB(), nullable=True),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("plan_hours_changed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("growth_target_hours", sa.Integer(), nullable=True),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("growth_speed", sa.String(16), nullable=True),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("growth_started_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "longest_streak",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.create_check_constraint(
        "ck_ugp_growth_speed",
        "user_gamification_profile",
        "growth_speed IS NULL OR growth_speed IN ('steady','faster','push')",
    )
    op.execute(
        "UPDATE user_gamification_profile"
        " SET longest_streak = GREATEST(longest_streak, streak_current)"
    )


def downgrade() -> None:
    op.drop_constraint("ck_ugp_growth_speed", "user_gamification_profile", type_="check")
    op.drop_column("user_gamification_profile", "longest_streak")
    op.drop_column("user_gamification_profile", "growth_started_at")
    op.drop_column("user_gamification_profile", "growth_speed")
    op.drop_column("user_gamification_profile", "growth_target_hours")
    op.drop_column("user_gamification_profile", "plan_hours_changed_at")
    op.drop_column("user_gamification_profile", "plan_hours_per_day")
