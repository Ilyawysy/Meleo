"""seed theme shop items

Revision ID: gg33_themes
Revises: gg22_gamif
Create Date: 2026-02-07 18:00:00.000000
"""
from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "gg33_themes"
down_revision = "gg22_gamif"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        INSERT INTO shop_items (id, name, category, price, created_at, updated_at) VALUES
        (gen_random_uuid(), 'Тёмная тема', 'theme', 500, now(), now()),
        (gen_random_uuid(), 'Океан', 'theme', 800, now(), now())
        """
    )


def downgrade() -> None:
    op.execute("DELETE FROM shop_items WHERE category = 'theme'")
