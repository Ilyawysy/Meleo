"""Drop rhythm tables.

Revision ID: pp22
Revises: pp11
Create Date: 2026-03-05
"""

from __future__ import annotations

from alembic import op


revision = "pp22"
down_revision = "pp11"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_table("rhythm_assignment_dates")
    op.drop_table("rhythm_assignments")
    op.drop_table("rhythm_segments")
    op.drop_table("rhythm_templates")


def downgrade() -> None:
    # Full recreation of rhythm tables is complex; see qq11rr22ss33_create_rhythm_tables.py
    raise NotImplementedError("Downgrade not supported — re-apply original rhythm migration.")
