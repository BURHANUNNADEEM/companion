"""Initial schema: users (auth_id, role, language), consents, events, caregiver_links,
scam_checks, alerts, guide_cards.

If you are migrating an older database that still has `users.clerk_id`, stamp this
revision and let 0002_clerk_to_auth_id rename the column (PRD §7 auth migration note).

Revision ID: 0001_initial
Revises:
Create Date: 2026-10-31
"""
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None

JSONT = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("auth_id", sa.String(128), nullable=False),
        sa.Column("email", sa.String(320), nullable=True),
        sa.Column("role", sa.String(16), nullable=True),
        sa.Column("language", sa.String(8), nullable=False, server_default="ur"),
        sa.Column("display_name", sa.String(60), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_users_auth_id", "users", ["auth_id"], unique=True)

    op.create_table(
        "consents",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("type", sa.String(32), nullable=False),
        sa.Column("granted", sa.Boolean, nullable=False),
        sa.Column("timestamp", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_consents_user_id", "consents", ["user_id"])

    op.create_table(
        "events",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("event_type", sa.String(32), nullable=False),
        sa.Column("item_id", sa.String(64), nullable=True),
        sa.Column("session_id", sa.String(64), nullable=True),
        sa.Column("properties", JSONT, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_events_user_id", "events", ["user_id"])
    op.create_index("ix_events_event_type", "events", ["event_type"])
    op.create_index("ix_events_created_at", "events", ["created_at"])
    op.create_index("ix_events_user_type_time", "events", ["user_id", "event_type", "created_at"])

    op.create_table(
        "caregiver_links",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("parent_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("caregiver_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=True),
        sa.Column("invite_email", sa.String(320), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("invite_code", sa.String(16), nullable=True, unique=True),
        sa.Column("invite_expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("permissions", JSONT, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_caregiver_links_parent_id", "caregiver_links", ["parent_id"])
    op.create_index("ix_caregiver_links_caregiver_id", "caregiver_links", ["caregiver_id"])

    op.create_table(
        "scam_checks",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("verdict", sa.String(16), nullable=False),
        sa.Column("score", sa.Float, nullable=False),
        sa.Column("reasons", JSONT, nullable=False),
        sa.Column("source", sa.String(16), nullable=False),
        sa.Column("engine", sa.String(16), nullable=False),
        sa.Column("redacted_text", sa.Text, nullable=True),
        sa.Column("shared_with_family", sa.Boolean, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_scam_checks_user_id", "scam_checks", ["user_id"])

    op.create_table(
        "alerts",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("parent_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("caregiver_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("type", sa.String(32), nullable=False),
        sa.Column("payload", JSONT, nullable=False),
        sa.Column("dedupe_key", sa.String(128), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("seen_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_alerts_parent_id", "alerts", ["parent_id"])
    op.create_index("ix_alerts_caregiver_id", "alerts", ["caregiver_id"])
    op.create_index("ix_alerts_dedupe_key", "alerts", ["dedupe_key"])

    op.create_table(
        "guide_cards",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("parent_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("caregiver_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("text", sa.String(280), nullable=False),
        sa.Column("workflow_id", sa.String(64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("seen_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_guide_cards_parent_id", "guide_cards", ["parent_id"])
    op.create_index("ix_guide_cards_caregiver_id", "guide_cards", ["caregiver_id"])


def downgrade() -> None:
    for t in ("guide_cards", "alerts", "scam_checks", "caregiver_links", "events", "consents", "users"):
        op.drop_table(t)
