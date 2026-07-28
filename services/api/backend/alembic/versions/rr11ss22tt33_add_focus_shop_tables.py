"""add focus shop and sessions tables

Revision ID: rr11ss22tt33
Revises: xxxx_add_pg_trgm_search
Create Date: 2026-01-17 22:15:00.000000
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision = "rr11ss22tt33"
down_revision = "xxxx_add_pg_trgm_search"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.execute(
		"""
	DO $$
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'shop_item_category') THEN
			CREATE TYPE shop_item_category AS ENUM ('hat', 'top', 'bottom', 'shoes', 'accessory');
		END IF;
		IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'focus_session_status') THEN
			CREATE TYPE focus_session_status AS ENUM ('created', 'running', 'paused', 'completed');
		END IF;
	END$$;
	"""
	)

	op.create_table(
		"shop_items",
		sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column(
			"category",
			postgresql.ENUM(
				"hat",
				"top",
				"bottom",
				"shoes",
				"accessory",
				name="shop_item_category",
				create_type=False,
			),
			nullable=False,
		),
		sa.Column("price", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
		sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now(), onupdate=sa.func.now()),
	)

	op.create_table(
		"user_shop_items",
		sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
		sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("item_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("purchased_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
		sa.ForeignKeyConstraint(["item_id"], ["shop_items.id"], name="fk_user_shop_items_item_id_shop_items"),
	)
	op.create_index("ix_user_shop_items_user_id", "user_shop_items", ["user_id"])
	op.create_index("ix_user_shop_items_item_id", "user_shop_items", ["item_id"])
	op.create_unique_constraint(
		"uq_user_shop_items_user_id_item_id", "user_shop_items", ["user_id", "item_id"]
	)

	op.create_table(
		"user_balance",
		sa.Column("user_id", postgresql.UUID(as_uuid=True), primary_key=True),
		sa.Column("coins", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
		sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now(), onupdate=sa.func.now()),
	)

	op.create_table(
		"focus_sessions",
		sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
		sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("planned_duration_sec", sa.Integer(), nullable=False),
		sa.Column(
			"status",
			postgresql.ENUM(
				"created",
				"running",
				"paused",
				"completed",
				name="focus_session_status",
				create_type=False,
			),
			nullable=False,
			server_default="created",
		),
		sa.Column("active_elapsed_sec", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("last_state_change_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("task_id", postgresql.UUID(as_uuid=True), nullable=True),
		sa.Column("earned_coins", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
		sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now(), onupdate=sa.func.now()),
		sa.ForeignKeyConstraint(["task_id"], ["tasks.id"], name="fk_focus_sessions_task_id_tasks"),
	)
	op.create_index("ix_focus_sessions_user_id", "focus_sessions", ["user_id"])

	now = datetime.now(timezone.utc)
	shop_items_table = sa.table(
		"shop_items",
		sa.column("id", postgresql.UUID(as_uuid=True)),
		sa.column("name", sa.String),
		sa.column(
			"category",
			postgresql.ENUM(
				"hat",
				"top",
				"bottom",
				"shoes",
				"accessory",
				name="shop_item_category",
				create_type=False,
			),
		),
		sa.column("price", sa.Integer),
		sa.column("created_at", sa.DateTime(timezone=True)),
		sa.column("updated_at", sa.DateTime(timezone=True)),
	)
	op.bulk_insert(
		shop_items_table,
		[
			{"id": uuid.uuid4(), "name": "Шапка бини", "category": "hat", "price": 50, "created_at": now, "updated_at": now},
			{"id": uuid.uuid4(), "name": "Кепка", "category": "hat", "price": 70, "created_at": now, "updated_at": now},
			{"id": uuid.uuid4(), "name": "Худи", "category": "top", "price": 120, "created_at": now, "updated_at": now},
			{"id": uuid.uuid4(), "name": "Футболка", "category": "top", "price": 60, "created_at": now, "updated_at": now},
			{"id": uuid.uuid4(), "name": "Джинсы", "category": "bottom", "price": 110, "created_at": now, "updated_at": now},
			{"id": uuid.uuid4(), "name": "Шорты", "category": "bottom", "price": 80, "created_at": now, "updated_at": now},
			{"id": uuid.uuid4(), "name": "Кроссовки", "category": "shoes", "price": 150, "created_at": now, "updated_at": now},
			{"id": uuid.uuid4(), "name": "Ботинки", "category": "shoes", "price": 180, "created_at": now, "updated_at": now},
			{"id": uuid.uuid4(), "name": "Очки", "category": "accessory", "price": 90, "created_at": now, "updated_at": now},
			{"id": uuid.uuid4(), "name": "Рюкзак", "category": "accessory", "price": 140, "created_at": now, "updated_at": now},
		],
	)


def downgrade() -> None:
	op.drop_index("ix_focus_sessions_user_id", table_name="focus_sessions")
	op.drop_table("focus_sessions")

	op.drop_index("ix_user_shop_items_item_id", table_name="user_shop_items")
	op.drop_index("ix_user_shop_items_user_id", table_name="user_shop_items")
	op.drop_constraint("uq_user_shop_items_user_id_item_id", "user_shop_items", type_="unique")
	op.drop_table("user_shop_items")

	op.drop_table("user_balance")
	op.drop_table("shop_items")

	op.execute("DROP TYPE IF EXISTS focus_session_status")
	op.execute("DROP TYPE IF EXISTS shop_item_category")
