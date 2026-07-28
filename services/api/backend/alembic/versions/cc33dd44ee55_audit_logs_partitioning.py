"""audit_logs partitioning with pg_partman

Revision ID: cc33dd44ee55
Revises: bb11cc22dd33
Create Date: 2026-02-13 12:00:00.000000
"""

from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "cc33dd44ee55"
down_revision = "bb11cc22dd33"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Check pg_partman availability (Supabase has it; skip gracefully if missing)
    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_available_extensions WHERE name = 'pg_partman'
            ) THEN
                RAISE NOTICE 'pg_partman not available — skipping audit_logs partitioning';
                RETURN;
            END IF;

            -- Enable extension
            CREATE EXTENSION IF NOT EXISTS pg_partman;

            -- 2. Create partitioned table
            CREATE TABLE IF NOT EXISTS audit_logs_new (
                id          VARCHAR(36)                NOT NULL,
                admin_user_id VARCHAR(36)              NOT NULL,
                action      VARCHAR(100)               NOT NULL,
                target_user_id VARCHAR(36),
                details     JSONB,
                ip_address  VARCHAR(45),
                user_agent  VARCHAR(500),
                created_at  TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),
                PRIMARY KEY (id, created_at)
            ) PARTITION BY RANGE (created_at);

            -- 3. Setup pg_partman (monthly partitions, 3 months pre-made)
            PERFORM partman.create_parent(
                p_parent_table := 'public.audit_logs_new',
                p_control      := 'created_at',
                p_type         := 'native',
                p_interval     := 'monthly',
                p_premake      := 3
            );

            -- 4. Set 90-day retention (drop old partitions automatically)
            UPDATE partman.part_config
            SET    retention            = '90 days',
                   retention_keep_table = false
            WHERE  parent_table = 'public.audit_logs_new';

            -- 5. Dual-write trigger: copies INSERT on old table into new partitioned table
            CREATE OR REPLACE FUNCTION audit_logs_dual_write()
            RETURNS TRIGGER AS $trg$
            BEGIN
                INSERT INTO audit_logs_new (
                    id, admin_user_id, action, target_user_id,
                    details, ip_address, user_agent, created_at
                ) VALUES (
                    NEW.id, NEW.admin_user_id, NEW.action, NEW.target_user_id,
                    NEW.details, NEW.ip_address, NEW.user_agent, NEW.created_at
                ) ON CONFLICT (id, created_at) DO NOTHING;
                RETURN NEW;
            END;
            $trg$ LANGUAGE plpgsql;

            CREATE TRIGGER trg_audit_logs_dual_write
            AFTER INSERT ON audit_logs
            FOR EACH ROW EXECUTE FUNCTION audit_logs_dual_write();

            -- 6. Indexes on partitioned table (inherited by child partitions)
            CREATE INDEX IF NOT EXISTS idx_audit_logs_new_admin_user_id
                ON audit_logs_new (admin_user_id);
            CREATE INDEX IF NOT EXISTS idx_audit_logs_new_action
                ON audit_logs_new (action);
            CREATE INDEX IF NOT EXISTS idx_audit_logs_new_target_user_id
                ON audit_logs_new (target_user_id);

        END $$;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
            -- Drop trigger
            DROP TRIGGER IF EXISTS trg_audit_logs_dual_write ON audit_logs;
            DROP FUNCTION IF EXISTS audit_logs_dual_write();

            -- Drop partitioned table (cascades to child partitions)
            DROP TABLE IF EXISTS audit_logs_new CASCADE;

            -- Remove pg_partman config entry
            IF EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'partman' AND table_name = 'part_config'
            ) THEN
                DELETE FROM partman.part_config
                WHERE parent_table = 'public.audit_logs_new';
            END IF;
        END $$;
        """
    )
