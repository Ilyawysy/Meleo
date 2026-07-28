"""merge heads 57ecc997d4f8 and nn22oo33pp44

Revision ID: 8381d10c5af6
Revises: 57ecc997d4f8, nn22oo33pp44
Create Date: 2026-01-08 17:29:12.506998
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '8381d10c5af6'
down_revision = ('57ecc997d4f8', 'nn22oo33pp44')
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
