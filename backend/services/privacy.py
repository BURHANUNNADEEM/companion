"""Consent lookups, event sanitising and delete-my-data."""

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from core.errors import AppError
from models import Consent, Event, ScamCheck, TaskAttempt, TaskProgress, User

# Keys that could carry personal content are dropped from event properties.
BLOCKED_PROP_KEYS = {
    "text", "message", "body", "content", "name", "contact", "contact_name", "phone", "number",
    "email", "address", "transcript", "screenshot", "otp", "pin", "password",
}


def sanitize_props(props: dict) -> dict:
    clean = {}
    for k, v in (props or {}).items():
        if k.lower() in BLOCKED_PROP_KEYS:
            continue
        if isinstance(v, str) and len(v) > 200:
            v = v[:200]
        clean[k] = v
    return clean


async def get_consent(db: AsyncSession, user_id: int) -> Consent | None:
    return (await db.execute(select(Consent).where(Consent.user_id == user_id))).scalar_one_or_none()


async def require_tracking(db: AsyncSession, user_id: int) -> None:
    c = await get_consent(db, user_id)
    if c is None or not c.tracking:
        raise AppError(403, "consent_required", "Activity tracking consent has not been given",
                       {"how_to_fix": "PUT /api/consent with {\"tracking\": true}"})


async def delete_all(db: AsyncSession, user: User) -> dict:
    uid = user.id
    counts = {}
    for name, model in (("events", Event), ("scam_checks", ScamCheck), ("task_attempts", TaskAttempt),
                        ("task_progress", TaskProgress), ("consents", Consent)):
        res = await db.execute(delete(model).where(model.user_id == uid))
        counts[name] = res.rowcount or 0
    await db.execute(delete(User).where(User.id == uid))
    counts["users"] = 1
    await db.commit()
    return counts
