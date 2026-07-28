"""add developer announcements

Revision ID: aa11bb22cc33
Revises: 238c239f5e10
Create Date: 2026-02-09 12:00:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'aa11bb22cc33'
down_revision = '238c239f5e10'
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Create developer_announcements table
	op.create_table(
		'developer_announcements',
		sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column('title', sa.String(length=255), nullable=False),
		sa.Column('message', sa.Text(), nullable=False),
		sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
		sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True),
		sa.Column('target_user_ids', postgresql.ARRAY(postgresql.UUID(as_uuid=True)), nullable=True),
		sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text("timezone('utc', now())")),
		sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text("timezone('utc', now())")),
		sa.PrimaryKeyConstraint('id')
	)

	# Create indexes for performance
	op.create_index('ix_developer_announcements_created_at', 'developer_announcements', ['created_at'])
	op.create_index('ix_developer_announcements_is_active', 'developer_announcements', ['is_active'])
	# GIN index for array containment queries
	op.create_index(
		'ix_developer_announcements_target_user_ids',
		'developer_announcements',
		['target_user_ids'],
		postgresql_using='gin',
	)

	# Create user_announcement_reads table
	op.create_table(
		'user_announcement_reads',
		sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column('announcement_id', postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column('read_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text("timezone('utc', now())")),
		sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text("timezone('utc', now())")),
		sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text("timezone('utc', now())")),
		sa.ForeignKeyConstraint(['announcement_id'], ['developer_announcements.id'], ondelete='CASCADE'),
		sa.PrimaryKeyConstraint('id'),
		sa.UniqueConstraint('user_id', 'announcement_id', name='uq_user_announcement')
	)

	# Create indexes for lookups
	op.create_index('ix_user_announcement_reads_user_id', 'user_announcement_reads', ['user_id'])
	op.create_index('ix_user_announcement_reads_announcement_id', 'user_announcement_reads', ['announcement_id'])


def downgrade() -> None:
	# Drop user_announcement_reads table
	op.drop_index('ix_user_announcement_reads_announcement_id', table_name='user_announcement_reads')
	op.drop_index('ix_user_announcement_reads_user_id', table_name='user_announcement_reads')
	op.drop_table('user_announcement_reads')

	# Drop developer_announcements table
	op.drop_index('ix_developer_announcements_target_user_ids', table_name='developer_announcements')
	op.drop_index('ix_developer_announcements_is_active', table_name='developer_announcements')
	op.drop_index('ix_developer_announcements_created_at', table_name='developer_announcements')
	op.drop_table('developer_announcements')
