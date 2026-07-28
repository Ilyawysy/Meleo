"""stage 5 follow-up: finalize audit_logs cutover and sync indexes

Revision ID: ee55ff66gg77
Revises: ee66ff77gg88
Create Date: 2026-02-14 13:10:00.000000
"""

from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "ee55ff66gg77"
down_revision = "ee66ff77gg88"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
            -- Stage 5.3/5.5 follow-up indexes.
            CREATE INDEX IF NOT EXISTS idx_announcements_updated_cursor
                ON developer_announcements (updated_at, id)
                WHERE is_active = true;

            -- Duplicate of uq_user_announcement index path.
            DROP INDEX IF EXISTS idx_announcement_reads_user_ann;

            -- Stage 5.1 cutover: move reads/writes to partitioned audit_logs table.
            IF EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'audit_logs_new'
            ) THEN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_extension WHERE extname = 'pg_partman'
                ) THEN
                    RAISE EXCEPTION 'pg_partman extension is required for audit_logs cutover';
                END IF;

                IF NOT EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'public' AND table_name = 'audit_logs'
                ) THEN
                    RAISE EXCEPTION 'audit_logs table is missing, cannot validate cutover';
                END IF;

                IF EXISTS (
                    SELECT 1
                    FROM public.audit_logs src
                    LEFT JOIN public.audit_logs_new dst
                      ON dst.id = src.id
                     AND dst.created_at = src.created_at
                    WHERE dst.id IS NULL
                    LIMIT 1
                ) THEN
                    RAISE EXCEPTION 'audit_logs_new is missing rows from audit_logs. Run python -m scripts.backfill_audit_logs before migration.';
                END IF;

                DROP TRIGGER IF EXISTS trg_audit_logs_dual_write ON public.audit_logs;
                DROP FUNCTION IF EXISTS public.audit_logs_dual_write();

                IF EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'public' AND table_name = 'audit_logs_legacy'
                ) THEN
                    RAISE EXCEPTION 'audit_logs_legacy already exists; manual cutover state detected';
                END IF;

                ALTER TABLE public.audit_logs RENAME TO audit_logs_legacy;
                ALTER TABLE public.audit_logs_new RENAME TO audit_logs;

                IF EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'partman' AND table_name = 'part_config'
                ) THEN
                    UPDATE partman.part_config
                    SET parent_table = 'public.audit_logs'
                    WHERE parent_table = 'public.audit_logs_new';
                END IF;
            END IF;
        END $$;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
            DROP INDEX IF EXISTS idx_announcements_updated_cursor;
            CREATE INDEX IF NOT EXISTS idx_announcement_reads_user_ann
                ON user_announcement_reads (user_id, announcement_id);

            IF EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'audit_logs_legacy'
            )
            AND EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'audit_logs'
            )
            AND NOT EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'audit_logs_new'
            ) THEN
                ALTER TABLE public.audit_logs RENAME TO audit_logs_new;
                ALTER TABLE public.audit_logs_legacy RENAME TO audit_logs;

                IF EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'partman' AND table_name = 'part_config'
                ) THEN
                    UPDATE partman.part_config
                    SET parent_table = 'public.audit_logs_new'
                    WHERE parent_table = 'public.audit_logs';
                END IF;

                CREATE OR REPLACE FUNCTION public.audit_logs_dual_write()
                RETURNS TRIGGER AS $trg$
                BEGIN
                    INSERT INTO public.audit_logs_new (
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
                AFTER INSERT ON public.audit_logs
                FOR EACH ROW EXECUTE FUNCTION public.audit_logs_dual_write();
            END IF;
        END $$;
        """
    )
