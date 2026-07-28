"""merge heads hh22ii33jj44 & ii44jj55kk66

Revision ID: be5fc02ddd44
Revises: hh22ii33jj44, ii44jj55kk66
Create Date: 2025-11-20 22:42:32.382823
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'be5fc02ddd44'
down_revision = ('hh22ii33jj44', 'ii44jj55kk66')
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
