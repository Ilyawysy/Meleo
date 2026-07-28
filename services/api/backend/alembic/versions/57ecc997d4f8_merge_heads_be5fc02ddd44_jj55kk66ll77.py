"""merge heads be5fc02ddd44 & jj55kk66ll77

Revision ID: 57ecc997d4f8
Revises: be5fc02ddd44, jj55kk66ll77
Create Date: 2025-11-20 23:16:21.911706
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '57ecc997d4f8'
down_revision = ('be5fc02ddd44', 'jj55kk66ll77')
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
