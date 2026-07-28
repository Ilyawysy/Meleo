"""add sync indexes for delta queries

Revision ID: dd44ee55ff66
Revises: cc33dd44ee55
Create Date: 2026-02-13 12:10:00.000000
"""

from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "dd44ee55ff66"
down_revision = "cc33dd44ee55"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Tasks: composite index for sync delta query
    # Covers: WHERE user_id = ? AND (updated_at, id) > (?, ?) ORDER BY updated_at, id
    op.create_index(
        "idx_tasks_user_updated",
        "tasks",
        ["user_id", "updated_at", "id"],
        postgresql_using="btree",
    )

    # Notifications: same pattern
    op.create_index(
        "idx_notifications_user_updated",
        "notifications",
        ["user_id", "updated_at", "id"],
        postgresql_using="btree",
    )

    # Chat messages: through thread_id for sync queries
    op.create_index(
        "idx_chat_messages_thread_updated",
        "chat_messages",
        ["thread_id", "updated_at", "id"],
        postgresql_using="btree",
    )

    # Announcements: partial index for active + not expired
    op.execute(
        """
        CREATE INDEX idx_announcements_active_expires
        ON developer_announcements (is_active, expires_at)
        WHERE is_active = true;
        """
    )

    # Announcement reads: composite for NOT EXISTS anti-join
    # (unique constraint uq_user_announcement already exists on (user_id, announcement_id),
    #  but adding explicit btree index for anti-join performance)
    op.create_index(
        "idx_announcement_reads_user_ann",
        "user_announcement_reads",
        ["user_id", "announcement_id"],
        postgresql_using="btree",
    )


def downgrade() -> None:
    op.drop_index("idx_announcement_reads_user_ann", table_name="user_announcement_reads")
    op.execute("DROP INDEX IF EXISTS idx_announcements_active_expires;")
    op.drop_index("idx_chat_messages_thread_updated", table_name="chat_messages")
    op.drop_index("idx_notifications_user_updated", table_name="notifications")
    op.drop_index("idx_tasks_user_updated", table_name="tasks")
