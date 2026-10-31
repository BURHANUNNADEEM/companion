"""/api/scam - check, share verdict with family, history (F6)."""
from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_current_user
from app.core.db import get_db
from app.models import ScamCheck, User
from app.services import llm
from app.services.caregiver import alert_scam_shared
from app.services.consent import has_consent
from app.services.i18n import lang_or_default
from app.services.redaction import redact
from app.services.scam_rules import explain, needs_llm, run_rules, verdict_for

router = APIRouter(tags=["scam"])


class ScamIn(BaseModel):
    text: str = Field(min_length=1, max_length=5000)
    source: Literal["paste", "share", "screenshot"] = "paste"


@router.post("/scam/check")
async def scam_check(body: ScamIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    lang = lang_or_default(user.language)
    rules = run_rules(body.text)
    verdict, score, flags, engine, llm_reason = rules.verdict, rules.score, list(rules.flags), "rules", None
    redacted = redact(body.text)

    if needs_llm(rules):
        out = await llm.classify_scam(user.id, redacted)
        if out is not None and out.confidence >= 0.5:
            engine = "llm"
            verdict = out.verdict
            # blend: LLM decides the level, score kept consistent with the level
            score = round(max(score, out.confidence) if verdict != "probably_fine" else min(score, 1 - out.confidence), 3)
            if verdict_for(score) != verdict:
                score = {"likely_scam": 0.7, "be_careful": 0.45, "probably_fine": 0.15}[verdict]
            llm_reason = {"en": out.reason_en.strip()[:200], "ur": out.reason_ur.strip()[:200]}

    check = ScamCheck(
        user_id=user.id, verdict=verdict, score=score, reasons=flags, source=body.source, engine=engine,
        redacted_text=redacted if await has_consent(db, user.id, "scam_text_storage") else None,
    )
    db.add(check)
    await db.commit()
    return {
        "id": check.id,
        "verdict": verdict,
        "score": score,
        "reasons": flags,
        "engine": engine,
        "explanation": explain(verdict, flags, lang, llm_reason),
        "can_tell_family": True,
    }


@router.post("/scam/share/{check_id}")
async def share_with_family(check_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """'Tell my family' - sends the verdict (never the message) to linked caregivers."""
    check = (await db.execute(select(ScamCheck).where(ScamCheck.id == check_id, ScamCheck.user_id == user.id))).scalar_one_or_none()
    if check is None:
        raise HTTPException(404, "not_found")
    check.shared_with_family = True
    sent = await alert_scam_shared(db, user.id, check)
    await db.commit()
    return {"shared": True, "caregivers_notified": sent}


@router.get("/scam/history")
async def history(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(ScamCheck).where(ScamCheck.user_id == user.id).order_by(ScamCheck.created_at.desc()).limit(50))).scalars()
    return {"checks": [{"id": r.id, "verdict": r.verdict, "score": r.score, "reasons": r.reasons, "source": r.source,
                        "engine": r.engine, "shared": r.shared_with_family, "created_at": r.created_at.isoformat()} for r in rows]}
