from datetime import datetime, timedelta, timezone

from sqlalchemy import update

from app.core.db import SessionLocal
from app.models import CaregiverLink, Event
from app.services import email as email_service
from tests.conftest import H, onboard


async def link_pair(client, *, sharing=True, parent="par", carer="car", email="kid@example.com"):
    hp = await onboard(client, parent, "parent", sharing=sharing, name="Ammi")
    hc = await onboard(client, carer, "caregiver", lang="en", email=email, name="Ali")
    r = await client.post("/api/caregiver/invite", json={"email": email}, headers=hp)
    assert r.status_code == 200, r.text
    code = r.json()["dev_invite_code"]
    link_id = r.json()["link"]["id"]
    assert (await client.post("/api/caregiver/accept", json={"code": code}, headers=hc)).status_code == 200
    assert (await client.post(f"/api/caregiver/approve/{link_id}", headers=hp)).json()["link"]["status"] == "active"
    return hp, hc, link_id


async def test_invite_sends_bilingual_email(client):
    hp = await onboard(client, "p", "parent", lang="ur", name="Ammi")
    r = await client.post("/api/caregiver/invite", json={"email": "Kid@Example.com"}, headers=hp)
    assert r.json()["email_sent"] is True and r.json()["link"]["status"] == "pending"
    mail = email_service.OUTBOX[-1]
    assert mail["to"] == "kid@example.com" and r.json()["dev_invite_code"] in mail["body"]
    assert "کوڈ" in mail["body"] and "code" in mail["body"]
    assert (await client.post("/api/caregiver/invite", json={"email": "not-an-email"}, headers=hp)).status_code == 422


async def test_only_parents_invite_and_only_caregivers_accept(client):
    hc = await onboard(client, "c", "caregiver")
    assert (await client.post("/api/caregiver/invite", json={"email": "a@b.co"}, headers=hc)).status_code == 403
    hp = await onboard(client, "p", "parent")
    code = (await client.post("/api/caregiver/invite", json={"email": "a@b.co"}, headers=hp)).json()["dev_invite_code"]
    assert (await client.post("/api/caregiver/accept", json={"code": code}, headers=hp)).status_code == 403


async def test_code_is_one_time_and_expires(client):
    hp = await onboard(client, "p", "parent")
    hc = await onboard(client, "c", "caregiver")
    hc2 = await onboard(client, "c2", "caregiver")
    r = await client.post("/api/caregiver/invite", json={"email": "x@y.co"}, headers=hp)
    code = r.json()["dev_invite_code"]
    async with SessionLocal() as db:
        await db.execute(update(CaregiverLink).values(invite_expires_at=datetime.now(timezone.utc) - timedelta(hours=1)))
        await db.commit()
    assert (await client.post("/api/caregiver/accept", json={"code": code}, headers=hc)).status_code == 410
    r = await client.post("/api/caregiver/invite", json={"email": "x@y.co"}, headers=hp)
    code = r.json()["dev_invite_code"]
    assert (await client.post("/api/caregiver/accept", json={"code": code}, headers=hc)).status_code == 200
    assert (await client.post("/api/caregiver/accept", json={"code": code}, headers=hc2)).status_code == 404


async def test_email_must_match_invite(client):
    hp = await onboard(client, "p", "parent")
    hc = await onboard(client, "c", "caregiver", email="someone@else.com")
    code = (await client.post("/api/caregiver/invite", json={"email": "kid@example.com"}, headers=hp)).json()["dev_invite_code"]
    assert (await client.post("/api/caregiver/accept", json={"code": code}, headers=hc)).status_code == 403


async def test_not_active_until_parent_approves(client):
    hp = await onboard(client, "p", "parent", sharing=True)
    hc = await onboard(client, "c", "caregiver")
    r = await client.post("/api/caregiver/invite", json={"email": "c@x.co"}, headers=hp)
    await client.post("/api/caregiver/accept", json={"code": r.json()["dev_invite_code"]}, headers=hc)
    links = (await client.get("/api/caregiver/links", headers=hp)).json()["links"]
    assert links[0]["awaiting_parent_approval"] is True
    assert (await client.get("/api/caregiver/summary", headers=hc)).json()["parents"] == []


async def test_sharing_off_caregiver_sees_nothing(client):
    hp, hc, _ = await link_pair(client, sharing=False)
    await client.post("/api/events", headers=hp, json={"session_id": "s", "events": [{"type": "task_completed", "item_id": "call"}]})
    assert (await client.get("/api/caregiver/summary", headers=hc)).json()["parents"] == []
    assert (await client.get("/api/caregiver/alerts", headers=hc)).json()["alerts"] == []


