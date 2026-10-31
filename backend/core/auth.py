from typing import Annotated

from clerk_backend_api import AuthenticateRequestOptions, authenticate_request
from clerk_backend_api.security.types import RequestState
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import Settings, get_settings
from core.db import get_db
from models import User

http_bearer = HTTPBearer(auto_error=False)  # gives Swagger an "Authorize" button


def require_auth(
    request: Request,
    settings: Annotated[Settings, Depends(get_settings)],
    _creds: Annotated[object, Depends(http_bearer)] = None,
) -> RequestState:
    parties = [p.strip() for p in settings.clerk_authorized_parties.split(",") if p.strip()]
    state = authenticate_request(
        request,
        AuthenticateRequestOptions(
            secret_key=settings.clerk_secret_key,
            jwt_key=settings.clerk_jwt_key or None,
            authorized_parties=parties or None,
            accepts_token=["session_token"],
        ),
    )
    if not state.is_signed_in:
        raise HTTPException(
            status_code=401,
            detail=state.reason.name if state.reason else "unauthorized",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return state


async def get_current_user(
    state: Annotated[RequestState, Depends(require_auth)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    clerk_id = state.payload["sub"]
    user = (await db.execute(select(User).where(User.clerk_id == clerk_id))).scalar_one_or_none()
    if user is None:
        user = User(clerk_id=clerk_id)
        db.add(user)
        await db.commit()
        await db.refresh(user)
    return user