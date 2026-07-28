"""add idempotency_keys table

Stores idempotency keys for safe retries of batched commands
and purchase endpoints. Keys expire after 24 hours.

Revision ID: ll55mm66nn77
Revises: kk44ll55mm66
Create Date: 2026-02-17 14:00:00.000000
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "ll55mm66nn77"
down_revision = "kk44ll55mm66"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "idempotency_keys",
        sa.Column("key", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id"),
            nullable=False,
        ),
        sa.Column("endpoint", sa.Text(), nullable=False),
        sa.Column("response_status", sa.Integer(), nullable=False),
        sa.Column("response_body", postgresql.JSONB(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "expires_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now() + interval '24 hours'"),
        ),
    )
    op.create_index(
        "ix_idempotency_user",
        "idempotency_keys",
        ["user_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_idempotency_user", table_name="idempotency_keys")
    op.drop_table("idempotency_keys")
