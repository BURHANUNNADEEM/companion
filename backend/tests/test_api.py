"""End-to-end API tests against a real Postgres.

Run (from backend/):
    DEV_AUTH_ENABLED=true python -m pytest -q tests
Uses "Bearer dev-<uuid>" tokens, so DEV_AUTH_ENABLED must be true for tests.
"""

import os
import uuid

os.environ.setdefault("DEV_AUTH_ENABLED", "true")

import pytest
from fastapi.testclient import TestClient

from main import app
from services import gemini


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def user_headers() -> dict:
    return {"Authorization": f"Bearer dev-{uuid.uuid4().hex[:12]}"}


@pytest.fixture
def h(client):
    hd = user_headers()
    r = client.put("/api/consent", json={"tracking": True}, headers=hd)
    assert r.status_code == 200
    return hd


# ---------------- health & auth ----------------
def test_health(client):
    assert client.get("/health").json()["status"] == "ok"
    assert client.get("/health/db").json() == {"db": "ok"}


def test_auth_required(client):
    r = client.get("/api/me")
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "unauthorized"
    r = client.get("/api/me", headers={"Authorization": "Bearer not-a-real-token"})
    assert r.status_code == 401


def test_me_and_profile(client):
    hd = user_headers()
    me = client.get("/api/me", headers=hd).json()
    assert me["language"] == "ur" and me["consent_given"] is False
    r = client.patch("/api/me", json={"display_name": "Ammi", "language": "ur"}, headers=hd)
    assert r.status_code == 200 and r.json()["display_name"] == "Ammi"
    assert client.patch("/api/me", json={"language": "fr"}, headers=hd).status_code == 422


# ---------------- consent & events ----------------
def test_events_blocked_without_consent(client):
    hd = user_headers()
    r = client.post("/api/events", json={"event_type": "tap"}, headers=hd)
    assert r.status_code == 403 and r.json()["error"]["code"] == "consent_required"


def test_consent_roundtrip(client):
    hd = user_headers()
    assert client.get("/api/consent", headers=hd).json()["tracking"] is False
    r = client.put("/api/consent", json={"tracking": True, "ai_processing": True}, headers=hd)
    assert r.json()["tracking"] is True and r.json()["ai_processing"] is True
    r = client.put("/api/consent", json={"ai_processing": False}, headers=hd)
    assert r.json()["tracking"] is True and r.json()["ai_processing"] is False


def test_event_single_and_batch_and_sanitising(client, h):
    assert client.post("/api/events", json={"event_type": "screen_view", "item_id": "home"}, headers=h).status_code == 201
    body = {
        "session_id": "s1",
        "events": [
            {"event_type": "tap", "item_id": "tile_call", "properties": {"screen": "home", "text": "SECRET"}},
            {"event_type": "back", "occurred_at": "2026-10-31T09:00:00Z"},
        ],
    }
    r = client.post("/api/events/batch", json=body, headers=h)
    assert r.status_code == 201 and r.json()["accepted"] == 2
    assert client.post("/api/events/batch", json={"events": []}, headers=h).status_code == 422


# ---------------- workflows ----------------
def test_workflows_allowlist(client, h):
    ids = [w["id"] for w in client.get("/api/workflows", headers=h).json()["workflows"]]
    assert {"call_family", "whatsapp_video", "scam_check"} <= set(ids)
    wf = client.get("/api/workflows/call_family?contact_id=son", headers=h).json()
    assert wf["steps"][1]["target_id"] == "contact_son" and wf["starting_help_level"] == "full"
    r = client.get("/api/workflows/rm_rf_everything", headers=h)
    assert r.status_code == 404 and r.json()["error"]["code"] == "unknown_workflow"


def test_workflow_resolve(client, h):
    r = client.post("/api/workflows/call_family/resolve", json={"contact_phone": "0300-1234567"}, headers=h)
    assert r.status_code == 200
    assert r.json()["launch"]["uri"] == "tel:+923001234567" and r.json()["launch"]["user_must_tap"] is True
    r = client.post("/api/workflows/whatsapp_video/resolve", json={"contact_phone": "923001234567"}, headers=h)
    assert r.json()["launch"]["uri"] == "https://wa.me/923001234567"
    r = client.post("/api/workflows/call_family/resolve", json={"contact_phone": "javascript:alert(1)"}, headers=h)
    assert r.status_code == 422
    r = client.post("/api/workflows/call_family/resolve", json={}, headers=h)
    assert r.json()["error"]["code"] == "phone_required"
    r = client.post("/api/workflows/wifi_settings/resolve", json={}, headers=h)
    assert r.json()["launch"]["android_action"] == "android.settings.WIFI_SETTINGS"


# ---------------- help ladder ----------------
def _run(client, h, task="call_family", struggle_at=None):
    a = client.post(f"/api/tasks/{task}/start", headers=h).json()
    if struggle_at is not None:
        r = client.post(f"/api/tasks/attempts/{a['attempt_id']}/struggle",
                        json={"step_index": struggle_at, "current_help_level": a["start_help_level"]}, headers=h)
        assert r.status_code == 200
    done = client.post(f"/api/tasks/attempts/{a['attempt_id']}/complete", json={"duration_ms": 9000}, headers=h).json()
    return a, done


