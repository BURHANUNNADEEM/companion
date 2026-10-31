"""Consent helpers (F5). Consents are append-only rows; the latest row per type wins."""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Consent

CONSENT_TYPES = ("activity_tracking", "caregiver_sharing", "scam_text_storage", "ai_disclosure")
DEFAULTS = {t: False for t in CONSENT_TYPES}


async def current_consents(db: AsyncSession, user_id: str) -> dict[str, bool]:
    rows = (
        await db.execute(
            select(Consent).where(Consent.user_id == user_id).order_by(Consent.timestamp, Consent.id)
        )
    ).scalars().all()
    state = dict(DEFAULTS)
    for r in rows:
        state[r.type] = r.granted
    state["completed"] = bool(rows)
    return state


async def has_consent(db: AsyncSession, user_id: str, ctype: str) -> bool:
    row = (
        await db.execute(
            select(Consent)
            .where(Consent.user_id == user_id, Consent.type == ctype)
            .order_by(Consent.timestamp.desc(), Consent.id.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    return bool(row and row.granted)
