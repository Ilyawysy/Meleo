"""add awaiting_confirm to focus_session_status enum

Revision ID: gg11_await
Revises: fe12ab34cd56
Create Date: 2026-02-07 12:00:00.000000
"""
from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "gg11_await"
down_revision = "fe12ab34cd56"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# ALTER TYPE ... ADD VALUE cannot run inside a transaction in Postgres.
	# We must commit the current transaction, add the value, then start a new one.
	op.execute("COMMIT")
	op.execute("ALTER TYPE focus_session_status ADD VALUE IF NOT EXISTS 'awaiting_confirm'")
	op.execute("BEGIN")


def downgrade() -> None:
	# Postgres does not support removing enum values.
	# The value 'awaiting_confirm' will remain but is harmless.
	pass