def test_help_fades_full_highlight_none_mastered(client, h):
    a1, d1 = _run(client, h)
    assert a1["start_help_level"] == "full" and d1["clean"] is True
    a2, _ = _run(client, h)
    assert a2["start_help_level"] == "highlight"
    a3, d3 = _run(client, h)
    assert a3["start_help_level"] == "highlight"
    assert d3["celebration"]["just_mastered"] is True and d3["progress"]["stage"] == "confident"
    a4, d4 = _run(client, h)
    assert a4["start_help_level"] == "none"
    assert d4["progress"]["independent_completions"] == 1
    assert "1" in d4["celebration"]["message_en"]


def test_struggled_run_not_clean_and_stuck_step(client, h):
    _, d = _run(client, h, struggle_at=1)
    assert d["clean"] is False and d["progress"]["stage"] == "learning"
    assert d["progress"]["most_struggled_step"]["step_index"] == 1
    p = client.get("/api/progress", headers=h).json()
    assert "call_family" in p["summary"]["learning"]


def test_attempt_rules(client, h):
    a, _ = _run(client, h)
    r = client.post(f"/api/tasks/attempts/{a['attempt_id']}/complete", json={}, headers=h)
    assert r.status_code == 409
    other = user_headers()
    r = client.post(f"/api/tasks/attempts/{a['attempt_id']}/complete", json={}, headers=other)
    assert r.status_code == 404  # cannot touch someone else's attempt
    assert client.post("/api/tasks/not_a_task/start", headers=h).status_code == 404


def test_seed_and_reset(client, h):
    p = client.post("/api/progress/whatsapp_video/seed", json={"clean_completions": 2}, headers=h).json()
    assert p["starting_help_level"] == "highlight"
    assert client.post("/api/progress/reset", headers=h).json()["ok"] is True
    assert client.get("/api/progress/whatsapp_video", headers=h).json()["starting_help_level"] == "full"


# ---------------- struggle & suggestions ----------------
def test_struggle_in_task_raises_help(client, h):
    a = client.post("/api/tasks/call_family/start", headers=h).json()
    r = client.post("/api/struggle/evaluate", json={
        "task_id": "call_family", "attempt_id": a["attempt_id"], "step_index": 1,
        "current_help_level": "none", "wrong_taps": 2,
    }, headers=h).json()
    assert r["triggered"] and r["action"] == "raise_help" and r["new_help_level"] == "nudge"
    calm = client.post("/api/struggle/evaluate", json={"task_id": "call_family", "idle_seconds": 3}, headers=h).json()
    assert calm["triggered"] is False and calm["action"] == "none"


def test_idle_uses_own_pace(client, h):
    # slow user: median step 6s -> threshold 15s, so 10s idle is NOT struggle
    r = client.post("/api/struggle/evaluate", json={"task_id": "call_family", "idle_seconds": 10,
                                                     "median_step_ms": 6000}, headers=h).json()
    assert r["triggered"] is False and r["idle_threshold_seconds"] == 15.0


def test_struggle_on_home_gives_suggestions_and_backoff(client, h):
    r = client.post("/api/struggle/evaluate", json={"idle_seconds": 25}, headers=h).json()
    assert r["action"] == "show_suggestions" and len(r["suggestions"]["suggestions"]) == 3
    for _ in range(3):
        client.post("/api/suggestions/feedback", json={"task_id": "call_family", "outcome": "dismissed"}, headers=h)
    s = client.get("/api/suggestions", headers=h).json()
    assert s["backoff"] is True and s["suggestions"] == []


def test_suggestions_learn_from_history(client, h):
    _run(client, h, "scam_check")
    _run(client, h, "whatsapp_video")
    _run(client, h, "scam_check")
    s = client.get("/api/suggestions?last_task=scam_check", headers=h).json()
    assert s["suggestions"][0]["task_id"] == "whatsapp_video"


def test_struggle_config(client, h):
    c = client.get("/api/struggle/config", headers=h).json()
    assert c["trigger_threshold"] == 1.0 and "ladder" in c


# ---------------- scam ----------------
BISP = "Mubarak ho! Aap ki BISP raqam Rs 25,000 approve ho gayi. Processing fee 500 bhej kar foran link par click karein: bisp-gov.xyz/claim"


