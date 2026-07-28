"""
add user_id to tasks

Revision ID: ff12aabbccdd
Revises: d1e2f3a4b5c6
Create Date: 2025-10-15
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "ff12aabbccdd"
down_revision = "d1e2f3a4b5c6"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"tasks",
		sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=True),
	)
	op.create_index("ix_tasks_user_id", "tasks", ["user_id"], unique=False)


def downgrade() -> None:
	op.drop_index("ix_tasks_user_id", table_name="tasks")
	op.drop_column("tasks", "user_id")
