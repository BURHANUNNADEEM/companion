from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from core.auth import get_current_user
from core.db import get_db
from models import Event, User
from schemas.events import EventBatchIn, EventIn
from services import privacy

router = APIRouter(prefix="/api", tags=["events"])


def _row(user_id: int, e: EventIn, session_id: str | None) -> Event:
    props = privacy.sanitize_props(e.properties)
    if session_id:
        props["session_id"] = session_id
    row = Event(user_id=user_id, event_type=e.event_type, item_id=e.item_id, properties=props)
    if e.occurred_at is not None:
        row.created_at = e.occurred_at
    return row


@router.post("/events", status_code=201)
async def track_event(
    body: EventIn,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    await privacy.require_tracking(db, user.id)
    db.add(_row(user.id, body, None))
    await db.commit()
    return {"ok": True}


@router.post("/events/batch", status_code=201)
async def track_events_batch(
    body: EventBatchIn,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    await privacy.require_tracking(db, user.id)
    db.add_all([_row(user.id, e, body.session_id) for e in body.events])
    await db.commit()
    return {"ok": True, "accepted": len(body.events)}
