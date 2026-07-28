"""add composite sync indexes for focus_sessions and rhythm_templates

Revision ID: ii22jj33kk44
Revises: hh11ii22jj33
Create Date: 2026-02-16 18:00:00.000000
"""

from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "ii22jj33kk44"
down_revision = "hh11ii22jj33"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        "ix_focus_sessions_sync",
        "focus_sessions",
        ["user_id", "updated_at", "id"],
    )
    op.create_index(
        "ix_rhythm_templates_sync",
        "rhythm_templates",
        ["user_id", "updated_at", "id"],
    )


def downgrade() -> None:
    op.drop_index("ix_rhythm_templates_sync", table_name="rhythm_templates")
    op.drop_index("ix_focus_sessions_sync", table_name="focus_sessions")
