"""add user_state_version table and version increment triggers

Revision ID: bb11cc22dd33
Revises: aa11bb22cc33
Create Date: 2026-02-13 12:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "bb11cc22dd33"
down_revision = "aa11bb22cc33"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Create user_state_version table
    op.create_table(
        "user_state_version",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "tasks_version",
            sa.BigInteger(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "notifications_version",
            sa.BigInteger(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "messages_version",
            sa.BigInteger(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "announcements_version",
            sa.BigInteger(),
            nullable=False,
            server_default="0",
        ),
    )

    # 2. Create trigger function: increment version for a given column
    #    Uses COALESCE(NEW, OLD) pattern so DELETE works (NEW is NULL on DELETE)
    op.execute("""
        CREATE OR REPLACE FUNCTION increment_user_state_version()
        RETURNS TRIGGER AS $$
        DECLARE
            _user_id UUID;
            _col TEXT;
        BEGIN
            -- Get user_id: NEW for INSERT/UPDATE, OLD for DELETE
            _user_id := COALESCE(NEW.user_id, OLD.user_id);
            -- Column name passed via TG_ARGV[0]
            _col := TG_ARGV[0];

            -- Upsert: insert row if not exists, increment version column
            EXECUTE format(
                'INSERT INTO user_state_version (user_id, %I) VALUES ($1, 1)
                 ON CONFLICT (user_id)
                 DO UPDATE SET %I = user_state_version.%I + 1',
                _col, _col, _col
            ) USING _user_id;

            RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;
    """)

    # 3. Create triggers for each domain table

    # Tasks: INSERT, UPDATE, DELETE
    op.execute("""
        CREATE TRIGGER trg_tasks_version
        AFTER INSERT OR UPDATE OR DELETE ON tasks
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('tasks_version');
    """)

    # Notifications: INSERT, UPDATE, DELETE
    op.execute("""
        CREATE TRIGGER trg_notifications_version
        AFTER INSERT OR UPDATE OR DELETE ON notifications
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('notifications_version');
    """)

    # Chat messages: INSERT, UPDATE, DELETE
    # Note: chat_messages has thread_id, not user_id directly.
    # We need a separate trigger function that joins through chat_threads.
    op.execute("""
        CREATE OR REPLACE FUNCTION increment_messages_version()
        RETURNS TRIGGER AS $$
        DECLARE
            _user_id UUID;
        BEGIN
            -- Get thread_id from NEW or OLD
            IF TG_OP = 'DELETE' THEN
                SELECT user_id INTO _user_id FROM chat_threads WHERE id = OLD.thread_id;
            ELSE
                SELECT user_id INTO _user_id FROM chat_threads WHERE id = NEW.thread_id;
            END IF;

            IF _user_id IS NOT NULL THEN
                INSERT INTO user_state_version (user_id, messages_version) VALUES (_user_id, 1)
                ON CONFLICT (user_id)
                DO UPDATE SET messages_version = user_state_version.messages_version + 1;
            END IF;

            RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;
    """)

    op.execute("""
        CREATE TRIGGER trg_messages_version
        AFTER INSERT OR UPDATE OR DELETE ON chat_messages
        FOR EACH ROW
        EXECUTE FUNCTION increment_messages_version();
    """)

    # Developer announcements: use a global version key (not per-user)
    # Since announcements are broadcast, we increment all affected users' versions.
    # For simplicity, we track a global announcements version in a separate row.
    op.execute("""
        CREATE OR REPLACE FUNCTION increment_announcements_global_version()
        RETURNS TRIGGER AS $$
        BEGIN
            -- Increment announcements_version for ALL users who have a row
            UPDATE user_state_version
            SET announcements_version = announcements_version + 1;

            RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;
    """)

    op.execute("""
        CREATE TRIGGER trg_announcements_version
        AFTER INSERT OR UPDATE OR DELETE ON developer_announcements
        FOR EACH ROW
        EXECUTE FUNCTION increment_announcements_global_version();
    """)


def downgrade() -> None:
    # Drop triggers
    op.execute("DROP TRIGGER IF EXISTS trg_announcements_version ON developer_announcements;")
    op.execute("DROP TRIGGER IF EXISTS trg_messages_version ON chat_messages;")
    op.execute("DROP TRIGGER IF EXISTS trg_notifications_version ON notifications;")
    op.execute("DROP TRIGGER IF EXISTS trg_tasks_version ON tasks;")

    # Drop functions
    op.execute("DROP FUNCTION IF EXISTS increment_announcements_global_version();")
    op.execute("DROP FUNCTION IF EXISTS increment_messages_version();")
    op.execute("DROP FUNCTION IF EXISTS increment_user_state_version();")

    # Drop table
    op.drop_table("user_state_version")
