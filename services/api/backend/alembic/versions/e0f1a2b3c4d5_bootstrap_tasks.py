"""bootstrap tasks table and enums if missing

Revision ID: e0f1a2b3c4d5
Revises: d1e2f3a4b5c6
Create Date: 2025-10-14 00:00:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision = "e0f1a2b3c4d5"
down_revision = "d1e2f3a4b5c6"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Ensure enums exist
	op.execute(
		"""
		DO $$
		BEGIN
			IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_priority') THEN
				CREATE TYPE task_priority AS ENUM ('low','medium','high');
			END IF;
			IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_status') THEN
				CREATE TYPE task_status AS ENUM ('pending','in_progress','done','archived');
			END IF;
			IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_recurrence') THEN
				CREATE TYPE task_recurrence AS ENUM ('none','daily','weekly');
			END IF;
		END$$;
		"""
	)

	# Ensure table exists with all columns
	op.execute(
		text(
			"""
			CREATE TABLE IF NOT EXISTS tasks (
				id uuid PRIMARY KEY,
				title varchar(255) NOT NULL,
				description varchar(2048) NOT NULL DEFAULT '',
				priority task_priority NOT NULL DEFAULT 'medium',
				status task_status NOT NULL DEFAULT 'pending',
				due_at timestamptz NULL,
				recurrence task_recurrence NOT NULL DEFAULT 'none',
				link_url varchar(1024) NULL,
				start_at timestamptz NULL,
				end_at timestamptz NULL,
				deleted boolean NOT NULL DEFAULT false,
				created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
				updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
			);
			"""
		)
	)

	# Add missing columns individually (if table existed but lacked some)
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS title varchar(255) NOT NULL")
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS description varchar(2048) NOT NULL DEFAULT ''")
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS priority task_priority NOT NULL DEFAULT 'medium'")
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS status task_status NOT NULL DEFAULT 'pending'")
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS due_at timestamptz NULL")
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS recurrence task_recurrence NOT NULL DEFAULT 'none'")
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS link_url varchar(1024) NULL")
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS start_at timestamptz NULL")
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS end_at timestamptz NULL")
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS deleted boolean NOT NULL DEFAULT false")
	op.execute("CREATE INDEX IF NOT EXISTS ix_tasks_created_at ON tasks (created_at)")


def downgrade() -> None:
	# no-op bootstrap downgrade
	pass
