"""recreate missing revision

Revision ID: b4d7d01582e7
Revises: 97180784b93e
Create Date: 2025-11-06 15:28:22.358658
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'b4d7d01582e7'
down_revision = '97180784b93e'
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
