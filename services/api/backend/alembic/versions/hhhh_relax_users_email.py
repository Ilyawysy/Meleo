"""relax users.email — make nullable, drop unique index; require supabase_user_id

Revision ID: hhhh_relax_users_email
Revises: gggg_add_active_focus_room_id
Create Date: 2026-05-15 22:00:00.000000

Privacy-инициатива: переходим к идентификации только через supabase_user_id.
Колонка email становится nullable (для совместимости и отката), unique-индекс
снимается. supabase_user_id становится NOT NULL (бэкфилл не требуется —
проверено, 0 строк с NULL).
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "hhhh_relax_users_email"
down_revision = "gggg_add_active_focus_room_id"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_index("ix_users_email", table_name="users")
    op.alter_column(
        "users", "email",
        existing_type=sa.String(length=255),
        nullable=True,
    )
    op.alter_column(
        "users", "supabase_user_id",
        existing_type=postgresql.UUID(as_uuid=True),
        nullable=False,
    )


def downgrade() -> None:
    op.alter_column(
        "users", "supabase_user_id",
        existing_type=postgresql.UUID(as_uuid=True),
        nullable=True,
    )
    op.execute(
        "UPDATE users SET email = id::text || '@placeholder.invalid' WHERE email IS NULL;"
    )
    op.alter_column(
        "users", "email",
        existing_type=sa.String(length=255),
        nullable=False,
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)
