from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from core.auth import get_current_user
from core.db import get_db
from models import ScamCheck, User
from schemas.api import ScamCheckIn
from services import privacy, scam_service

router = APIRouter(prefix="/api/scam", tags=["scam"])


@router.post("/check")
async def scam_check(body: ScamCheckIn, user: Annotated[User, Depends(get_current_user)],
                     db: Annotated[AsyncSession, Depends(get_db)]):
    c = await privacy.get_consent(db, user.id)
    return await scam_service.check(
        db, user.id, body.text, body.source,
        ai_allowed=bool(c and c.ai_processing),
        store_text=bool(c and c.store_scam_text),
    )


@router.get("/history")
async def scam_history(user: Annotated[User, Depends(get_current_user)],
                       db: Annotated[AsyncSession, Depends(get_db)],
                       limit: Annotated[int, Query(ge=1, le=100)] = 20):
    rows = (await db.execute(
        select(ScamCheck).where(ScamCheck.user_id == user.id).order_by(ScamCheck.id.desc()).limit(limit)
    )).scalars().all()
    counts = dict((await db.execute(
        select(ScamCheck.verdict, func.count()).where(ScamCheck.user_id == user.id).group_by(ScamCheck.verdict)
    )).all())
    return {
        "counts": {k: counts.get(k, 0) for k in ("likely_scam", "be_careful", "probably_fine")},
        "items": [
            {"id": r.id, "verdict": r.verdict, "score": r.score, "reasons": r.reasons, "source": r.source,
             "created_at": r.created_at.isoformat() if r.created_at else None}
            for r in rows
        ],
    }
