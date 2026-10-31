from typing import Annotated

import firebase_admin
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth as fb_auth
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import Settings, get_settings
from core.db import get_db
from models import User

http_bearer = HTTPBearer(auto_error=False)  # gives Swagger an "Authorize" button


def _init_firebase(project_id: str) -> None:
    if not firebase_admin._apps:
        # Verifying ID tokens only needs the project ID (no service account key).
        firebase_admin.initialize_app(options={"projectId": project_id})


# plain `def` -> FastAPI runs it in a threadpool, so the sync verify doesn't block the loop
def require_auth(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(http_bearer)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict:
    if creds is None:
        raise HTTPException(401, "missing token", headers={"WWW-Authenticate": "Bearer"})
    # Local testing only (DEV_AUTH_ENABLED=true): "Bearer dev-alice" -> uid "dev-alice"
    if settings.dev_auth_enabled and creds.credentials.startswith("dev-"):
        return {"uid": creds.credentials}
    _init_firebase(settings.firebase_project_id)
    try:
        return fb_auth.verify_id_token(creds.credentials)
    except Exception:
        raise HTTPException(401, "invalid or expired token", headers={"WWW-Authenticate": "Bearer"})


async def get_current_user(
    claims: Annotated[dict, Depends(require_auth)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    uid = claims["uid"]  # same as claims["sub"]
    user = (await db.execute(select(User).where(User.firebase_uid == uid))).scalar_one_or_none()
    if user is None:
        user = User(firebase_uid=uid)
        db.add(user)
        await db.commit()
        await db.refresh(user)
    return user