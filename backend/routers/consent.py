from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from core.auth import get_current_user
from core.db import get_db
from models import Consent, User
from schemas.api import ConsentIn
from services import privacy

router = APIRouter(prefix="/api", tags=["consent"])


def _out(c: Consent | None) -> dict:
    return {
        "tracking": bool(c and c.tracking),
        "ai_processing": bool(c and c.ai_processing),
        "store_scam_text": bool(c and c.store_scam_text),
        "updated_at": c.updated_at.isoformat() if c and c.updated_at else None,
        "notes_en": {
            "tracking": "Records which buttons you use (never what you type) so help can fade as you learn.",
            "ai_processing": "Lets us send a message with numbers and names removed to Google Gemini when our rules are unsure. On the free tier Google may use it to improve its products.",
            "store_scam_text": "Keeps a copy of checked messages (numbers removed). Off by default.",
        },
    }


@router.get("/consent")
async def get_consent(user: Annotated[User, Depends(get_current_user)],
                      db: Annotated[AsyncSession, Depends(get_db)]):
    return _out(await privacy.get_consent(db, user.id))


@router.put("/consent")
async def put_consent(body: ConsentIn, user: Annotated[User, Depends(get_current_user)],
                      db: Annotated[AsyncSession, Depends(get_db)]):
    c = await privacy.get_consent(db, user.id)
    if c is None:
        c = Consent(user_id=user.id, tracking=False, ai_processing=False, store_scam_text=False)
        db.add(c)
    for k, v in body.model_dump(exclude_none=True).items():
        setattr(c, k, v)
    await db.commit()
    await db.refresh(c)
    return _out(c)
