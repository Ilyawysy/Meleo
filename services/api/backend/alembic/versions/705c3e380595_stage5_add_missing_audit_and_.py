"""stage5 add missing audit and announcement indexes

Revision ID: 705c3e380595
Revises: gg77hh88ii99
Create Date: 2026-02-15 11:06:53.544080
"""
from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "705c3e380595"
down_revision = "gg77hh88ii99"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Stage 5 sync path: unread tombstones use
    # WHERE user_id = ? AND read_at > ? ORDER BY read_at, announcement_id.
    op.create_index(
        "idx_announcement_reads_user_read_at_ann",
        "user_announcement_reads",
        ["user_id", "read_at", "announcement_id"],
        postgresql_using="btree",
    )

    # Stage 5 admin audit path: ORDER BY created_at DESC with offset pagination.
    # Keep explicit created_at index after audit_logs cutover.
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at_id
        ON audit_logs (created_at DESC, id DESC);
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_audit_logs_created_at_id;")
    op.drop_index(
        "idx_announcement_reads_user_read_at_ann",
        table_name="user_announcement_reads",
    )
