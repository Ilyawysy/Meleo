"""fix users timestamps defaults

Revision ID: abcdef123456
Revises: aabbccdd1122
Create Date: 2025-10-25 21:00:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "abcdef123456"
down_revision = "aabbccdd1122"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Backfill NULLs first to satisfy NOT NULL
	op.execute("UPDATE users SET created_at = timezone('utc', now()) WHERE created_at IS NULL")
	op.execute("UPDATE users SET updated_at = timezone('utc', now()) WHERE updated_at IS NULL")

	# Set server defaults for future inserts/updates
	op.alter_column(
		"users",
		"created_at",
		existing_type=sa.DateTime(),
		server_default=sa.text("timezone('utc', now())"),
		existing_nullable=False,
	)
	op.alter_column(
		"users",
		"updated_at",
		existing_type=sa.DateTime(),
		server_default=sa.text("timezone('utc', now())"),
		existing_nullable=False,
	)


def downgrade() -> None:
	# Remove server defaults (leave data intact)
	op.alter_column(
		"users",
		"created_at",
		existing_type=sa.DateTime(),
		server_default=None,
		existing_nullable=False,
	)
	op.alter_column(
		"users",
		"updated_at",
		existing_type=sa.DateTime(),
		server_default=None,
		existing_nullable=False,
	)
