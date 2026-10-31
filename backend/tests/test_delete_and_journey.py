import os
import subprocess
import sys
import tempfile
from pathlib import Path

from sqlalchemy import func, select

from app.core.db import Base, SessionLocal
from app.models import Alert, CaregiverLink, Consent, Event, GuideCard, ScamCheck, User
from tests.conftest import H
from tests.test_caregiver import link_pair

BACKEND = Path(__file__).resolve().parents[1]


async def _rows_for(user_id: str) -> dict:
    async with SessionLocal() as db:
        out = {}
        for model, cols in [(User, ["id"]), (Consent, ["user_id"]), (Event, ["user_id"]), (ScamCheck, ["user_id"]),
                            (Alert, ["parent_id", "caregiver_id"]), (GuideCard, ["parent_id", "caregiver_id"]),
                            (CaregiverLink, ["parent_id", "caregiver_id"])]:
            n = 0
            for c in cols:
                n += (await db.execute(select(func.count()).select_from(model).where(getattr(model, c) == user_id))).scalar_one()
            out[model.__tablename__] = n
        return out


async def test_delete_my_data_leaves_no_rows(client):
    hp, hc, _ = await link_pair(client)
    parent_id = (await client.get("/api/me", headers=hp)).json()["id"]
    await client.post("/api/events", headers=hp, json={"session_id": "s", "events": [
        {"type": "struggle_detected", "item_id": "call", "properties": {"task": "call"}}] * 3})
    check = (await client.post("/api/scam/check", headers=hp, json={"text": "send OTP now"})).json()
    await client.post(f"/api/scam/share/{check['id']}", headers=hp)
    await client.post("/api/caregiver/guide-cards", headers=hc, json={"parent_id": parent_id, "text": "hello"})
    before = await _rows_for(parent_id)
    assert all(before[t] > 0 for t in before), before
    assert (await client.delete("/api/me/data", headers=hp)).json() == {"deleted": True}
    after = await _rows_for(parent_id)
    assert all(v == 0 for v in after.values()), after
    # caregiver no longer sees anything
    assert (await client.get("/api/caregiver/summary", headers=hc)).json()["parents"] == []


async def test_full_demo_journey(client):
    """PRD §11 demo flow, end to end through the API."""
    # 1. Parent signs in, picks a role, chooses Urdu, consents
    hp = H("ammi", "ammi@example.com")
    me = (await client.get("/api/me", headers=hp)).json()
    assert me["role"] is None
    await client.put("/api/me/role", json={"role": "parent"}, headers=hp)
    await client.put("/api/me/language", json={"language": "ur"}, headers=hp)
    await client.put("/api/me/profile", json={"display_name": "امی"}, headers=hp)
    await client.put("/api/consent", headers=hp, json={"activity_tracking": True, "caregiver_sharing": True,
                                                         "scam_text_storage": False, "ai_disclosure": True})
    cfg = (await client.get("/api/config")).json()
    assert cfg["struggle"]["threshold"] > 0 and len(cfg["home_tiles"]) == 6

    # 2. Caregiver links via e-mailed invite, parent approves
    hc = H("ali", "ali@example.com")
    await client.put("/api/me/role", json={"role": "caregiver"}, headers=hc)
    inv = (await client.post("/api/caregiver/invite", json={"email": "ali@example.com"}, headers=hp)).json()
    await client.post("/api/caregiver/accept", json={"code": inv["dev_invite_code"]}, headers=hc)
    await client.post(f"/api/caregiver/approve/{inv['link']['id']}", headers=hp)

    # 3. Parent wanders between screens; on-device detector fires; app asks for suggestions
    wander = [{"type": "screen_view", "properties": {"screen": s}} for s in ("home", "settings", "home", "settings")]
    wander += [{"type": "back"}] * 3
    wander += [{"type": "struggle_detected", "item_id": "call",
                "properties": {"task": "call", "score": 1.4, "signals": ["backtracking", "looping"]}}]
    assert (await client.post("/api/events", headers=hp, json={"session_id": "d1", "events": wander})).status_code == 200
    sug = (await client.get("/api/suggestions?hour=9", headers=hp)).json()
    assert sug["suggestions"][0]["task"] == "call" and sug["suggestions"][0]["text"] == "کال کریں"

    # 4. Parent accepts "Call" -> navigation plan -> Tier 1 dialer with contact ready
    plan = (await client.post("/api/navigation/plan", json={"task": "call", "slots": {"contact": "son"}}, headers=hp)).json()
    assert plan["steps"][0]["action"]["intent"] == "dial"
    await client.post("/api/events", headers=hp, json={"session_id": "d1", "events": [
        {"type": "suggestion_accepted", "item_id": "call", "properties": {"rank": 1}},
        {"type": "nav_started", "item_id": "call_contact", "properties": {"workflow_id": "call_contact", "tier": "tier1"}},
        {"type": "nav_completed", "item_id": "call_contact", "properties": {"workflow_id": "call_contact", "steps_total": 2}},
        {"type": "task_completed", "item_id": "call", "properties": {"task": "call", "hour": 9}},
    ]})

    # 5. Voice in Urdu works too
    v = (await client.post("/api/voice/intent", json={"transcript": "بیٹے کو فون کرو"}, headers=hp)).json()
    assert v["task"] == "call"

    # 6. Parent pastes a scam message -> Urdu verdict -> tells family
    chk = (await client.post("/api/scam/check", headers=hp, json={
        "text": "آپ کا بینک اکاؤنٹ بند کر دیا جائے گا۔ فوری طور پر اپنا کوڈ اس نمبر پر بھیجیں۔"})).json()
    assert chk["verdict"] == "likely_scam" and chk["explanation"]["label"]["ur"] == "غالباً دھوکہ"
    await client.post(f"/api/scam/share/{chk['id']}", headers=hp)

    # 7. Two more struggles on the same task -> caregiver gets struggle + scam alerts
    await client.post("/api/events", headers=hp, json={"session_id": "d1", "events": [
        {"type": "struggle_detected", "item_id": "call", "properties": {"task": "call"}}] * 2})
    alerts = (await client.get("/api/caregiver/alerts", headers=hc)).json()["alerts"]
    assert {a["type"] for a in alerts} == {"scam_shared", "repeated_struggle"}
    summary = (await client.get("/api/caregiver/summary", headers=hc)).json()["parents"][0]
    assert summary["scam_checks"]["verdicts"]["likely_scam"] == 1
    assert summary["friction_tasks"][0]["task"] == "call"

    # 8. Caregiver sends a guide card back
    pid = (await client.get("/api/me", headers=hp)).json()["id"]
    await client.post("/api/caregiver/guide-cards", headers=hc, json={"parent_id": pid, "text": "سبز بٹن دبائیں"})
    assert (await client.get("/api/guide-cards", headers=hp)).json()["cards"][0]["text"] == "سبز بٹن دبائیں"


def test_alembic_migration_matches_models():
    db = os.path.join(tempfile.mkdtemp(), "mig.db")
    env = {**os.environ, "DATABASE_URL": f"sqlite+aiosqlite:///{db}"}
    r = subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], cwd=BACKEND, env=env,
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    import sqlite3

    con = sqlite3.connect(db)
    for table in Base.metadata.sorted_tables:
        cols = {row[1] for row in con.execute(f"PRAGMA table_info({table.name})")}
        assert cols == {c.name for c in table.columns}, table.name
