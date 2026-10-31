"""Seed clearly-labelled DEMO data (PRD F3 / §12: "seeded demo data, clearly disclosed").

Creates:
  * parent  (auth_id "demo-parent",    token "dev:demo-parent")    Urdu, consented, 30 days of routine
  * caregiver (auth_id "demo-caregiver", token "dev:demo-caregiver") linked + active
Usage:
  python -m scripts.seed_demo            # uses DATABASE_URL
  python -m scripts.seed_demo --reset    # deletes the demo users first
"""
from __future__ import annotations

import argparse
import asyncio
import random
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select

from app.core.db import Base, SessionLocal, engine
from app.models import Alert, CaregiverLink, Consent, Event, GuideCard, ScamCheck, User

# Daily routine: (hour, [task sequence], probability)
ROUTINE = [
    (8, ["photos", "call"], 0.85),
    (13, ["messages", "whatsapp"], 0.75),
    (19, ["whatsapp", "call"], 0.75),
    (21, ["call"], 0.5),
]
NOISE_TASKS = ["camera", "scam_check", "messages", "photos", "ask_family", "maps"]


def generate_routine(days: int = 30, seed: int = 7, start: datetime | None = None) -> list[tuple[datetime, str]]:
    """Deterministic list of (timestamp, task) completions."""
    rng = random.Random(seed)
    start = start or (datetime.now(timezone.utc) - timedelta(days=days)).replace(hour=0, minute=0, second=0, microsecond=0)
    out: list[tuple[datetime, str]] = []
    for d in range(days):
        day = start + timedelta(days=d)
        for hour, seq, prob in ROUTINE:
            if rng.random() > prob:
                continue
            t = day.replace(hour=hour, minute=rng.randint(0, 40))
            for task in seq:
                out.append((t, task))
                t += timedelta(minutes=rng.randint(2, 12))
        if rng.random() < 0.6:  # noise
            t = day.replace(hour=rng.randint(9, 22), minute=rng.randint(0, 59))
            out.append((t, rng.choice(NOISE_TASKS)))
    out.sort()
    return out


async def seed(reset: bool = False) -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with SessionLocal() as db:
        if reset:
            ids = [u.id for u in (await db.execute(select(User).where(User.auth_id.in_(["demo-parent", "demo-caregiver"])))).scalars()]
            for model in (Event, ScamCheck, Consent):
                await db.execute(delete(model).where(model.user_id.in_(ids)))
            for model in (Alert, GuideCard, CaregiverLink):
                await db.execute(delete(model).where(model.parent_id.in_(ids)))
            await db.execute(delete(User).where(User.id.in_(ids)))
            await db.commit()

        parent = User(auth_id="demo-parent", role="parent", language="ur", display_name="امی (Demo)",
                      email="demo-parent@example.com")
        caregiver = User(auth_id="demo-caregiver", role="caregiver", language="en", display_name="Ali (Demo)",
                         email="demo-caregiver@example.com")
        db.add_all([parent, caregiver])
        await db.flush()
        for ctype in ("activity_tracking", "caregiver_sharing", "ai_disclosure"):
            db.add(Consent(user_id=parent.id, type=ctype, granted=True))
        db.add(Consent(user_id=parent.id, type="scam_text_storage", granted=False))
        db.add(Consent(user_id=caregiver.id, type="ai_disclosure", granted=True))
        now = datetime.now(timezone.utc)
        db.add(CaregiverLink(parent_id=parent.id, caregiver_id=caregiver.id, invite_email=caregiver.email,
                             status="active", invite_code=None, invite_expires_at=now, accepted_at=now,
                             permissions={"activity": True, "scam": True, "alerts": True}))
        for ts, task in generate_routine():
            db.add(Event(user_id=parent.id, event_type="task_completed", item_id=task, session_id="demo-seed",
                         properties={"task": task, "hour": ts.hour, "source": "demo_seed"}, created_at=ts))
        for i in range(4):
            db.add(Event(user_id=parent.id, event_type="struggle_detected", item_id="whatsapp", session_id="demo-seed",
                         properties={"task": "whatsapp", "score": 1.2, "signals": ["backtracking", "idle"]},
                         created_at=now - timedelta(days=i % 3, hours=i)))
        db.add(ScamCheck(user_id=parent.id, verdict="likely_scam", score=0.9, reasons=["otp_request", "urgency_threat"],
                         source="paste", engine="rules"))
        await db.commit()
    print("Seeded demo users. Tokens (AUTH_MODE=dev): 'dev:demo-parent' and 'dev:demo-caregiver'")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--reset", action="store_true")
    asyncio.run(seed(reset=ap.parse_args().reset))
