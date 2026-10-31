from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from core.auth import get_current_user
from core.db import get_db
from models import Event, User
from schemas.api import VoiceIntentIn
from services import intents, privacy

router = APIRouter(prefix="/api/voice", tags=["voice"])


@router.post("/intent")
async def voice_intent(body: VoiceIntentIn, user: Annotated[User, Depends(get_current_user)],
                       db: Annotated[AsyncSession, Depends(get_db)]):
    """Maps a transcript to ONE allowlisted workflow id. Never executes anything."""
    c = await privacy.get_consent(db, user.id)
    res = await intents.parse(body.transcript, use_ai=bool(c and c.ai_processing))
    if c and c.tracking:  # log outcome only, never the transcript
        db.add(Event(user_id=user.id, event_type="voice_intent", item_id=res["task_id"],
                     properties={"source": res["source"], "confidence": res["confidence"]}))
        await db.commit()
    return res
