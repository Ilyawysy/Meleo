"""add theme_mode to user_gamification_profile

Revision ID: uu11
Revises: tt11
Create Date: 2026-03-08
"""

from alembic import op
import sqlalchemy as sa

revision = "uu11"
down_revision = "tt11"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "theme_mode",
            sa.String(length=10),
            nullable=False,
            server_default="system",
        ),
    )


def downgrade() -> None:
    op.drop_column("user_gamification_profile", "theme_mode")
