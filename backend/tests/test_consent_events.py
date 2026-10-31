from sqlalchemy import func, select

from app.core.db import SessionLocal
from app.models import Event
from tests.conftest import H, onboard


async def _count_events():
    async with SessionLocal() as db:
        return (await db.execute(select(func.count()).select_from(Event))).scalar_one()


BATCH = {"session_id": "s1", "events": [{"type": "screen_view", "properties": {"screen": "home"}}]}


async def test_nothing_logged_before_consent(client):
    h = H("p1")
    await client.put("/api/me/role", json={"role": "parent"}, headers=h)
    r = await client.post("/api/events", json=BATCH, headers=h)
    assert r.status_code == 403 and r.json()["detail"] == "consent_required"
    assert await _count_events() == 0


async def test_tracking_declined_logs_nothing(client):
    h = await onboard(client, "p2", "parent", tracking=False)
    assert (await client.post("/api/events", json=BATCH, headers=h)).status_code == 403
    assert await _count_events() == 0


async def test_consent_defaults_and_text(client):
    h = H("p3")
    body = (await client.get("/api/consent", headers=h)).json()
    assert body["consent"]["caregiver_sharing"] is False and body["consent"]["scam_text_storage"] is False
    for k in ("activity_tracking", "caregiver_sharing", "scam_text_storage", "ai_disclosure"):
        assert body["text"][k]["en"] and body["text"][k]["ur"]


async def test_events_accept_actions_and_strip_content(client):
    h = await onboard(client, "p4", "parent")
    r = await client.post("/api/events", headers=h, json={"session_id": "s-1", "events": [
        {"type": "tap", "item_id": "tile_call", "properties": {"screen": "home", "target": "tile_call",
                                                                "text": "secret message", "contact_name": "Ali",
                                                                "number": "03001234567"}},
        {"type": "task_completed", "item_id": "call", "properties": {"task": "call", "hour": 9}},
        {"type": "message_read", "properties": {}},                         # unknown type
        {"type": "tap", "item_id": "Has Spaces And Caps!", "properties": {}},  # bad id
        {"type": "tap", "properties": {"screen": "free text with spaces"}},   # unsafe value dropped
    ]})
    assert r.json() == {"accepted": 3, "rejected": 2}
    async with SessionLocal() as db:
        rows = (await db.execute(select(Event).order_by(Event.id))).scalars().all()
    assert rows[0].properties == {"screen": "home", "target": "tile_call"}
    assert rows[0].session_id == "s-1"
    assert rows[2].properties == {}


async def test_all_prd_event_types_accepted(client):
    h = await onboard(client, "p5", "parent")
    types = ["screen_view", "tap", "back", "idle", "task_started", "task_completed", "suggestion_shown",
             "suggestion_accepted", "suggestion_dismissed", "something_else_tapped", "nav_started",
             "nav_completed", "nav_aborted"]
    r = await client.post("/api/events", headers=h, json={"session_id": "s", "events": [{"type": t} for t in types]})
    assert r.json()["accepted"] == len(types)


async def test_revoking_tracking_stops_logging(client):
    h = await onboard(client, "p6", "parent")
    assert (await client.post("/api/events", json=BATCH, headers=h)).status_code == 200
    await client.put("/api/consent", json={"activity_tracking": False}, headers=h)
    assert (await client.post("/api/events", json=BATCH, headers=h)).status_code == 403
    assert await _count_events() == 1
