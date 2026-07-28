"""Bump focus_version on mascot skin changes (user-scoped + catalog-wide)

Revision ID: eeee_mascot_skins_sync_triggers
Revises: dddd_mascot_skins
Create Date: 2026-04-29 01:00:00.000000
"""

from __future__ import annotations

from alembic import op


revision = "eeee_mascot_skins_sync_triggers"
down_revision = "dddd_mascot_skins"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # User-scoped: row in user_mascot_skins (purchase/refund) → bump focus_version
    op.execute("""
        CREATE TRIGGER trg_user_mascot_skins_version
        AFTER INSERT OR UPDATE OR DELETE ON user_mascot_skins
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('focus_version');
    """)

    # User-scoped: users.active_mascot_skin_id changed → bump focus_version
    # Trigger only when this specific column actually changes (avoid noise on
    # unrelated user updates).
    op.execute("""
        CREATE OR REPLACE FUNCTION bump_focus_version_on_active_skin_change()
        RETURNS TRIGGER AS $$
        BEGIN
            INSERT INTO user_state_version (user_id, focus_version)
            VALUES (NEW.id, 1)
            ON CONFLICT (user_id)
            DO UPDATE SET focus_version = user_state_version.focus_version + 1;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
    """)

    op.execute("""
        CREATE TRIGGER trg_users_active_skin_version
        AFTER UPDATE OF active_mascot_skin_id ON users
        FOR EACH ROW
        WHEN (OLD.active_mascot_skin_id IS DISTINCT FROM NEW.active_mascot_skin_id)
        EXECUTE FUNCTION bump_focus_version_on_active_skin_change();
    """)

    # Catalog-wide: mascot_skins changed → bump focus_version for ALL users
    # (analogous to the announcements global broadcast).
    op.execute("""
        CREATE OR REPLACE FUNCTION increment_focus_version_global()
        RETURNS TRIGGER AS $$
        BEGIN
            UPDATE user_state_version
            SET focus_version = focus_version + 1;
            RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;
    """)

    op.execute("""
        CREATE TRIGGER trg_mascot_skins_version
        AFTER INSERT OR UPDATE OR DELETE ON mascot_skins
        FOR EACH ROW
        EXECUTE FUNCTION increment_focus_version_global();
    """)


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_mascot_skins_version ON mascot_skins;")
    op.execute("DROP TRIGGER IF EXISTS trg_users_active_skin_version ON users;")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_user_mascot_skins_version ON user_mascot_skins;"
    )
    op.execute("DROP FUNCTION IF EXISTS increment_focus_version_global();")
    op.execute("DROP FUNCTION IF EXISTS bump_focus_version_on_active_skin_change();")
