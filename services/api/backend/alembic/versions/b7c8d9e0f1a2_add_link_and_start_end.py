"""add link_url, start_at, end_at to tasks

Revision ID: b7c8d9e0f1a2
Revises: a1b2c3d4e5f6
Create Date: 2025-10-11 16:24:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect, text

# revision identifiers, used by Alembic.
revision = "b7c8d9e0f1a2"
down_revision = "a1b2c3d4e5f6"
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
	if "link_url" not in cols:
		op.add_column("tasks", sa.Column("link_url", sa.String(length=1024), nullable=True))
	if "start_at" not in cols:
		op.add_column("tasks", sa.Column("start_at", sa.DateTime(timezone=True), nullable=True))
	if "end_at" not in cols:
		op.add_column("tasks", sa.Column("end_at", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
	bind = op.get_bind()
	insp = inspect(bind)
	if insp.has_table("tasks"):
		cols = [c["name"] for c in insp.get_columns("tasks")]
		if "end_at" in cols:
			op.drop_column("tasks", "end_at")
		if "start_at" in cols:
			op.drop_column("tasks", "start_at")
		if "link_url" in cols:
			op.drop_column("tasks", "link_url")
