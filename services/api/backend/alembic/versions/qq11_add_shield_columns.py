"""Add shield columns back to user_gamification_profile.

Shield was dropped in pp11 (along with freeze). Now re-adding only shield
fields per spec v0.10.2 section 7.

Revision ID: qq11
Revises: pp22
Create Date: 2026-03-06
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "qq11"
down_revision = "pp22"
branch_labels = None
depends_on = None


def upgrade() -> None:
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

    # Unlock shield for users who already have streak >= 3
    op.execute(
        """
        UPDATE user_gamification_profile
        SET shield_unlocked = true, shield_charges = 1
        WHERE streak_current >= 3
        """
    )


def downgrade() -> None:
    op.drop_column("user_gamification_profile", "shield_recharge_progress")
    op.drop_column("user_gamification_profile", "shield_charges")
    op.drop_column("user_gamification_profile", "shield_unlocked")
