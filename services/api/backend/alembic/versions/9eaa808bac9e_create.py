"""create tasks table (idempotent enums)

Revision ID: 9eaa808bac9e
Revises: c6c6c641b486
Create Date: 2025-10-09 13:44:20.106392
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = "9eaa808bac9e"
down_revision = "c6c6c641b486"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# 1) Создаём enum-типы ИДЕМПОТЕНТНО (если уже есть — молча пропускаем)
	op.execute("""
	DO $$
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_priority') THEN
			CREATE TYPE task_priority AS ENUM ('low','medium','high');
		END IF;
		IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_status') THEN
			CREATE TYPE task_status AS ENUM ('pending','in_progress','done');
		END IF;
		IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_recurrence') THEN
			CREATE TYPE task_recurrence AS ENUM ('none','daily','weekly');
		END IF;
	END$$;
	""")

	# 2) Колонки с ENUM не должны пытаться создавать тип повторно
	priority_enum = postgresql.ENUM(
		'low','medium','high', name='task_priority', create_type=False
	)
	status_enum = postgresql.ENUM(
		'pending','in_progress','done', name='task_status', create_type=False
	)
	recurrence_enum = postgresql.ENUM(
		'none','daily','weekly', name='task_recurrence', create_type=False
	)

	# 3) Создаём таблицу только если её нет
	bind = op.get_bind()
	insp = inspect(bind)
	if not insp.has_table("tasks"):
		op.create_table(
			"tasks",
			sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
			sa.Column("title", sa.String(length=255), nullable=False),
			sa.Column("description", sa.String(length=2048), nullable=False, server_default=""),
			sa.Column("priority", priority_enum, nullable=False, server_default="medium"),
			sa.Column("status", status_enum, nullable=False, server_default="pending"),
			sa.Column("due_at", sa.DateTime(timezone=True), nullable=True),
			sa.Column("recurrence", recurrence_enum, nullable=False, server_default="none"),
			sa.Column(
				"created_at",
				sa.DateTime(timezone=True),
				nullable=False,
				server_default=sa.text("timezone('utc', now())"),
			),
			sa.Column(
				"updated_at",
				sa.DateTime(timezone=True),
				nullable=False,
				server_default=sa.text("timezone('utc', now())"),
			),
		)

	# 4) Индекс — только если его нет
	op.execute('CREATE INDEX IF NOT EXISTS ix_tasks_created_at ON tasks (created_at)')


def downgrade() -> None:
	# индекс/таблица — безопасные дропы (если вдруг их не было из-за старых пустых ревизий)
	op.execute('DROP INDEX IF EXISTS ix_tasks_created_at')
	op.execute('DROP TABLE IF EXISTS tasks CASCADE')

	# enum-типы — тоже безопасно
	op.execute("DO $$ BEGIN DROP TYPE IF EXISTS task_status;  EXCEPTION WHEN undefined_object THEN NULL; END $$;")
	op.execute("DO $$ BEGIN DROP TYPE IF EXISTS task_priority; EXCEPTION WHEN undefined_object THEN NULL; END $$;")
	op.execute("DO $$ BEGIN DROP TYPE IF EXISTS task_recurrence; EXCEPTION WHEN undefined_object THEN NULL; END $$;")
