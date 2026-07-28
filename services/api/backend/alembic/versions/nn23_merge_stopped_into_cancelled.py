"""merge stopped into cancelled

Revision ID: nn23_stopped_cancel
Revises: nn22_simplify
Create Date: 2026-03-02 12:00:00.000000
"""

from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "nn23_stopped_cancel"
down_revision = "nn22_simplify"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        UPDATE focus_sessions SET status = 'cancelled'
        WHERE status = 'stopped'
    """)


def downgrade() -> None:
    # Cannot distinguish which cancelled sessions were originally stopped.
    # No-op: stopped enum value still exists in Postgres.
    pass
