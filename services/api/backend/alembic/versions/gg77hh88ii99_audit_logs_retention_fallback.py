"""audit_logs retention fallback when pg_partman is unavailable

Revision ID: gg77hh88ii99
Revises: ff77aa88bb99
Create Date: 2026-02-14 16:00:00.000000
"""

from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "gg77hh88ii99"
down_revision = "ff77aa88bb99"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
            -- If pg_partman is available, Stage 5 partition retention is authoritative.
            IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_partman') THEN
                DROP TRIGGER IF EXISTS trg_audit_logs_retention_fallback ON public.audit_logs;
                DROP FUNCTION IF EXISTS public.audit_logs_retention_fallback();
                RETURN;
            END IF;

            -- Fallback policy for environments without pg_partman:
            -- 1) one-time cleanup
            -- 2) statement-level retention trigger (90 days).
            IF EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'audit_logs'
            ) THEN
                DELETE FROM public.audit_logs
                WHERE created_at < (NOW() - INTERVAL '90 days');

                CREATE OR REPLACE FUNCTION public.audit_logs_retention_fallback()
                RETURNS TRIGGER AS $trg$
                BEGIN
                    DELETE FROM public.audit_logs
                    WHERE created_at < (NOW() - INTERVAL '90 days');
                    RETURN NULL;
                END;
                $trg$ LANGUAGE plpgsql;

                DROP TRIGGER IF EXISTS trg_audit_logs_retention_fallback ON public.audit_logs;
                CREATE TRIGGER trg_audit_logs_retention_fallback
                AFTER INSERT ON public.audit_logs
                FOR EACH STATEMENT
                EXECUTE FUNCTION public.audit_logs_retention_fallback();
            END IF;
        END $$;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP TRIGGER IF EXISTS trg_audit_logs_retention_fallback ON public.audit_logs;
        DROP FUNCTION IF EXISTS public.audit_logs_retention_fallback();
        """
    )
