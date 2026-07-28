"""Add focus_version triggers for checklist_items and focus_task_segments

Revision ID: bbbb_focus_version_triggers
Revises: aaaa_focus_rooms_refactor
Create Date: 2026-04-21 00:00:00.000000
"""

from __future__ import annotations

from alembic import op

revision = "bbbb_focus_version_triggers"
down_revision = "aaaa_focus_rooms_refactor"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE OR REPLACE FUNCTION increment_focus_version_via_task()
        RETURNS TRIGGER AS $$
        DECLARE
            _user_id UUID;
            _task_id UUID;
        BEGIN
            IF TG_OP = 'DELETE' THEN
                _task_id := OLD.task_id;
            ELSE
                _task_id := NEW.task_id;
            END IF;

            SELECT user_id INTO _user_id FROM tasks WHERE id = _task_id;

            IF _user_id IS NOT NULL THEN
                INSERT INTO user_state_version (user_id, focus_version) VALUES (_user_id, 1)
                ON CONFLICT (user_id)
                DO UPDATE SET focus_version = user_state_version.focus_version + 1;
            END IF;

            RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;
    """)

    op.execute("""
        CREATE TRIGGER trg_checklist_items_version
        AFTER INSERT OR UPDATE OR DELETE ON checklist_items
        FOR EACH ROW
        EXECUTE FUNCTION increment_focus_version_via_task();
    """)

    op.execute("""
        CREATE TRIGGER trg_focus_task_segments_version
        AFTER INSERT OR UPDATE OR DELETE ON focus_task_segments
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('focus_version');
    """)


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_checklist_items_version ON checklist_items;")
    op.execute("DROP TRIGGER IF EXISTS trg_focus_task_segments_version ON focus_task_segments;")
    op.execute("DROP FUNCTION IF EXISTS increment_focus_version_via_task();")
