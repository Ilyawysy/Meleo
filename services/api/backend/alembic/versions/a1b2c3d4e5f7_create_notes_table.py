"""create notes table

Revision ID: a1b2c3d4e5f7
Revises: ff12aabbccdd
Create Date: 2025-10-21 12:00:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "a1b2c3d4e5f7"
down_revision = "ff12aabbccdd"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"notes",
		sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
		sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("task_id", postgresql.UUID(as_uuid=True), nullable=True),
		sa.Column("title", sa.String(length=255), nullable=False),
		sa.Column("text", sa.Text(), nullable=False),
		sa.Column("deleted", sa.Boolean(), nullable=False, server_default="false"),
		sa.Column(
			"created_at",
			sa.DateTime(timezone=True),
			nullable=False,
			server_default=sa.text("timezone('utc', now())"),
		),
		sa.Column(
			"updated_at",
			sa.DateTime(timezone=True),
			nullable=False,
			server_default=sa.text("timezone('utc', now())"),
		),
		sa.ForeignKeyConstraint(
			["task_id"], 
			["tasks.id"], 
			name="fk_notes_task_id_tasks",
			ondelete="SET NULL"
		),
	)
	op.create_index("ix_notes_user_id", "notes", ["user_id"])
	op.create_index("ix_notes_task_id", "notes", ["task_id"])
	op.create_index("ix_notes_created_at", "notes", ["created_at"])


def downgrade() -> None:
	op.drop_index("ix_notes_created_at", table_name="notes")
	op.drop_index("ix_notes_task_id", table_name="notes")
	op.drop_index("ix_notes_user_id", table_name="notes")
	op.drop_table("notes")
