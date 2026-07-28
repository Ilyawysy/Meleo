"""Restore users.email for expand-compatible deployments.

Revision ID: jjjj_restore_users_email_expand
Revises: iiii_drop_users_email
Create Date: 2026-07-26 00:00:00.000000
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "jjjj_restore_users_email_expand"
down_revision = "iiii_drop_users_email"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("email", sa.String(length=255), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "email")
