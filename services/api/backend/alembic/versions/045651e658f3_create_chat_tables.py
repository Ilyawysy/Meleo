"""create chat tables

Revision ID: 045651e658f3
Revises: ee11ee22ee33
Create Date: 2025-10-30 09:35:20.388615
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '045651e658f3'
down_revision = 'ee11ee22ee33'
branch_labels = None
depends_on = None


def upgrade() -> None:
	from sqlalchemy.dialects import postgresql
	op.create_table(
		"chat_threads",
		sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
		sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("title", sa.String(length=255), nullable=False),
		sa.Column("metadata_", sa.Text(), nullable=True),
	)
	# Index on user_id for faster lookups
	op.create_index("ix_chat_threads_user_id", "chat_threads", ["user_id"], unique=False)

	op.create_table(
		"chat_messages",
		sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
		sa.Column("thread_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("role", sa.String(length=20), nullable=False),
		sa.Column("content", sa.Text(), nullable=False),
		sa.Column("metadata_", sa.Text(), nullable=True),
		sa.Column("order", sa.Integer(), server_default="0", nullable=False),
		# FK with cascade delete
		sa.ForeignKeyConstraint(["thread_id"], ["chat_threads.id"], ondelete="CASCADE"),
	)
	# Index on thread_id for message retrieval
	op.create_index("ix_chat_messages_thread_id", "chat_messages", ["thread_id"], unique=False)


def downgrade() -> None:
	# Drop message table and its index first
	op.drop_index("ix_chat_messages_thread_id", table_name="chat_messages")
	op.drop_table("chat_messages")
	# Then drop threads index and table
	op.drop_index("ix_chat_threads_user_id", table_name="chat_threads")
	op.drop_table("chat_threads")
