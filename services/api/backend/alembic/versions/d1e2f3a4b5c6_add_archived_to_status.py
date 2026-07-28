"""add archived value to task_status enum

Revision ID: d1e2f3a4b5c6
Revises: c9d0e1f2a3b4
Create Date: 2025-10-11 19:00:00.000000
"""
from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "d1e2f3a4b5c6"
down_revision = "c9d0e1f2a3b4"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Ensure enum exists, then ensure value exists
	op.execute(
		"""
		DO $$
		BEGIN
			IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_status') THEN
				CREATE TYPE task_status AS ENUM ('pending','in_progress','done','archived');
			ELSIF NOT EXISTS (
				SELECT 1 FROM pg_enum e
				JOIN pg_type t ON e.enumtypid = t.oid
				WHERE t.typname = 'task_status' AND e.enumlabel = 'archived'
			) THEN
				ALTER TYPE task_status ADD VALUE 'archived';
			END IF;
		END$$;
		"""
	)


def downgrade() -> None:
	# Cannot remove enum value in PostgreSQL easily; leave as is.
	pass
