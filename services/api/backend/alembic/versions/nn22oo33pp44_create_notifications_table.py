"""create notifications table

Revision ID: nn22oo33pp44
Revises: mm11nn22oo33
Create Date: 2025-01-27 16:00:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'nn22oo33pp44'
down_revision = 'mm11nn22oo33'
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Use existing task_recurrence enum type (created_type=False)
	recurrence_enum = postgresql.ENUM('none', 'daily', 'weekly', name='task_recurrence', create_type=False)
	
	# Create notifications table
	op.create_table(
		'notifications',
		sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column('title', sa.String(length=255), nullable=False),
		sa.Column('time', sa.DateTime(timezone=True), nullable=False),
		sa.Column('recurrence', recurrence_enum, nullable=False, server_default='none'),
		sa.Column('deleted', sa.Boolean(), nullable=False, server_default='false'),
		sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text("timezone('utc', now())")),
		sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text("timezone('utc', now())")),
		sa.PrimaryKeyConstraint('id')
	)
	
	# Create indexes
	op.create_index('ix_notifications_user_id', 'notifications', ['user_id'])
	op.create_index('ix_notifications_time', 'notifications', ['time'])
	op.create_index('ix_notifications_created_at', 'notifications', ['created_at'])


def downgrade() -> None:
	# Drop indexes
	op.drop_index('ix_notifications_created_at', table_name='notifications')
	op.drop_index('ix_notifications_time', table_name='notifications')
	op.drop_index('ix_notifications_user_id', table_name='notifications')
	
	# Drop table
	op.drop_table('notifications')