async def test_summary_has_counts_but_no_content(client):
    hp, hc, _ = await link_pair(client)
    await client.post("/api/events", headers=hp, json={"session_id": "s", "events": [
        {"type": "task_completed", "item_id": "call", "properties": {"task": "call"}},
        {"type": "task_completed", "item_id": "photos", "properties": {"task": "photos"}},
        {"type": "struggle_detected", "item_id": "whatsapp", "properties": {"task": "whatsapp", "score": 1.3}},
    ]})
    await client.post("/api/scam/check", headers=hp, json={"text": "Share your OTP now or account blocked"})
    p = (await client.get("/api/caregiver/summary", headers=hc)).json()["parents"][0]
    today = datetime.now(timezone.utc).date().isoformat()
    assert p["tasks_completed_per_day"][today] == 2
    assert p["struggle_episodes_per_day"][today] == 1
    assert p["friction_tasks"][0]["task"] == "whatsapp"
    assert p["scam_checks"]["total"] == 1 and p["scam_checks"]["verdicts"]["likely_scam"] == 1
    assert p["last_active"] and p["display_name"] == "Ammi"
    blob = str(p)
    assert "OTP" not in blob and "text" not in p
    # parent can preview exactly what is shared
    preview = (await client.get("/api/me/sharing-preview", headers=hp)).json()
    assert preview["sharing"] is True and preview["summary"]["scam_checks"]["total"] == 1


async def test_revoke_removes_access_immediately(client):
    hp, hc, link_id = await link_pair(client)
    assert len((await client.get("/api/caregiver/summary", headers=hc)).json()["parents"]) == 1
    assert (await client.delete(f"/api/caregiver/link/{link_id}", headers=hp)).json()["link"]["status"] == "revoked"
    assert (await client.get("/api/caregiver/summary", headers=hc)).json()["parents"] == []
    assert (await client.post("/api/caregiver/guide-cards", headers=hc, json={"parent_id": "x", "text": "hi"})).status_code == 403


async def test_repeated_struggle_alert_once_per_task_per_day(client):
    hp, hc, _ = await link_pair(client)
    ev = {"type": "struggle_detected", "item_id": "whatsapp", "properties": {"task": "whatsapp"}}
    for _ in range(2):
        await client.post("/api/events", headers=hp, json={"session_id": "s", "events": [ev]})
    assert (await client.get("/api/caregiver/alerts", headers=hc)).json()["alerts"] == []
    for _ in range(3):
        await client.post("/api/events", headers=hp, json={"session_id": "s", "events": [ev]})
    alerts = (await client.get("/api/caregiver/alerts", headers=hc)).json()
    assert alerts["unseen"] == 1 and alerts["alerts"][0]["type"] == "repeated_struggle"
    msg = alerts["alerts"][0]["payload"]["message"]
    assert "WhatsApp video call" in msg["en"] and "واٹس ایپ" in msg["ur"]
    aid = alerts["alerts"][0]["id"]
    await client.post(f"/api/caregiver/alerts/{aid}/seen", headers=hc)
    assert (await client.get("/api/caregiver/alerts", headers=hc)).json()["unseen"] == 0


async def test_tell_my_family_shares_verdict_not_content(client):
    hp, hc, _ = await link_pair(client)
    check = (await client.post("/api/scam/check", headers=hp, json={"text": "You won a lottery! Send fee 5000 to claim prize"})).json()
    r = (await client.post(f"/api/scam/share/{check['id']}", headers=hp)).json()
    assert r["caregivers_notified"] == 1
    alert = (await client.get("/api/caregiver/alerts", headers=hc)).json()["alerts"][0]
    assert alert["type"] == "scam_shared" and alert["payload"]["verdict"] == "likely_scam"
    assert "lottery" not in str(alert).lower()


async def test_inactivity_alert_job(client):
    hp, hc, _ = await link_pair(client)
    await client.post("/api/events", headers=hp, json={"session_id": "s", "events": [{"type": "tap"}]})
    async with SessionLocal() as db:
        await db.execute(update(Event).values(created_at=datetime.now(timezone.utc) - timedelta(days=3)))
        await db.commit()
    assert (await client.post("/api/alerts/inactivity/run", headers={"X-Admin-Token": "wrong"})).status_code == 403
    assert (await client.post("/api/alerts/inactivity/run", headers={"X-Admin-Token": "test-admin"})).json()["created"] == 1
    assert (await client.post("/api/alerts/inactivity/run", headers={"X-Admin-Token": "test-admin"})).json()["created"] == 0
    alert = (await client.get("/api/caregiver/alerts", headers=hc)).json()["alerts"][0]
    assert alert["type"] == "inactivity" and "3" in alert["payload"]["message"]["ur"]


async def test_guide_cards(client):
    hp, hc, _ = await link_pair(client)
    parent_id = (await client.get("/api/me", headers=hp)).json()["id"]
    r = await client.post("/api/caregiver/guide-cards", headers=hc,
                          json={"parent_id": parent_id, "text": "Tap Photos, then the plus sign", "workflow_id": "open_photos"})
    assert r.status_code == 200
    assert (await client.post("/api/caregiver/guide-cards", headers=hc,
                              json={"parent_id": parent_id, "text": "x", "workflow_id": "evil"})).status_code == 422
    cards = (await client.get("/api/guide-cards", headers=hp)).json()["cards"]
    assert cards[0]["text"].startswith("Tap Photos") and cards[0]["from"] == "Ali"
    await client.post(f"/api/guide-cards/{cards[0]['id']}/seen", headers=hp)
    assert (await client.get("/api/guide-cards", headers=hp)).json()["cards"] == []
