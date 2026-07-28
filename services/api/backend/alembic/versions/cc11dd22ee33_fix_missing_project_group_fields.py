"""ensure project_id/group_id columns exist on tasks/notes

Revision ID: cc11dd22ee33
Revises: 987ae03f193d
Create Date: 2026-01-23 12:10:00.000000
"""
from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "cc11dd22ee33"
down_revision = "987ae03f193d"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Backfill schema drift: add columns/indexes only if missing.
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS project_id VARCHAR(255)")
	op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS group_id VARCHAR(255)")
	op.execute("ALTER TABLE notes ADD COLUMN IF NOT EXISTS group_id VARCHAR(255)")
	op.execute("CREATE INDEX IF NOT EXISTS ix_tasks_project_id ON tasks (project_id)")
	op.execute("CREATE INDEX IF NOT EXISTS ix_tasks_group_id ON tasks (group_id)")
	op.execute("CREATE INDEX IF NOT EXISTS ix_notes_group_id ON notes (group_id)")


def downgrade() -> None:
	# Conservative rollback: drop indexes/columns if present.
	op.execute("DROP INDEX IF EXISTS ix_notes_group_id")
	op.execute("DROP INDEX IF EXISTS ix_tasks_group_id")
	op.execute("DROP INDEX IF EXISTS ix_tasks_project_id")
	op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS group_id")
	op.execute("ALTER TABLE tasks DROP COLUMN IF EXISTS group_id")
	op.execute("ALTER TABLE tasks DROP COLUMN IF EXISTS project_id")
