"""/api/caregiver - invites, links, summary, alerts, guide cards (F9)."""
from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException
import re

from pydantic import BaseModel, Field, field_validator
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_current_user, require_role
from app.core.config import get_settings
from app.core.db import get_db
from app.models import Alert, CaregiverLink, GuideCard, User
from app.services.caregiver import DEFAULT_PERMISSIONS, parent_summary, run_inactivity_alerts
from app.services.consent import has_consent
from app.services.email import send_email
from app.services.flow_engine import workflows_by_id
from app.services.i18n import MESSAGES

router = APIRouter(tags=["caregiver"])

_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I confusion


def _aware(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def link_view(l: CaregiverLink, users: dict[str, User] | None = None) -> dict:
    users = users or {}
    p, c = users.get(l.parent_id), users.get(l.caregiver_id or "")
    return {
        "id": l.id,
        "status": l.status,
        "parent_id": l.parent_id,
        "parent_name": p.display_name if p else None,
        "caregiver_id": l.caregiver_id,
        "caregiver_name": c.display_name if c else None,
        "invite_email": l.invite_email,
        "accepted": l.accepted_at is not None,
        "awaiting_parent_approval": l.status == "pending" and l.accepted_at is not None,
        "invite_expires_at": _aware(l.invite_expires_at).isoformat(),
        "permissions": {**DEFAULT_PERMISSIONS, **(l.permissions or {})},
    }


_EMAIL = re.compile(r"^[^@\s]{1,64}@[^@\s]+\.[A-Za-z]{2,}$")


class InviteIn(BaseModel):
    email: str = Field(max_length=320)
    permissions: dict | None = None

    @field_validator("email")
    @classmethod
    def _valid_email(cls, v: str) -> str:
        v = v.strip().lower()
        if not _EMAIL.match(v):
            raise ValueError("invalid_email")
        return v


class AcceptIn(BaseModel):
    code: str = Field(min_length=6, max_length=16)


class GuideCardIn(BaseModel):
    parent_id: str = Field(max_length=32)
    text: str = Field(min_length=1, max_length=280)
    workflow_id: str | None = Field(default=None, max_length=64)


@router.post("/caregiver/invite")
async def invite(body: InviteIn, user: User = Depends(require_role("parent")), db: AsyncSession = Depends(get_db)):
    s = get_settings()
    code = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(8))
    perms = {**DEFAULT_PERMISSIONS, **{k: v for k, v in (body.permissions or {}).items() if k in DEFAULT_PERMISSIONS}}
    link = CaregiverLink(
        parent_id=user.id, invite_email=str(body.email).lower(), invite_code=code, status="pending",
        invite_expires_at=datetime.now(timezone.utc) + timedelta(hours=s.invite_ttl_hours), permissions=perms,
    )
    db.add(link)
    await db.commit()
    lang = user.language if user.language in ("ur", "en") else "ur"
    name = user.display_name or ("Your family member" if lang == "en" else "آپ کے گھر کے فرد")
    # Bilingual e-mail: user's language first, then the other.
    order = [lang, "en" if lang == "ur" else "ur"]
    subject = " / ".join(MESSAGES["email.invite.subject"][l] for l in order)
    body_text = "\n\n----------\n\n".join(
        MESSAGES["email.invite.body"][l].format(name=name, code=code, url=s.app_invite_url, hours=s.invite_ttl_hours)
        for l in order
    )
    sent = await send_email(link.invite_email, subject, body_text)
    out = {"link": link_view(link), "email_sent": sent}
    if s.email_backend == "console" and s.env != "production":
        out["dev_invite_code"] = code  # demo convenience only
    return out


