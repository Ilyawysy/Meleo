"""fix: create chat tables (second attempt)

Revision ID: aa55bb66cc77
Revises: 045651e658f3
Create Date: 2025-10-30 12:07:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'aa55bb66cc77'
down_revision = '045651e658f3'
branch_labels = None
depends_on = None

def upgrade() -> None:
	from sqlalchemy.dialects import postgresql
	# Create chat_threads if not exists
	conn = op.get_bind()
	res = conn.execute(sa.text("""
		SELECT to_regclass('public.chat_threads')
	"""))
	exists = res.scalar() is not None
	if not exists:
		op.create_table(
			"chat_threads",
			sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
			sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
			sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
			sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
			sa.Column("title", sa.String(length=255), nullable=False),
			sa.Column("metadata_", sa.Text(), nullable=True),
		)
		op.create_index("ix_chat_threads_user_id", "chat_threads", ["user_id"], unique=False)

	# Create chat_messages if not exists
	res2 = conn.execute(sa.text("""
		SELECT to_regclass('public.chat_messages')
	"""))
	exists2 = res2.scalar() is not None
	if not exists2:
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
			sa.ForeignKeyConstraint(["thread_id"], ["chat_threads.id"], ondelete="CASCADE"),
		)
		op.create_index("ix_chat_messages_thread_id", "chat_messages", ["thread_id"], unique=False)


def downgrade() -> None:
	# Safe drops
	try:
		op.drop_index("ix_chat_messages_thread_id", table_name="chat_messages")
	except Exception:
		pass
	try:
		op.drop_table("chat_messages")
	except Exception:
		pass
	try:
		op.drop_index("ix_chat_threads_user_id", table_name="chat_threads")
	except Exception:
		pass
	try:
		op.drop_table("chat_threads")
	except Exception:
		pass
