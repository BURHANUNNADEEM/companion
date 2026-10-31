from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from core.auth import get_current_user
from core.db import get_db
from models import User
from schemas.api import DeleteConfirm, ProfileUpdate
from services import privacy

router = APIRouter(prefix="/api", tags=["me"])

CurrentUser = Annotated[User, Depends(get_current_user)]
DB = Annotated[AsyncSession, Depends(get_db)]


def _profile(u: User) -> dict:
    return {
        "id": u.id,
        "firebase_uid": u.firebase_uid,
        "display_name": u.display_name,
        "language": u.language or "ur",
        "created_at": u.created_at.isoformat() if u.created_at else None,
    }


@router.get("/me")
async def me(user: CurrentUser, db: DB):
    c = await privacy.get_consent(db, user.id)
    return {**_profile(user), "consent_given": bool(c and c.tracking)}


@router.patch("/me")
async def update_me(body: ProfileUpdate, user: CurrentUser, db: DB):
    if body.display_name is not None:
        user.display_name = body.display_name.strip() or None
    if body.language is not None:
        user.language = body.language
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return _profile(user)


@router.delete("/me/data")
async def delete_my_data(body: DeleteConfirm, user: CurrentUser, db: DB):
    """Deletes events, scam checks, task attempts/progress, consent and the user row."""
    counts = await privacy.delete_all(db, user)
    return {"deleted": True, "rows_deleted": counts}
