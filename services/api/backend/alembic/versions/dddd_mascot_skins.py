"""Add mascot skins tables and active_mascot_skin_id on users

Revision ID: dddd_mascot_skins
Revises: cccc_adaptive_plan_and_longest_streak
Create Date: 2026-04-29 00:00:00.000000
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision = "dddd_mascot_skins"
down_revision = "cccc_adaptive_plan_and_longest_streak"
branch_labels = None
depends_on = None


MASCOT_SKIN_TIER = "mascot_skin_tier"


SEED_ROWS = [
    # (slug, tier, price_coins, c1, c2, c3, c4, sort_order)
    ("cheap_1", "cheap", 100, "#ECCF8B", "#DFB669", "#FFFFFF", "#C7A15A", 1),
    ("cheap_2", "cheap", 100, "#99582A", "#432818", "#FFE6A7", "#682B07", 2),
    ("cheap_3", "cheap", 100, "#FF8E72", "#ED6A5E", "#FFEFE6", "#D04B3F", 3),
    ("medium_1", "medium", 300, "#C97D60", "#965A46", "#F2E5D7", "#76402E", 4),
    ("medium_2", "medium", 300, "#FFE94E", "#FDB833", "#FFFFFF", "#FFA800", 5),
    ("medium_3", "medium", 300, "#74776B", "#5C574F", "#FFFFFF", "#48483A", 6),
    ("expensive_1", "expensive", 800, "#E3E4DB", "#CDCDCD", "#FFFFFF", "#A1A1A1", 7),
    ("expensive_2", "expensive", 800, "#8A5A44", "#5F3A2B", "#FFFFFF", "#42281D", 8),
    ("expensive_3", "expensive", 800, "#A882C8", "#864CB9", "#FFFFFF", "#240046", 9),
    ("pro_1", "pro", 2000, "#E02427", "#A50104", "#FFFFC7", "#590002", 10),
    ("pro_2", "pro", 2000, "#FFC8DD", "#FFAFCC", "#FFFFFF", "#FF7DAC", 11),
    ("pro_3", "pro", 2000, "#85CBD8", "#00AED0", "#FFFFFF", "#00788F", 12),
]


def upgrade() -> None:
    tier_enum = postgresql.ENUM(
        "cheap",
        "medium",
        "expensive",
        "pro",
        name=MASCOT_SKIN_TIER,
        create_type=False,
    )
    tier_enum.create(op.get_bind(), checkfirst=True)

    op.create_table(
        "mascot_skins",
        sa.Column(
            "id",
            sa.Integer(),
            primary_key=True,
            autoincrement=True,
        ),
        sa.Column("slug", sa.String(64), nullable=False, unique=True),
        sa.Column("tier", tier_enum, nullable=False),
        sa.Column("price_coins", sa.Integer(), nullable=False),
        sa.Column("color1", sa.String(7), nullable=False),
        sa.Column("color2", sa.String(7), nullable=False),
        sa.Column("color3", sa.String(7), nullable=False),
        sa.Column("color4", sa.String(7), nullable=False),
        sa.Column(
            "sort_order",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )

    op.create_table(
        "user_mascot_skins",
        sa.Column(
            "user_id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "skin_id",
            sa.Integer(),
            sa.ForeignKey("mascot_skins.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "purchased_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index(
        "ix_user_mascot_skins_user_id",
        "user_mascot_skins",
        ["user_id"],
    )

    op.add_column(
        "users",
        sa.Column(
            "active_mascot_skin_id",
            sa.Integer(),
            sa.ForeignKey("mascot_skins.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )

    # Seed catalog
    bind = op.get_bind()
    for row in SEED_ROWS:
        bind.execute(
            sa.text(
                "INSERT INTO mascot_skins "
                "(slug, tier, price_coins, color1, color2, color3, color4, sort_order) "
                "VALUES (:slug, :tier, :price, :c1, :c2, :c3, :c4, :sort)"
            ),
            {
                "slug": row[0],
                "tier": row[1],
                "price": row[2],
                "c1": row[3],
                "c2": row[4],
                "c3": row[5],
                "c4": row[6],
                "sort": row[7],
            },
        )


def downgrade() -> None:
    op.drop_column("users", "active_mascot_skin_id")
    op.drop_index("ix_user_mascot_skins_user_id", table_name="user_mascot_skins")
    op.drop_table("user_mascot_skins")
    op.drop_table("mascot_skins")
    postgresql.ENUM(name=MASCOT_SKIN_TIER).drop(op.get_bind(), checkfirst=True)
