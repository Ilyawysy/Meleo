"""add session settings columns to user_gamification_profile

Revision ID: vv11
Revises: uu11
Create Date: 2026-03-11
"""

from alembic import op
import sqlalchemy as sa

revision = "vv11"
down_revision = "uu11"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "user_gamification_profile",
        sa.Column("focus_duration_min", sa.Integer(), nullable=False, server_default="25"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("short_break_min", sa.Integer(), nullable=False, server_default="5"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("long_break_min", sa.Integer(), nullable=False, server_default="15"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("sessions_before_long_break", sa.Integer(), nullable=False, server_default="4"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("auto_start_break", sa.Boolean(), nullable=False, server_default="true"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column("auto_start_next_session", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "adjust_duration_after_session", sa.Boolean(), nullable=False, server_default="false"
        ),
    )


def downgrade() -> None:
    op.drop_column("user_gamification_profile", "adjust_duration_after_session")
    op.drop_column("user_gamification_profile", "auto_start_next_session")
    op.drop_column("user_gamification_profile", "auto_start_break")
    op.drop_column("user_gamification_profile", "sessions_before_long_break")
    op.drop_column("user_gamification_profile", "long_break_min")
    op.drop_column("user_gamification_profile", "short_break_min")
    op.drop_column("user_gamification_profile", "focus_duration_min")
