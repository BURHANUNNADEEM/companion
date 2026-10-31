"""Firebase ID token verification -> uid -> user (+ role).

Per PRD §7 "Auth migration note": only this module knows about the identity provider.
`get_current_user` stays the single dependency used by every router.

AUTH_MODE=dev (only allowed when ENV != production) accepts tokens of the form
`dev:<uid>` or `dev:<uid>:<email>` so the stack can be demoed/tested without Firebase.
"""
from __future__ import annotations

import base64
import json
import logging
import os
from dataclasses import dataclass

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import get_db
from app.models import User

log = logging.getLogger(__name__)
bearer = HTTPBearer(auto_error=False)


@dataclass
class Identity:
    uid: str
    email: str | None = None


_firebase_app = None


def _init_firebase():
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app
    import firebase_admin  # lazy: not needed in dev/test
    from firebase_admin import credentials

    settings = get_settings()
    raw = settings.firebase_credentials.strip()
    cred = None
    if raw:
        if os.path.isfile(raw):
            cred = credentials.Certificate(raw)
        else:
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                data = json.loads(base64.b64decode(raw).decode("utf-8"))
            cred = credentials.Certificate(data)
    options = {"projectId": settings.firebase_project_id} if settings.firebase_project_id else None
    _firebase_app = firebase_admin.initialize_app(cred, options) if cred else firebase_admin.initialize_app(options=options)
    return _firebase_app


def verify_token(token: str) -> Identity:
    settings = get_settings()
    if settings.auth_mode == "dev":
        if not token.startswith("dev:"):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid_token")
        parts = token.split(":", 2)
        uid = parts[1].strip()
        if not uid or len(uid) > 128:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid_token")
        email = parts[2].strip().lower() if len(parts) > 2 and parts[2].strip() else None
        return Identity(uid=uid, email=email)

    from firebase_admin import auth as fb_auth

    _init_firebase()
    try:
        decoded = fb_auth.verify_id_token(token, check_revoked=False)
    except Exception as exc:  # noqa: BLE001 - firebase raises many types
        log.info("firebase token rejected: %s", type(exc).__name__)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid_token") from exc
    email = decoded.get("email")
    return Identity(uid=decoded["uid"], email=email.lower() if email else None)


async def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    if creds is None or creds.scheme.lower() != "bearer":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "missing_token")
    ident = verify_token(creds.credentials)
    user = (await db.execute(select(User).where(User.auth_id == ident.uid))).scalar_one_or_none()
    if user is None:
        user = User(auth_id=ident.uid, email=ident.email)
        db.add(user)
        try:
            await db.commit()
        except IntegrityError:  # concurrent first request
            await db.rollback()
            user = (await db.execute(select(User).where(User.auth_id == ident.uid))).scalar_one()
        await db.refresh(user)
    elif ident.email and user.email != ident.email:
        user.email = ident.email
        await db.commit()
    return user


def require_role(role: str):
    async def _dep(user: User = Depends(get_current_user)) -> User:
        if user.role != role:
            raise HTTPException(status.HTTP_403_FORBIDDEN, f"{role}_role_required")
        return user

    return _dep