@router.post("/caregiver/accept")
async def accept(body: AcceptIn, user: User = Depends(require_role("caregiver")), db: AsyncSession = Depends(get_db)):
    code = body.code.strip().upper()
    link = (await db.execute(select(CaregiverLink).where(CaregiverLink.invite_code == code))).scalar_one_or_none()
    if link is None or link.status != "pending" or link.accepted_at is not None:
        raise HTTPException(404, "invalid_code")
    if _aware(link.invite_expires_at) < datetime.now(timezone.utc):
        raise HTTPException(410, "code_expired")
    if link.parent_id == user.id:
        raise HTTPException(400, "cannot_link_self")
    if user.email and link.invite_email and user.email.lower() != link.invite_email.lower():
        raise HTTPException(403, "email_mismatch")
    link.caregiver_id = user.id
    link.accepted_at = datetime.now(timezone.utc)
    link.invite_code = None  # one-time
    await db.commit()
    return {"link": link_view(link), "next": "waiting_for_parent_approval"}


@router.post("/caregiver/approve/{link_id}")
async def approve(link_id: str, user: User = Depends(require_role("parent")), db: AsyncSession = Depends(get_db)):
    link = (await db.execute(select(CaregiverLink).where(CaregiverLink.id == link_id, CaregiverLink.parent_id == user.id))).scalar_one_or_none()
    if link is None:
        raise HTTPException(404, "not_found")
    if link.status != "pending" or link.caregiver_id is None:
        raise HTTPException(409, "not_awaiting_approval")
    link.status = "active"
    await db.commit()
    return {"link": link_view(link)}


