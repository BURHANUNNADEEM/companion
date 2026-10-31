"""/api/consent (F5)."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_current_user
from app.core.db import get_db
from app.models import Consent, User
from app.services.consent import current_consents

router = APIRouter(tags=["consent"])

CONSENT_TEXT = {
    "activity_tracking": {
        "en": "Companion notes which buttons you use (never what you write) so it can offer help when you seem stuck.",
        "ur": "کمپینین یہ نوٹ کرتا ہے کہ آپ کون سے بٹن استعمال کرتے ہیں (کبھی یہ نہیں کہ آپ کیا لکھتے ہیں) تاکہ مشکل کے وقت مدد پیش کر سکے۔",
    },
    "caregiver_sharing": {
        "en": "Share a simple summary (activity counts, struggles, scam-check results) with family you invite. Never messages or contacts.",
        "ur": "جن گھر والوں کو آپ دعوت دیں ان کے ساتھ سادہ خلاصہ (سرگرمی کی گنتی، مشکلات، پیغام کی جانچ کے نتائج) شیئر کریں۔ کبھی پیغامات یا رابطے نہیں۔",
    },
    "scam_text_storage": {
        "en": "Keep a copy of checked messages (with personal details removed). If off, we keep only the result.",
        "ur": "چیک کیے گئے پیغامات کی کاپی رکھیں (ذاتی تفصیلات ہٹا کر)۔ بند ہو تو ہم صرف نتیجہ رکھتے ہیں۔",
    },
    "ai_disclosure": {
        "en": "To check messages and understand your voice, text with personal details removed may be sent to Google's Gemini AI. On the free tier Google may use it to improve its products, so this test version uses only sample or consenting testers' messages.",
        "ur": "پیغامات چیک کرنے اور آپ کی آواز سمجھنے کے لیے، ذاتی تفصیلات ہٹا کر متن گوگل کے Gemini AI کو بھیجا جا سکتا ہے۔ مفت ورژن میں گوگل اسے اپنی سروسز بہتر بنانے کے لیے استعمال کر سکتا ہے، اس لیے یہ آزمائشی ورژن صرف نمونہ یا رضامند افراد کے پیغامات استعمال کرتا ہے۔",
    },
}


class ConsentIn(BaseModel):
    activity_tracking: bool | None = None
    caregiver_sharing: bool | None = None
    scam_text_storage: bool | None = None
    ai_disclosure: bool | None = None


@router.get("/consent")
async def get_consent(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return {"consent": await current_consents(db, user.id), "text": CONSENT_TEXT}


@router.put("/consent")
async def put_consent(body: ConsentIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    current = await current_consents(db, user.id)
    for ctype, value in body.model_dump(exclude_none=True).items():
        if not current["completed"] or current.get(ctype) != value:
            db.add(Consent(user_id=user.id, type=ctype, granted=value))
    await db.commit()
    return {"consent": await current_consents(db, user.id)}
