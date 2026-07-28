"""Drop shield and freeze columns from gamification tables.

Revision ID: pp11
Revises: oo33
Create Date: 2026-03-05
"""

from __future__ import annotations

from alembic import op


revision = "pp11"
down_revision = "oo33"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_column("user_gamification_profile", "shield_unlocked")
    op.drop_column("user_gamification_profile", "shield_charges")
    op.drop_column("user_gamification_profile", "shield_recharge_progress")
    op.drop_column("user_gamification_profile", "freeze_count")
    op.drop_column("user_gamification_profile", "auto_freeze_enabled")
    op.drop_column("daily_focus_aggregate", "freeze_applied")


def downgrade() -> None:
    import sqlalchemy as sa

    op.add_column(
        "daily_focus_aggregate",
        sa.Column("freeze_applied", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("auto_freeze_enabled", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("freeze_count", sa.Integer(), nullable=False, server_default="10"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("shield_recharge_progress", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("shield_charges", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("shield_unlocked", sa.Boolean(), nullable=False, server_default="false"),
    )
