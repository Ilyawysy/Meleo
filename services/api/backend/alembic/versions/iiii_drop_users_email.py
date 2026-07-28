"""drop users.email column

Revision ID: iiii_drop_users_email
Revises: hhhh_relax_users_email
Create Date: 2026-05-15 22:30:00.000000

Privacy-инициатива (финальный шаг): email окончательно удаляется из
прикладной БД. Идентификация — только через supabase_user_id; email
остаётся только в auth.users (Supabase Auth).

ВНИМАНИЕ: downgrade восстанавливает только структуру колонки. Значения
можно восстановить из auth.users через join по supabase_user_id.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "iiii_drop_users_email"
down_revision = "hhhh_relax_users_email"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_column("users", "email")


def downgrade() -> None:
    op.add_column(
        "users",
        sa.Column("email", sa.String(length=255), nullable=True),
    )
    op.execute(
        """
        UPDATE public.users u
        SET email = au.email
        FROM auth.users au
        WHERE au.id = u.supabase_user_id;
        """
    )
