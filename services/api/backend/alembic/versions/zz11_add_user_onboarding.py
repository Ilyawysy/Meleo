"""add onboarding_completed_at to users

Revision ID: zz11_add_user_onboarding
Revises: yy11_add_aura_skin_env_shop
Create Date: 2026-04-14 00:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "zz11_add_user_onboarding"
down_revision = "yy11_add_aura_skin_env_shop"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("onboarding_completed_at", sa.DateTime(timezone=True), nullable=True),
    )
    # Protect existing prod users from seeing onboarding again after deploy.
    op.execute(
        "UPDATE users SET onboarding_completed_at = NOW() WHERE onboarding_completed_at IS NULL"
    )


def downgrade() -> None:
    op.drop_column("users", "onboarding_completed_at")
