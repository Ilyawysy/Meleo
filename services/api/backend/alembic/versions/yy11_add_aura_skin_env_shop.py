"""add aura skin environment shop categories and user_active_items

Revision ID: yy11_add_aura_skin_env_shop
Revises: d00e7c147d66
Create Date: 2026-03-14 00:00:00.000000
"""

from __future__ import annotations

import uuid

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "yy11_add_aura_skin_env_shop"
down_revision = "d00e7c147d66"
branch_labels = None
depends_on = None

# Fixed UUIDs for seeded items (generated once)
_AURA_BLUE_ID = uuid.UUID("a1000000-0000-0000-0000-000000000001")
_AURA_GRAY_ID = uuid.UUID("a1000000-0000-0000-0000-000000000002")
_AURA_TEAL_ID = uuid.UUID("a1000000-0000-0000-0000-000000000003")
_AURA_RED_ID = uuid.UUID("a1000000-0000-0000-0000-000000000004")
_AURA_PURPLE_ID = uuid.UUID("a1000000-0000-0000-0000-000000000005")
_AURA_GREEN_ID = uuid.UUID("a1000000-0000-0000-0000-000000000006")
_AURA_NAVY_ID = uuid.UUID("a1000000-0000-0000-0000-000000000007")

_SKIN_ORANGE_ID = uuid.UUID("b2000000-0000-0000-0000-000000000001")
_SKIN_SAND_ID = uuid.UUID("b2000000-0000-0000-0000-000000000002")
_SKIN_SILVER_ID = uuid.UUID("b2000000-0000-0000-0000-000000000003")
_SKIN_WHITE_ID = uuid.UUID("b2000000-0000-0000-0000-000000000004")
_SKIN_DARK_ID = uuid.UUID("b2000000-0000-0000-0000-000000000005")

_ENV_RAINFOREST_ID = uuid.UUID("c3000000-0000-0000-0000-000000000001")
_ENV_FIREPLACE_ID = uuid.UUID("c3000000-0000-0000-0000-000000000002")

_SEEDED_IDS = [
    _AURA_BLUE_ID,
    _AURA_GRAY_ID,
    _AURA_TEAL_ID,
    _AURA_RED_ID,
    _AURA_PURPLE_ID,
    _AURA_GREEN_ID,
    _AURA_NAVY_ID,
    _SKIN_ORANGE_ID,
    _SKIN_SAND_ID,
    _SKIN_SILVER_ID,
    _SKIN_WHITE_ID,
    _SKIN_DARK_ID,
    _ENV_RAINFOREST_ID,
    _ENV_FIREPLACE_ID,
]


def upgrade() -> None:
    # 1. Add new enum values to shop_item_category
    # Must run outside transaction — Postgres requires COMMIT before new enum values can be used
    bind = op.get_bind()
    bind.execute(sa.text("COMMIT"))
    bind.execute(sa.text("ALTER TYPE shop_item_category ADD VALUE IF NOT EXISTS 'aura'"))
    bind.execute(sa.text("ALTER TYPE shop_item_category ADD VALUE IF NOT EXISTS 'skin'"))
    bind.execute(sa.text("ALTER TYPE shop_item_category ADD VALUE IF NOT EXISTS 'environment'"))
    bind.execute(sa.text("BEGIN"))

    # 2. Add required_level column to shop_items
    op.add_column(
        "shop_items",
        sa.Column("required_level", sa.Integer(), nullable=False, server_default="0"),
    )

    # 3. Create user_active_items table
    op.create_table(
        "user_active_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("category", sa.String(length=50), nullable=False),
        sa.Column("item_id", postgresql.UUID(as_uuid=True), nullable=False),
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
            onupdate=sa.func.now(),
        ),
        sa.ForeignKeyConstraint(
            ["item_id"],
            ["shop_items.id"],
            name="fk_user_active_items_item_id_shop_items",
        ),
        sa.UniqueConstraint("user_id", "category", name="uq_user_active_items_user_category"),
    )
    op.create_index("ix_user_active_items_user_id", "user_active_items", ["user_id"])

    # 4. Seed new items
    op.execute(
        sa.text(
            """
            INSERT INTO shop_items (id, name, category, price, required_level, created_at, updated_at)
            VALUES
              (:aura_blue,    'Blue',       'aura',        0, 0,  now(), now()),
              (:aura_gray,    'Gray',       'aura',     1000, 2,  now(), now()),
              (:aura_teal,    'Teal',       'aura',     1000, 5,  now(), now()),
              (:aura_red,     'Red',        'aura',     2000, 7,  now(), now()),
              (:aura_purple,  'Purple',     'aura',     3000, 9,  now(), now()),
              (:aura_green,   'Green',      'aura',     3000, 11, now(), now()),
              (:aura_navy,    'Navy',       'aura',     4000, 14, now(), now()),
              (:skin_orange,  'Orange',     'skin',        0, 0,  now(), now()),
              (:skin_sand,    'Sand',       'skin',     2000, 6,  now(), now()),
              (:skin_silver,  'Silver',     'skin',     2000, 8,  now(), now()),
              (:skin_white,   'White',      'skin',     3000, 12, now(), now()),
              (:skin_dark,    'Dark',       'skin',     4000, 15, now(), now()),
              (:env_rain,     'Rainforest', 'environment', 3000, 10, now(), now()),
              (:env_fire,     'Fireplace',  'environment', 4000, 13, now(), now())
            """
        ).bindparams(
            aura_blue=_AURA_BLUE_ID,
            aura_gray=_AURA_GRAY_ID,
            aura_teal=_AURA_TEAL_ID,
            aura_red=_AURA_RED_ID,
            aura_purple=_AURA_PURPLE_ID,
            aura_green=_AURA_GREEN_ID,
            aura_navy=_AURA_NAVY_ID,
            skin_orange=_SKIN_ORANGE_ID,
            skin_sand=_SKIN_SAND_ID,
            skin_silver=_SKIN_SILVER_ID,
            skin_white=_SKIN_WHITE_ID,
            skin_dark=_SKIN_DARK_ID,
            env_rain=_ENV_RAINFOREST_ID,
            env_fire=_ENV_FIREPLACE_ID,
        )
    )


def downgrade() -> None:
    # Delete seeded items (remove user_active_items references first)
    id_list = ", ".join(f"'{str(i)}'" for i in _SEEDED_IDS)
    op.execute(sa.text(f"DELETE FROM user_active_items WHERE item_id IN ({id_list})"))
    op.execute(sa.text(f"DELETE FROM shop_items WHERE id IN ({id_list})"))

    # Drop user_active_items table
    op.drop_index("ix_user_active_items_user_id", table_name="user_active_items")
    op.drop_table("user_active_items")

    # Drop required_level column
    op.drop_column("shop_items", "required_level")

    # NOTE: Postgres does not support removing enum values.
    # 'aura', 'skin', 'environment' remain in the shop_item_category type.
