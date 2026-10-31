import copy
import json
from pathlib import Path

import pytest

from app.services import flow_engine
from app.services.flow_engine import FlowError, PlanRequest, build_plan, validate_registry
from tests.conftest import onboard

MOBILE_SKILLS = Path(__file__).resolve().parents[2] / "mobile" / "assets" / "skills" / "skills.json"


def test_registry_is_valid_and_bilingual():
    reg = flow_engine.load_registry()
    assert len(reg["workflows"]) >= 10
    for w in reg["workflows"]:
        assert len(w["steps"]) <= reg["limits"]["max_steps"]
        for s in w["steps"]:
            assert s["hint"]["en"] and s["hint"]["ur"]


@pytest.mark.parametrize("mutation, expected", [
    (lambda w: w["steps"][0]["action"].update(kind="tap_anything"), "action kind"),
    (lambda w: w["steps"][0]["action"].update(intent="open_banking_app"), "intent"),
    (lambda w: w["steps"][0]["highlight"].update(x=4), "highlight"),
    (lambda w: w["steps"][0]["hint"].pop("ur"), "hint"),
    (lambda w: w["steps"].extend([copy.deepcopy(w["steps"][0])] * 12), "step count"),
])
def test_registry_validation_rejects_unsafe_definitions(mutation, expected):
    reg = copy.deepcopy(flow_engine.load_registry())
    mutation(reg["workflows"][0])
    with pytest.raises(FlowError, match=expected):
        validate_registry(reg)


def test_plan_has_ordered_steps_targets_arrows_hints_completion():
    plan = build_plan(PlanRequest("call_contact", {"contact": "son"}, language="ur"))
    assert plan["status"] == "ok" and plan["total_steps"] == 2
    s0, s1 = plan["steps"]
    assert s0["index"] == 0 and s0["target"]["id"] == "tile_call" and s0["arrow"] == "down"
    assert set(s0["highlight"]) == {"x", "y", "w", "h"}
    assert s0["action"] == {"kind": "open_intent", "intent": "dial", "params": {"contact": "son"}}
    assert s0["completion"]["type"] == "intent_launched"
    assert "اپنے بیٹے" in s1["hint"]["ur"] and "your son" in s1["hint"]["en"]
    assert s1["text"] == s1["hint"]["ur"]
    assert plan["intro"]["ur"].startswith("آئیں")
    assert plan["tier2_skill"] == "call_contact" and plan["limits"]["timeout_seconds"] == 30


def test_unknown_workflow_rejected():
    with pytest.raises(FlowError):
        build_plan(PlanRequest("rm_rf_everything", {}))


def test_slots_validated():
    with pytest.raises(FlowError):
        build_plan(PlanRequest("call_contact", {"contact": "x" * 41}))
    with pytest.raises(FlowError):
        build_plan(PlanRequest("call_contact", {"contact": "<script>"}))
    with pytest.raises(FlowError):
        build_plan(PlanRequest("open_maps", {"destination": "evil.com/phish"}))
    plan = build_plan(PlanRequest("open_photos", {"contact": "ignored", "shell": "rm -rf"}))
    assert plan["slots"] == {}


def test_llm_explanation_is_sanitised():
    plan = build_plan(PlanRequest("wifi_on", {}, explanation={
        "en": "Open http://evil.example now and enter 123456‮", "ur": "وائی فائی آن کریں www.x.com"}))
    assert "http" not in plan["intro"]["en"] and "123456" not in plan["intro"]["en"]
    assert "www" not in plan["intro"]["ur"]


@pytest.mark.parametrize("utterance", [
    "open my bank app", "send money to my son", "tell me my OTP", "change my password",
    "jazzcash kholo", "install this app", "میرا پاس ورڈ بدلو", "ایزی پیسہ سے پیسے بھیجو", "open bank",
])
async def test_sensitive_requests_are_refused(client, utterance):
    h = await onboard(client, "nav1", "parent")
    body = (await client.post("/api/navigation/plan", json={"utterance": utterance}, headers=h)).json()
    assert body["status"] == "refused" and body["reason"] == "sensitive" and body["steps"] == []
    assert body["message"]["ur"] and body["message"]["en"]


