"""Add per-room focus_duration_min and break_min defaults

Revision ID: ffff_focus_rooms_durations
Revises: eeee_mascot_skins_sync_triggers
Create Date: 2026-04-29 02:00:00.000000
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "ffff_focus_rooms_durations"
down_revision = "eeee_mascot_skins_sync_triggers"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "focus_rooms",
        sa.Column("focus_duration_min", sa.Integer(), nullable=True),
    )
    op.add_column(
        "focus_rooms",
        sa.Column("break_min", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("focus_rooms", "break_min")
    op.drop_column("focus_rooms", "focus_duration_min")
