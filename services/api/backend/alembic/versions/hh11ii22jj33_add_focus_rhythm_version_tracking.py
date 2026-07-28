"""add focus_version and rhythm_version columns with triggers

Revision ID: hh11ii22jj33
Revises: 705c3e380595
Create Date: 2026-02-16 12:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "hh11ii22jj33"
down_revision = "705c3e380595"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Add version columns to user_state_version
    op.add_column(
        "user_state_version",
        sa.Column("focus_version", sa.BigInteger(), nullable=False, server_default="0"),
    )
    op.add_column(
        "user_state_version",
        sa.Column("rhythm_version", sa.BigInteger(), nullable=False, server_default="0"),
    )

    # 2. Focus domain triggers (all tables have user_id, reuse increment_user_state_version)
    op.execute("""
        CREATE TRIGGER trg_focus_sessions_version
        AFTER INSERT OR UPDATE OR DELETE ON focus_sessions
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('focus_version');
    """)

    op.execute("""
        CREATE TRIGGER trg_user_balance_version
        AFTER INSERT OR UPDATE OR DELETE ON user_balance
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('focus_version');
    """)

    op.execute("""
        CREATE TRIGGER trg_user_shop_items_version
        AFTER INSERT OR UPDATE OR DELETE ON user_shop_items
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('focus_version');
    """)

    op.execute("""
        CREATE TRIGGER trg_gamification_profile_version
        AFTER INSERT OR UPDATE OR DELETE ON user_gamification_profile
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('focus_version');
    """)

    # 3. Rhythm domain triggers

    # rhythm_templates has user_id directly
    op.execute("""
        CREATE TRIGGER trg_rhythm_templates_version
        AFTER INSERT OR UPDATE OR DELETE ON rhythm_templates
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('rhythm_version');
    """)

    # rhythm_segments and rhythm_assignments need JOIN through template_id
    op.execute("""
        CREATE OR REPLACE FUNCTION increment_rhythm_version_via_template()
        RETURNS TRIGGER AS $$
        DECLARE
            _user_id UUID;
            _template_id UUID;
        BEGIN
            -- Get template_id from NEW or OLD
            IF TG_OP = 'DELETE' THEN
                _template_id := OLD.template_id;
            ELSE
                _template_id := NEW.template_id;
            END IF;

            SELECT user_id INTO _user_id
            FROM rhythm_templates
            WHERE id = _template_id;

            IF _user_id IS NOT NULL THEN
                INSERT INTO user_state_version (user_id, rhythm_version)
                VALUES (_user_id, 1)
                ON CONFLICT (user_id)
                DO UPDATE SET rhythm_version = user_state_version.rhythm_version + 1;
            END IF;

            RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;
    """)

    op.execute("""
        CREATE TRIGGER trg_rhythm_segments_version
        AFTER INSERT OR UPDATE OR DELETE ON rhythm_segments
        FOR EACH ROW
        EXECUTE FUNCTION increment_rhythm_version_via_template();
    """)

    op.execute("""
        CREATE TRIGGER trg_rhythm_assignments_version
        AFTER INSERT OR UPDATE OR DELETE ON rhythm_assignments
        FOR EACH ROW
        EXECUTE FUNCTION increment_rhythm_version_via_template();
    """)


def downgrade() -> None:
    # Drop triggers
    op.execute("DROP TRIGGER IF EXISTS trg_rhythm_assignments_version ON rhythm_assignments;")
    op.execute("DROP TRIGGER IF EXISTS trg_rhythm_segments_version ON rhythm_segments;")
    op.execute("DROP TRIGGER IF EXISTS trg_rhythm_templates_version ON rhythm_templates;")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_gamification_profile_version ON user_gamification_profile;"
    )
    op.execute("DROP TRIGGER IF EXISTS trg_user_shop_items_version ON user_shop_items;")
    op.execute("DROP TRIGGER IF EXISTS trg_user_balance_version ON user_balance;")
    op.execute("DROP TRIGGER IF EXISTS trg_focus_sessions_version ON focus_sessions;")

    # Drop function
    op.execute("DROP FUNCTION IF EXISTS increment_rhythm_version_via_template();")

    # Drop columns
    op.drop_column("user_state_version", "rhythm_version")
    op.drop_column("user_state_version", "focus_version")
