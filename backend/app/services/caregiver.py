"""Caregiver summaries and alerts (F9). Only aggregate counts; never content."""
from __future__ import annotations

from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import Alert, CaregiverLink, Event, ScamCheck, User
from app.services.consent import has_consent
from app.services.i18n import both
from app.services.tasks import TASKS

DEFAULT_PERMISSIONS = {"activity": True, "scam": True, "alerts": True, "inactivity_days": None}


def _aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


async def active_links_for_parent(db: AsyncSession, parent_id: str) -> list[CaregiverLink]:
    return list(
        (
            await db.execute(
                select(CaregiverLink).where(
                    CaregiverLink.parent_id == parent_id,
                    CaregiverLink.status == "active",
                    CaregiverLink.caregiver_id.is_not(None),
                )
            )
        ).scalars()
    )


async def parent_summary(db: AsyncSession, parent: User, days: int = 7, permissions: dict | None = None) -> dict:
    perms = {**DEFAULT_PERMISSIONS, **(permissions or {})}
    now = datetime.now(timezone.utc)
    since = now - timedelta(days=days)
    events = (
        await db.execute(
            select(Event.event_type, Event.item_id, Event.properties, Event.created_at)
            .where(Event.user_id == parent.id, Event.created_at >= since)
            .order_by(Event.created_at)
        )
    ).all()
    last_active = (
        await db.execute(select(func.max(Event.created_at)).where(Event.user_id == parent.id))
    ).scalar_one_or_none()

    day_keys = [(now - timedelta(days=i)).date().isoformat() for i in range(days - 1, -1, -1)]
    tasks_per_day = {d: 0 for d in day_keys}
    struggles_per_day = {d: 0 for d in day_keys}
    friction: Counter = Counter()
    for etype, item_id, props, created in events:
        d = _aware(created).date().isoformat()
        props = props or {}
        if etype == "task_completed" and d in tasks_per_day:
            tasks_per_day[d] += 1
        elif etype == "struggle_detected":
            if d in struggles_per_day:
                struggles_per_day[d] += 1
            task = props.get("task") or item_id
            if task in TASKS:
                friction[task] += 1
        elif etype == "nav_aborted":
            task = props.get("task")
            if task in TASKS:
                friction[task] += 1

    out: dict = {
        "parent_id": parent.id,
        "display_name": parent.display_name,
        "last_active": _aware(last_active).isoformat() if last_active else None,
    }
    if perms.get("activity", True):
        out["tasks_completed_per_day"] = tasks_per_day
        out["struggle_episodes_per_day"] = struggles_per_day
        out["friction_tasks"] = [
            {"task": t, "count": c, "label": TASKS[t]["label"]} for t, c in friction.most_common(3)
        ]
    if perms.get("scam", True):
        checks = (
            await db.execute(
                select(ScamCheck.verdict, func.count()).where(
                    ScamCheck.user_id == parent.id, ScamCheck.created_at >= since
                ).group_by(ScamCheck.verdict)
            )
        ).all()
        verdicts = {"likely_scam": 0, "be_careful": 0, "probably_fine": 0}
        for v, c in checks:
            verdicts[v] = c
        out["scam_checks"] = {"total": sum(verdicts.values()), "verdicts": verdicts}
    return out


async def create_alert(db: AsyncSession, parent_id: str, caregiver_id: str, atype: str, payload: dict,
                       dedupe_key: str | None = None) -> Alert | None:
    if dedupe_key:
        exists = (
            await db.execute(
                select(Alert.id).where(Alert.caregiver_id == caregiver_id, Alert.dedupe_key == dedupe_key)
            )
        ).first()
        if exists:
            return None
    alert = Alert(parent_id=parent_id, caregiver_id=caregiver_id, type=atype, payload=payload, dedupe_key=dedupe_key)
    db.add(alert)
    return alert


async def _sharing_links(db: AsyncSession, parent_id: str, perm: str) -> list[CaregiverLink]:
    if not await has_consent(db, parent_id, "caregiver_sharing"):
        return []
    links = await active_links_for_parent(db, parent_id)
    return [l for l in links if {**DEFAULT_PERMISSIONS, **(l.permissions or {})}.get(perm, True)]


async def check_repeated_struggle(db: AsyncSession, parent_id: str, task: str | None) -> int:
    """Alert when the same task causes struggle >= N times in 24h (one alert per task per day)."""
    if not task or task not in TASKS:
        return 0
    s = get_settings()
    since = datetime.now(timezone.utc) - timedelta(hours=24)
    rows = (
        await db.execute(
            select(Event.item_id, Event.properties).where(
                Event.user_id == parent_id, Event.event_type == "struggle_detected", Event.created_at >= since
            )
        )
    ).all()
    count = sum(1 for item, props in rows if (props or {}).get("task", item) == task)
    if count < s.repeated_struggle_alert_count:
        return 0
    created = 0
    today = datetime.now(timezone.utc).date().isoformat()
    for link in await _sharing_links(db, parent_id, "alerts"):
        a = await create_alert(
            db, parent_id, link.caregiver_id, "repeated_struggle",
            {"task": task, "count": count, "message": {
                "en": both("alert.repeated_struggle", task=TASKS[task]["label"]["en"])["en"],
                "ur": both("alert.repeated_struggle", task=TASKS[task]["label"]["ur"])["ur"],
            }},
            dedupe_key=f"struggle:{task}:{today}",
        )
        created += a is not None
    return created


async def alert_scam_shared(db: AsyncSession, parent_id: str, check: ScamCheck) -> int:
    created = 0
    for link in await _sharing_links(db, parent_id, "scam"):
        if check.verdict == "likely_scam":
            msg = both("alert.scam_shared")
        else:
            label = both(f"verdict.{check.verdict}")
            msg = {"en": both("alert.scam_shared_generic", verdict=label["en"])["en"],
                   "ur": both("alert.scam_shared_generic", verdict=label["ur"])["ur"]}
        a = await create_alert(
            db, parent_id, link.caregiver_id, "scam_shared",
            {"check_id": check.id, "verdict": check.verdict, "reasons": check.reasons, "message": msg},
            dedupe_key=f"scam:{check.id}",
        )
        created += a is not None
    return created


async def run_inactivity_alerts(db: AsyncSession) -> int:
    s = get_settings()
    now = datetime.now(timezone.utc)
    links = (await db.execute(select(CaregiverLink).where(CaregiverLink.status == "active"))).scalars().all()
    by_parent: dict[str, list[CaregiverLink]] = defaultdict(list)
    for l in links:
        by_parent[l.parent_id].append(l)
    created = 0
    for parent_id, plinks in by_parent.items():
        if not await has_consent(db, parent_id, "caregiver_sharing"):
            continue
        last = (await db.execute(select(func.max(Event.created_at)).where(Event.user_id == parent_id))).scalar_one_or_none()
        if last is None:
            continue
        idle_days = (now - _aware(last)).days
        for l in plinks:
            perms = {**DEFAULT_PERMISSIONS, **(l.permissions or {})}
            limit = perms.get("inactivity_days") or s.inactivity_days_default
            if perms.get("alerts", True) and idle_days >= limit:
                a = await create_alert(
                    db, parent_id, l.caregiver_id, "inactivity",
                    {"days": idle_days, "message": both("alert.inactivity", days=idle_days)},
                    dedupe_key=f"inactive:{parent_id}:{now.date().isoformat()}",
                )
                created += a is not None
    await db.commit()
    return created
