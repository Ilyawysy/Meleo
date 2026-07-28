"""drop notes table

Revision ID: fe12ab34cd56
Revises: dd11ee22ff33
Create Date: 2026-01-24 00:00:00.000000
"""
from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "fe12ab34cd56"
down_revision = "dd11ee22ff33"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.execute("DROP TABLE IF EXISTS notes CASCADE")


def downgrade() -> None:
	# Irreversible by default; notes schema was removed.
	pass
