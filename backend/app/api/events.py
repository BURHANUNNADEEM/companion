"""/api/events - batch upload of ACTION-ONLY events (F2). Content is never accepted."""
from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_current_user
from app.core.db import get_db
from app.models import Event, User
from app.services.caregiver import check_repeated_struggle
from app.services.consent import has_consent

router = APIRouter(tags=["events"])

EVENT_TYPES = {
    "screen_view", "tap", "back", "idle", "task_started", "task_completed", "suggestion_shown",
    "suggestion_accepted", "suggestion_dismissed", "something_else_tapped", "nav_started", "nav_completed",
    "nav_aborted",
    # documented addition: lets the caregiver summary count struggle episodes (counts only)
    "struggle_detected",
}
# Allowed property keys. Anything else (text, name, number, message...) is dropped.
ALLOWED_PROPS = {
    "screen", "target", "task", "workflow_id", "skill_id", "score", "signals", "duration_ms", "reason",
    "rank", "hour", "tier", "mode", "step", "steps_total", "source", "lang", "package",
}
_ID = re.compile(r"^[a-z0-9_.:\-]{1,64}$")
_SAFE_STR = re.compile(r"^[A-Za-z0-9_.:\-]{1,64}$")


class EventIn(BaseModel):
    type: str
    item_id: str | None = None
    ts: datetime | None = None
    properties: dict = Field(default_factory=dict)


class EventBatch(BaseModel):
    session_id: str = Field(min_length=1, max_length=64)
    events: list[EventIn] = Field(max_length=200)


def clean_properties(props: dict) -> dict:
    out: dict = {}
    for k, v in (props or {}).items():
        if k not in ALLOWED_PROPS:
            continue
        if isinstance(v, bool) or isinstance(v, (int, float)):
            out[k] = v
        elif isinstance(v, str) and _SAFE_STR.match(v):
            out[k] = v
        elif isinstance(v, list) and len(v) <= 10 and all(isinstance(x, str) and _SAFE_STR.match(x) for x in v):
            out[k] = v
    return out


@router.post("/events")
async def post_events(batch: EventBatch, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    # Nothing is logged before consent (F5 acceptance).
    if not await has_consent(db, user.id, "activity_tracking"):
        raise HTTPException(403, "consent_required")
    if not _SAFE_STR.match(batch.session_id):
        raise HTTPException(422, "bad_session_id")
    now = datetime.now(timezone.utc)
    accepted, rejected = 0, 0
    struggle_tasks: set[str] = set()
    for e in batch.events:
        if e.type not in EVENT_TYPES or (e.item_id is not None and not _ID.match(e.item_id)):
            rejected += 1
            continue
        ts = e.ts or now
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        if ts > now + timedelta(minutes=5) or ts < now - timedelta(days=7):
            ts = now
        props = clean_properties(e.properties)
        db.add(Event(user_id=user.id, event_type=e.type, item_id=e.item_id, session_id=batch.session_id,
                     properties=props, created_at=ts))
        accepted += 1
        if e.type == "struggle_detected":
            struggle_tasks.add(props.get("task") or e.item_id or "")
    await db.flush()
    for task in struggle_tasks:
        await check_repeated_struggle(db, user.id, task)
    await db.commit()
    return {"accepted": accepted, "rejected": rejected}
