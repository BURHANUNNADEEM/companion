from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from core.auth import get_current_user
from core.db import get_db
from models import Event, User
from schemas.events import EventIn

router = APIRouter(prefix="/api", tags=["me"])


@router.get("/me")
async def me(user: Annotated[User, Depends(get_current_user)]):
    return {"id": user.id, "firebase_uid": user.firebase_uid}


@router.post("/events", status_code=201)
async def track_event(
    body: EventIn,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    db.add(Event(user_id=user.id, **body.model_dump()))
    await db.commit()
    return {"ok": True}