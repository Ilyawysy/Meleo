"""merge heads bc23de45fg67 and rr11ss22tt33

Revision ID: 987ae03f193d
Revises: bc23de45fg67, rr11ss22tt33
Create Date: 2026-01-22 11:20:18.901576
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '987ae03f193d'
down_revision = ('bc23de45fg67', 'rr11ss22tt33')
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
