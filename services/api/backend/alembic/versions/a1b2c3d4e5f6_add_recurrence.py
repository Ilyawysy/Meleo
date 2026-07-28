"""add recurrence column and enum

Revision ID: a1b2c3d4e5f6
Revises: 9eaa808bac9e
Create Date: 2025-10-11 16:20:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
from sqlalchemy import inspect, text

# revision identifiers, used by Alembic.
revision = "a1b2c3d4e5f6"
down_revision = "9eaa808bac9e"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Create enum type if not exists
	op.execute(
		"""
		DO $$
		BEGIN
			IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_recurrence') THEN
				CREATE TYPE task_recurrence AS ENUM ('none','daily','weekly');
			END IF;
		END$$;
		"""
	)

	bind = op.get_bind()
	insp = inspect(bind)

	# Ensure tasks table exists minimally if missing (in case earlier revs were empty)
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

	recurrence_enum = postgresql.ENUM('none', 'daily', 'weekly', name='task_recurrence', create_type=False)

	# Add column only if missing
	cols = [c["name"] for c in insp.get_columns("tasks")]
	if "recurrence" not in cols:
		op.add_column(
			"tasks",
			sa.Column("recurrence", recurrence_enum, nullable=False, server_default="none"),
		)
		# drop default after backfill
		op.alter_column("tasks", "recurrence", server_default=None)


def downgrade() -> None:
	# Drop column first if exists
	bind = op.get_bind()
	insp = inspect(bind)
	cols = [c["name"] for c in insp.get_columns("tasks")] if insp.has_table("tasks") else []
	if "recurrence" in cols:
		op.drop_column("tasks", "recurrence")
	# Then drop enum type safely
	op.execute("DO $$ BEGIN DROP TYPE IF EXISTS task_recurrence; EXCEPTION WHEN undefined_object THEN NULL; END $$;")