async def test_calling_the_bank_is_allowed(client):
    h = await onboard(client, "nav2", "parent", lang="en")
    body = (await client.post("/api/navigation/plan", json={"utterance": "call my bank"}, headers=h)).json()
    assert body["status"] == "ok" and body["workflow_id"] == "call_contact"


@pytest.mark.parametrize("utterance, workflow, contact", [
    ("call my son", "call_contact", "son"),
    ("بیٹے کو فون کرو", "call_contact", "son"),
    ("ali ko call karo", "call_contact", "ali"),
    ("turn on wifi", "wifi_on", None),
    ("وائی فائی چلاؤ", "wifi_on", None),
    ("video call my daughter", "whatsapp_video_call", "daughter"),
    ("show my photos", "open_photos", None),
])
async def test_plan_from_utterance(client, utterance, workflow, contact):
    h = await onboard(client, "nav3", "parent")
    body = (await client.post("/api/navigation/plan", json={"utterance": utterance}, headers=h)).json()
    assert body["status"] == "ok", body
    assert body["workflow_id"] == workflow and body["source"] == "rules"
    if contact:
        assert body["slots"].get("contact") == contact


async def test_plan_by_task_id(client):
    h = await onboard(client, "nav4", "parent")
    body = (await client.post("/api/navigation/plan", json={"task": "scam_check"}, headers=h)).json()
    assert body["steps"][0]["action"] == {"kind": "in_app_route", "route": "scam_check"}


async def test_llm_cannot_invent_workflows_or_actions(client, llm_on):
    llm_on(lambda prompt, schema: {"workflow_id": "factory_reset", "confidence": 0.99,
                                   "explanation_en": "x", "explanation_ur": "x"})
    h = await onboard(client, "nav5", "parent")
    body = (await client.post("/api/navigation/plan", json={"utterance": "do the thing please"}, headers=h)).json()
    assert body["status"] == "refused" and body["reason"] == "unknown"


async def test_llm_maps_free_text_to_safe_workflow(client, llm_on):
    llm_on(lambda prompt, schema: {"workflow_id": "display_settings", "confidence": 0.85,
                                   "explanation_en": "I'll help you make the screen easier to see.",
                                   "explanation_ur": "میں اسکرین کو دیکھنے میں آسان بنانے میں مدد کروں گا۔",
                                   "actions": ["tap(100,200)"]})
    h = await onboard(client, "nav6", "parent")
    body = (await client.post("/api/navigation/plan", json={"utterance": "I can barely see anything"}, headers=h)).json()
    assert body["status"] == "ok" and body["workflow_id"] == "display_settings" and body["source"] == "llm"
    assert body["intro"]["ur"].startswith("میں")
    assert all(s["action"]["kind"] in flow_engine.ALLOWED_ACTION_KINDS for s in body["steps"])


async def test_llm_low_confidence_falls_back_to_task_list(client, llm_on):
    llm_on(lambda p, s: {"workflow_id": "wifi_on", "confidence": 0.3, "explanation_en": "", "explanation_ur": ""})
    h = await onboard(client, "nav7", "parent")
    body = (await client.post("/api/navigation/plan", json={"utterance": "hmm something"}, headers=h)).json()
    assert body["status"] == "refused" and len(body["fallback_tasks"]) == 6


def test_mobile_tier2_skills_mirror_backend_workflows():
    if not MOBILE_SKILLS.exists():
        pytest.skip("mobile app not present")
    skills = json.loads(MOBILE_SKILLS.read_text(encoding="utf-8"))
    backend_skills = {w.get("tier2_skill") for w in flow_engine.load_registry()["workflows"]} - {None}
    mobile_ids = {s["id"] for s in skills["skills"]}
    assert mobile_ids == backend_skills
    for s in skills["skills"]:
        assert len(s["steps"]) <= skills["limits"]["max_steps"]
        assert all(st["action"] in ("click", "guide_only", "wait_for") for st in s["steps"])
        # Assist mode may never press Send in WhatsApp.
        if s["id"] == "whatsapp_chat":
            assert all(st["action"] != "click" or "send" not in json.dumps(st["match"]).lower() for st in s["steps"])