def test_scam_rules(client, h):
    r = client.post("/api/scam/check", json={"text": BISP}, headers=h).json()
    assert r["verdict"] == "likely_scam" and r["source"] == "rules" and r["ai_used"] is False
    assert any(x["rule_id"] == "link_mismatch" for x in r["reasons"]) and r["lesson_ur"]
    assert client.post("/api/scam/check", json={"text": "Share your OTP now or account blocked"},
                       headers=h).json()["verdict"] == "likely_scam"
    assert client.post("/api/scam/check", json={"text": "مبارک ہو! آپ نے انعام جیتا ہے۔ اپنا کوڈ بھیجیں"},
                       headers=h).json()["verdict"] == "likely_scam"
    assert client.post("/api/scam/check", json={"text": "Ammi main 6 baje ghar aaunga"},
                       headers=h).json()["verdict"] == "probably_fine"
    hist = client.get("/api/scam/history", headers=h).json()
    assert hist["counts"]["likely_scam"] == 3 and "redacted_text" not in hist["items"][0]


def test_scam_gemini_fallback_only_when_inconclusive_and_consented(client, h, monkeypatch):
    calls = []

    async def fake(text):
        calls.append(text)
        return gemini.GeminiScamResult(level="likely_scam", confidence=0.9, reason_en="Fake courier", reason_ur="جعلی")

    monkeypatch.setattr(gemini, "classify_scam", fake)
    msg = "Your parcel is held. Visit dhl-track.xyz and call 03001234567"
    r = client.post("/api/scam/check", json={"text": msg}, headers=h).json()
    assert calls == [] and r["verdict"] == "be_careful"  # no AI consent -> rules only
    client.put("/api/consent", json={"ai_processing": True}, headers=h)
    r = client.post("/api/scam/check", json={"text": msg}, headers=h).json()
    assert r["ai_used"] is True and r["verdict"] == "likely_scam" and r["source"] == "rules+gemini"
    assert "03001234567" not in calls[0]  # redacted before AI
    client.post("/api/scam/check", json={"text": BISP}, headers=h)
    assert len(calls) == 1  # conclusive rules -> no AI call


def test_scam_gemini_cannot_lower_rule_verdict(client, h, monkeypatch):
    async def fake(text):
        return gemini.GeminiScamResult(level="probably_fine", confidence=0.99, reason_en="ok", reason_ur="ٹھیک")

    monkeypatch.setattr(gemini, "classify_scam", fake)
    client.put("/api/consent", json={"ai_processing": True}, headers=h)
    r = client.post("/api/scam/check", json={"text": "Visit bit.ly/abc for details"}, headers=h).json()
    assert r["verdict"] == "be_careful"


def test_gemini_invalid_output_is_rejected(monkeypatch):
    import asyncio
    import httpx

    class FakeResp:
        status_code = 200

        def json(self):
            return {"candidates": [{"content": {"parts": [{"text": '{"level": "DELETE_ALL", "confidence": 5}'}]}}]}

    class FakeClient:
        def __init__(self, *a, **k): ...
        async def __aenter__(self): return self
        async def __aexit__(self, *a): ...
        async def post(self, *a, **k): return FakeResp()

    from core.config import get_settings
    monkeypatch.setattr(get_settings(), "gemini_api_key", "x")
    monkeypatch.setattr(httpx, "AsyncClient", FakeClient)
    assert asyncio.run(gemini.classify_scam("hi")) is None


# ---------------- voice ----------------
def test_voice_intent_keywords(client, h):
    for t, want in [("Ali ko call karo", "call_family"), ("بیٹے سے ویڈیو پر بات کرنی ہے", "whatsapp_video"),
                    ("ye message fraud hai kya", "scam_check"), ("wifi on karo", "wifi_settings")]:
        r = client.post("/api/voice/intent", json={"transcript": t}, headers=h).json()
        assert r["task_id"] == want, (t, r)
        assert r["requires_confirmation"] is True
    r = client.post("/api/voice/intent", json={"transcript": "aaj mausam kaisa hai"}, headers=h).json()
    assert r["task_id"] is None and len(r["fallback_options"]) >= 3


def test_voice_gemini_constrained_to_allowlist(client, h, monkeypatch):
    async def fake(transcript, allowed):
        assert "call_family" in allowed
        return gemini.GeminiIntentResult(task_id=None, confidence=0.9, explanation_ur="")

    monkeypatch.setattr(gemini, "classify_intent", fake)
    client.put("/api/consent", json={"ai_processing": True}, headers=h)
    r = client.post("/api/voice/intent", json={"transcript": "transfer all my money"}, headers=h).json()
    assert r["task_id"] is None and r["source"] == "gemini"


# ---------------- delete my data ----------------
def test_delete_my_data(client, h):
    _run(client, h)
    client.post("/api/scam/check", json={"text": BISP}, headers=h)
    assert client.request("DELETE", "/api/me/data", json={}, headers=h).status_code == 422  # needs confirm
    r = client.request("DELETE", "/api/me/data", json={"confirm": "DELETE"}, headers=h).json()
    assert r["deleted"] is True and r["rows_deleted"]["task_attempts"] >= 1 and r["rows_deleted"]["scam_checks"] == 1
    me = client.get("/api/me", headers=h).json()  # a fresh, empty account is created on next login
    assert me["consent_given"] is False
    assert client.get("/api/scam/history", headers=h).json()["counts"]["likely_scam"] == 0
