"""add project_id and group_id fields to tasks and notes

Revision ID: mm11nn22oo33
Revises: jj55kk66ll77
Create Date: 2025-01-27 15:00:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'mm11nn22oo33'
down_revision = 'jj55kk66ll77'
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Add project_id and group_id to tasks table
	op.add_column('tasks', sa.Column('project_id', sa.String(length=255), nullable=True))
	op.add_column('tasks', sa.Column('group_id', sa.String(length=255), nullable=True))
	
	# Add group_id to notes table
	op.add_column('notes', sa.Column('group_id', sa.String(length=255), nullable=True))
	
	# Create indexes for filtering
	op.create_index('ix_tasks_project_id', 'tasks', ['project_id'])
	op.create_index('ix_tasks_group_id', 'tasks', ['group_id'])
	op.create_index('ix_notes_group_id', 'notes', ['group_id'])


def downgrade() -> None:
	# Drop indexes
	op.drop_index('ix_notes_group_id', table_name='notes')
	op.drop_index('ix_tasks_group_id', table_name='tasks')
	op.drop_index('ix_tasks_project_id', table_name='tasks')
	
	# Drop columns
	op.drop_column('notes', 'group_id')
	op.drop_column('tasks', 'group_id')
	op.drop_column('tasks', 'project_id')
