from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from core.db import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    firebase_uid: Mapped[str] = mapped_column(String, unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(80), nullable=True)
    language: Mapped[str] = mapped_column(String(8), default="ur", server_default="ur")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (Index("ix_events_user_created", "user_id", "created_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    event_type: Mapped[str] = mapped_column(String, index=True)  # "screen_view", "tap", ...
    item_id: Mapped[str | None] = mapped_column(String, index=True)
    properties: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Consent(Base):
    """One row per user. Nothing is tracked until `tracking` is true."""

    __tablename__ = "consents"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    tracking: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    ai_processing: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    store_scam_text: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class TaskAttempt(Base):
    """One run of a predefined workflow (start -> complete/abandon)."""

    __tablename__ = "task_attempts"
    __table_args__ = (Index("ix_task_attempts_user_task", "user_id", "task_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    task_id: Mapped[str] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(16), default="started")  # started|completed|abandoned
    start_help_level: Mapped[str] = mapped_column(String(16))
    clean: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    struggle_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class TaskProgress(Base):
    """Learning record per user per task (drives the help-that-fades ladder)."""

    __tablename__ = "task_progress"
    __table_args__ = (UniqueConstraint("user_id", "task_id", name="uq_task_progress_user_task"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    task_id: Mapped[str] = mapped_column(String(64))
    attempts: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    completions: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    clean_completions: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    independent_completions: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    mastered: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    struggle_by_step: Mapped[dict] = mapped_column(JSONB, default=dict)
    last_done_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ScamCheck(Base):
    """Verdict only. Message text is stored ONLY if the user consented."""

    __tablename__ = "scam_checks"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    verdict: Mapped[str] = mapped_column(String(16))  # probably_fine|be_careful|likely_scam
    score: Mapped[int] = mapped_column(Integer)
    reasons: Mapped[list] = mapped_column(JSONB, default=list)
    source: Mapped[str] = mapped_column(String(16))  # rules|rules+gemini
    input_source: Mapped[str] = mapped_column(String(16), default="paste")
    redacted_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
