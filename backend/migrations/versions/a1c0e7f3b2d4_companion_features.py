"""companion features: profile, consents, task attempts/progress, scam checks

Idempotent: safe to run whether or not clerk_id was already renamed or the
tables were created by init_db.py.

Revision ID: a1c0e7f3b2d4
Revises: 5ecd32ef857a
Create Date: 2026-10-31 13:40:00
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "a1c0e7f3b2d4"
down_revision: Union[str, Sequence[str], None] = "5ecd32ef857a"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _cols(insp, table: str) -> set[str]:
    return {c["name"] for c in insp.get_columns(table)}


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    # users: clerk_id -> firebase_uid (the previous migration was empty)
    ucols = _cols(insp, "users")
    if "clerk_id" in ucols and "firebase_uid" not in ucols:
        op.alter_column("users", "clerk_id", new_column_name="firebase_uid")
        op.execute("ALTER INDEX IF EXISTS ix_users_clerk_id RENAME TO ix_users_firebase_uid")
        ucols = _cols(sa.inspect(bind), "users")
    if "display_name" not in ucols:
        op.add_column("users", sa.Column("display_name", sa.String(80), nullable=True))
    if "language" not in ucols:
        op.add_column("users", sa.Column("language", sa.String(8), nullable=False, server_default="ur"))

    if "consents" not in tables:
        op.create_table(
            "consents",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("tracking", sa.Boolean(), nullable=False, server_default="false"),
            sa.Column("ai_processing", sa.Boolean(), nullable=False, server_default="false"),
            sa.Column("store_scam_text", sa.Boolean(), nullable=False, server_default="false"),
            sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        )
        op.create_index("ix_consents_user_id", "consents", ["user_id"], unique=True)

    if "task_attempts" not in tables:
        op.create_table(
            "task_attempts",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("task_id", sa.String(64), nullable=False),
            sa.Column("status", sa.String(16), nullable=False),
            sa.Column("start_help_level", sa.String(16), nullable=False),
            sa.Column("clean", sa.Boolean(), nullable=True),
            sa.Column("struggle_count", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("duration_ms", sa.Integer(), nullable=True),
            sa.Column("started_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
            sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        )
        op.create_index("ix_task_attempts_user_id", "task_attempts", ["user_id"])
        op.create_index("ix_task_attempts_user_task", "task_attempts", ["user_id", "task_id"])

    if "task_progress" not in tables:
        op.create_table(
            "task_progress",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("task_id", sa.String(64), nullable=False),
            sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("completions", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("clean_completions", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("independent_completions", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("mastered", sa.Boolean(), nullable=False, server_default="false"),
            sa.Column("struggle_by_step", postgresql.JSONB(), nullable=False, server_default="{}"),
            sa.Column("last_done_at", sa.DateTime(timezone=True), nullable=True),
            sa.UniqueConstraint("user_id", "task_id", name="uq_task_progress_user_task"),
        )
        op.create_index("ix_task_progress_user_id", "task_progress", ["user_id"])

    if "scam_checks" not in tables:
        op.create_table(
            "scam_checks",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("verdict", sa.String(16), nullable=False),
            sa.Column("score", sa.Integer(), nullable=False),
            sa.Column("reasons", postgresql.JSONB(), nullable=False, server_default="[]"),
            sa.Column("source", sa.String(16), nullable=False),
            sa.Column("input_source", sa.String(16), nullable=False, server_default="paste"),
            sa.Column("redacted_text", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        )
        op.create_index("ix_scam_checks_user_id", "scam_checks", ["user_id"])


def downgrade() -> None:
    for t in ("scam_checks", "task_progress", "task_attempts", "consents"):
        op.drop_table(t)
    op.drop_column("users", "language")
    op.drop_column("users", "display_name")
