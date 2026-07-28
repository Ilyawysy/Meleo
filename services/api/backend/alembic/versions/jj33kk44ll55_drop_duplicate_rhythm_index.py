"""drop duplicate rhythm_templates index (user_id, updated_at, id)

The index ix_rhythm_templates_user_updated_id was created in qq11rr22ss33
and ix_rhythm_templates_sync (same columns) was created in ii22jj33kk44.
Keep ix_rhythm_templates_sync (used by sync queries), drop the duplicate.

Revision ID: jj33kk44ll55
Revises: ii22jj33kk44
Create Date: 2026-02-17 12:00:00.000000
"""

from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "jj33kk44ll55"
down_revision = "ii22jj33kk44"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "DROP INDEX IF EXISTS ix_rhythm_templates_user_updated_id"
    )


def downgrade() -> None:
    op.create_index(
        "ix_rhythm_templates_user_updated_id",
        "rhythm_templates",
        ["user_id", "updated_at", "id"],
    )