@router.delete("/caregiver/link/{link_id}")
async def revoke(link_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    link = (
        await db.execute(
            select(CaregiverLink).where(
                CaregiverLink.id == link_id,
                or_(CaregiverLink.parent_id == user.id, CaregiverLink.caregiver_id == user.id),
            )
        )
    ).scalar_one_or_none()
    if link is None:
        raise HTTPException(404, "not_found")
    link.status = "revoked"
    link.invite_code = None
    await db.commit()
    return {"link": link_view(link)}


@router.get("/caregiver/links")
async def links(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    rows = (
        await db.execute(
            select(CaregiverLink).where(
                or_(CaregiverLink.parent_id == user.id, CaregiverLink.caregiver_id == user.id),
                CaregiverLink.status != "revoked",
            ).order_by(CaregiverLink.created_at.desc())
        )
    ).scalars().all()
    ids = {r.parent_id for r in rows} | {r.caregiver_id for r in rows if r.caregiver_id}
    users = {u.id: u for u in (await db.execute(select(User).where(User.id.in_(ids)))).scalars()} if ids else {}
    return {"links": [link_view(r, users) for r in rows]}


async def _active_parent_link(db: AsyncSession, caregiver_id: str, parent_id: str) -> CaregiverLink | None:
    return (
        await db.execute(
            select(CaregiverLink).where(
                CaregiverLink.caregiver_id == caregiver_id, CaregiverLink.parent_id == parent_id,
                CaregiverLink.status == "active",
            )
        )
    ).scalar_one_or_none()


@router.get("/caregiver/summary")
async def summary(user: User = Depends(require_role("caregiver")), db: AsyncSession = Depends(get_db)):
    """Aggregated stats for linked parents. With sharing off, the caregiver sees nothing."""
    rows = (
        await db.execute(
            select(CaregiverLink).where(CaregiverLink.caregiver_id == user.id, CaregiverLink.status == "active")
        )
    ).scalars().all()
    parents = []
    for link in rows:
        if not await has_consent(db, link.parent_id, "caregiver_sharing"):
            continue
        parent = await db.get(User, link.parent_id)
        if parent is None:
            continue
        s = await parent_summary(db, parent, permissions=link.permissions)
        s["link_id"] = link.id
        parents.append(s)
    return {"parents": parents}


@router.get("/caregiver/alerts")
async def alerts(user: User = Depends(require_role("caregiver")), db: AsyncSession = Depends(get_db)):
    active_parents = {
        l.parent_id for l in (await db.execute(
            select(CaregiverLink).where(CaregiverLink.caregiver_id == user.id, CaregiverLink.status == "active")
        )).scalars()
    }
    if not active_parents:
        return {"alerts": [], "unseen": 0}
    shared = {p for p in active_parents if await has_consent(db, p, "caregiver_sharing")}
    rows = (
        await db.execute(
            select(Alert).where(Alert.caregiver_id == user.id, Alert.parent_id.in_(shared)).order_by(Alert.created_at.desc()).limit(100)
        )
    ).scalars().all() if shared else []
    return {
        "alerts": [{"id": a.id, "type": a.type, "parent_id": a.parent_id, "payload": a.payload,
                    "created_at": _aware(a.created_at).isoformat(), "seen": a.seen_at is not None} for a in rows],
        "unseen": sum(1 for a in rows if a.seen_at is None),
    }


@router.post("/caregiver/alerts/{alert_id}/seen")
async def alert_seen(alert_id: str, user: User = Depends(require_role("caregiver")), db: AsyncSession = Depends(get_db)):
    a = (await db.execute(select(Alert).where(Alert.id == alert_id, Alert.caregiver_id == user.id))).scalar_one_or_none()
    if a is None:
        raise HTTPException(404, "not_found")
    a.seen_at = datetime.now(timezone.utc)
    await db.commit()
    return {"ok": True}


@router.post("/caregiver/guide-cards")
async def send_guide_card(body: GuideCardIn, user: User = Depends(require_role("caregiver")), db: AsyncSession = Depends(get_db)):
    if await _active_parent_link(db, user.id, body.parent_id) is None:
        raise HTTPException(403, "not_linked")
    if body.workflow_id and body.workflow_id not in workflows_by_id():
        raise HTTPException(422, "unknown_workflow")
    card = GuideCard(parent_id=body.parent_id, caregiver_id=user.id, text=body.text.strip(), workflow_id=body.workflow_id)
    db.add(card)
    await db.commit()
    return {"id": card.id}


@router.get("/guide-cards")
async def my_guide_cards(user: User = Depends(require_role("parent")), db: AsyncSession = Depends(get_db)):
    active_caregivers = {
        l.caregiver_id for l in (await db.execute(
            select(CaregiverLink).where(CaregiverLink.parent_id == user.id, CaregiverLink.status == "active")
        )).scalars()
    }
    rows = (await db.execute(
        select(GuideCard).where(GuideCard.parent_id == user.id, GuideCard.seen_at.is_(None)).order_by(GuideCard.created_at.desc())
    )).scalars().all()
    rows = [r for r in rows if r.caregiver_id in active_caregivers]
    names = {u.id: u.display_name for u in (await db.execute(select(User).where(User.id.in_(active_caregivers)))).scalars()} if active_caregivers else {}
    return {"cards": [{"id": c.id, "text": c.text, "workflow_id": c.workflow_id, "from": names.get(c.caregiver_id),
                       "created_at": _aware(c.created_at).isoformat()} for c in rows]}


@router.post("/guide-cards/{card_id}/seen")
async def guide_card_seen(card_id: str, user: User = Depends(require_role("parent")), db: AsyncSession = Depends(get_db)):
    c = (await db.execute(select(GuideCard).where(GuideCard.id == card_id, GuideCard.parent_id == user.id))).scalar_one_or_none()
    if c is None:
        raise HTTPException(404, "not_found")
    c.seen_at = datetime.now(timezone.utc)
    await db.commit()
    return {"ok": True}


@router.post("/alerts/inactivity/run", tags=["admin"])
async def inactivity_job(x_admin_token: str = Header(default=""), db: AsyncSession = Depends(get_db)):
    """Call from a scheduler (e.g. cron / GitHub Actions) once a day."""
    if not secrets.compare_digest(x_admin_token, get_settings().admin_token):
        raise HTTPException(403, "forbidden")
    return {"created": await run_inactivity_alerts(db)}
