"""add deleted flag to tasks

Revision ID: c9d0e1f2a3b4
Revises: b7c8d9e0f1a2
Create Date: 2025-10-11 17:12:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect, text

# revision identifiers, used by Alembic.
revision = "c9d0e1f2a3b4"
down_revision = "b7c8d9e0f1a2"
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	insp = inspect(bind)

	# Ensure tasks exists (minimal) if missing
	if not insp.has_table("tasks"):
		op.execute(
			text(
				"""
				CREATE TABLE IF NOT EXISTS tasks (
					id uuid PRIMARY KEY,
					created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
					updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
				)
				"""
			)
		)

	cols = [c["name"] for c in insp.get_columns("tasks")]
	if "deleted" not in cols:
		op.add_column("tasks", sa.Column("deleted", sa.Boolean(), nullable=False, server_default="false"))


def downgrade() -> None:
	bind = op.get_bind()
	insp = inspect(bind)
	if insp.has_table("tasks"):
		cols = [c["name"] for c in insp.get_columns("tasks")]
		if "deleted" in cols:
			op.drop_column("tasks", "deleted")
