"""add stat_widget_config to gamification profile

Revision ID: d00e7c147d66
Revises: ww11
Create Date: 2026-03-12 18:28:08.138414
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'd00e7c147d66'
down_revision = 'ww11'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'user_gamification_profile',
        sa.Column('stat_widget_config', sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('user_gamification_profile', 'stat_widget_config')
