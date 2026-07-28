"""Add active_focus_room_id to user_gamification_profile

Revision ID: gggg_add_active_focus_room_id
Revises: ffff_focus_rooms_durations
Create Date: 2026-05-02 00:00:00.000000
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "gggg_add_active_focus_room_id"
down_revision = "ffff_focus_rooms_durations"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "user_gamification_profile",
        sa.Column(
            "active_focus_room_id",
            postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
    )
    op.create_foreign_key(
        "fk_ugp_active_focus_room_id",
        "user_gamification_profile",
        "focus_rooms",
        ["active_focus_room_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_ugp_active_focus_room_id",
        "user_gamification_profile",
        type_="foreignkey",
    )
    op.drop_column("user_gamification_profile", "active_focus_room_id")
