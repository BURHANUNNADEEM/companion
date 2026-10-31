"""/api/me - profile, role, language, delete-my-data (F5)."""
from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_current_user, require_role
from app.core.db import get_db
from app.models import Alert, CaregiverLink, Consent, Event, GuideCard, ScamCheck, User
from app.services.caregiver import parent_summary
from app.services.consent import current_consents

router = APIRouter(tags=["me"])


class RoleIn(BaseModel):
    role: Literal["parent", "caregiver"]


class LanguageIn(BaseModel):
    language: Literal["ur", "en"]


class ProfileIn(BaseModel):
    display_name: str | None = Field(default=None, max_length=60)


async def user_view(db: AsyncSession, user: User) -> dict:
    return {
        "id": user.id,
        "role": user.role,
        "language": user.language,
        "display_name": user.display_name,
        "email": user.email,
        "created_at": user.created_at.isoformat() if user.created_at else None,
        "consent": await current_consents(db, user.id),
    }


@router.get("/me")
async def get_me(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await user_view(db, user)


@router.put("/me/role")
async def set_role(body: RoleIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    # Chosen once; changing role means deleting and recreating the account (PRD F5).
    if user.role and user.role != body.role:
        raise HTTPException(409, "role_already_set")
    user.role = body.role
    await db.commit()
    return await user_view(db, user)


@router.put("/me/language")
async def set_language(body: LanguageIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    user.language = body.language
    await db.commit()
    return await user_view(db, user)


@router.put("/me/profile")
async def set_profile(body: ProfileIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    user.display_name = (body.display_name or "").strip() or None
    await db.commit()
    return await user_view(db, user)


@router.get("/me/sharing-preview")
async def sharing_preview(user: User = Depends(require_role("parent")), db: AsyncSession = Depends(get_db)):
    """The parent sees exactly what a linked caregiver would see (PRD §12 mitigation)."""
    consents = await current_consents(db, user.id)
    if not consents["caregiver_sharing"]:
        return {"sharing": False, "summary": None}
    return {"sharing": True, "summary": await parent_summary(db, user)}


@router.delete("/me/data")
async def delete_my_data(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Remove events, consents, scam history, links, alerts, guide cards and the account itself."""
    uid = user.id
    await db.execute(delete(Event).where(Event.user_id == uid))
    await db.execute(delete(ScamCheck).where(ScamCheck.user_id == uid))
    await db.execute(delete(Consent).where(Consent.user_id == uid))
    await db.execute(delete(Alert).where(or_(Alert.parent_id == uid, Alert.caregiver_id == uid)))
    await db.execute(delete(GuideCard).where(or_(GuideCard.parent_id == uid, GuideCard.caregiver_id == uid)))
    await db.execute(delete(CaregiverLink).where(or_(CaregiverLink.parent_id == uid, CaregiverLink.caregiver_id == uid)))
    await db.execute(delete(User).where(User.id == uid))
    await db.commit()
    return {"deleted": True}
