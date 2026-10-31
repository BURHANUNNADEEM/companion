"""F7 acceptance: >= 80% of scripted supported commands map to the right task (Urdu, Roman Urdu, English)."""
from app.services.intent import match_rules
from tests.conftest import onboard

SCRIPTED = [
    ("call my son", "call"), ("phone Ali", "call"), ("please call my daughter", "call"),
    ("بیٹے کو فون کرو", "call"), ("علی کو کال کریں", "call"), ("beta ko call karo", "call"),
    ("show my photos", "photos"), ("open gallery", "photos"), ("میری تصویریں دکھاؤ", "photos"),
    ("tasveerein dikhao", "photos"),
    ("send a message to my son", "messages"), ("read my messages", "messages"), ("پیغامات کھولو", "messages"),
    ("video call my daughter", "whatsapp"), ("بیٹی کو ویڈیو کال کرو", "whatsapp"),
    ("whatsapp my son", "whatsapp_chat"), ("واٹس ایپ کھولو", "whatsapp_chat"),
    ("is this message a scam", "scam_check"), ("کیا یہ دھوکہ ہے", "scam_check"), ("check this message", "scam_check"),
    ("turn on wifi", "wifi"), ("انٹرنیٹ نہیں چل رہا", "wifi"), ("wifi on karo", "wifi"),
    ("turn on bluetooth", "bluetooth"), ("make it louder", "sound"), ("آواز تیز کرو", "sound"),
    ("screen is too dark", "display"), ("take a photo", "camera"), ("کیمرا کھولو", "camera"),
    ("how do I get to the hospital", "maps"), ("ہسپتال کا راستہ", "maps"),
    ("I need help", "ask_family"), ("گھر والوں سے بات کرنی ہے", "ask_family"),
    ("send a photo to my son", "share_photo"),
]


def _task(wid):
    from app.services.flow_engine import workflows_by_id

    return workflows_by_id()[wid]["task"] if wid else None


def test_scripted_command_accuracy():
    correct = sum(_task(match_rules(text).workflow_id) == task for text, task in SCRIPTED)
    misses = [(t, _task(match_rules(t).workflow_id)) for t, task in SCRIPTED if _task(match_rules(t).workflow_id) != task]
    accuracy = correct / len(SCRIPTED)
    print(f"voice accuracy {accuracy:.0%}; misses: {misses}")
    assert accuracy >= 0.80


async def test_voice_endpoint_bilingual(client):
    h = await onboard(client, "v1", "parent", lang="ur")
    body = (await client.post("/api/voice/intent", json={"transcript": "بیٹے کو فون کرو", "locale": "ur-PK"}, headers=h)).json()
    assert body["task"] == "call" and body["slots"]["relation"] == "son"
    assert body["text"] == body["explanation"]["ur"]


async def test_unmatched_without_llm_shows_task_list(client):
    h = await onboard(client, "v2", "parent", lang="en")
    body = (await client.post("/api/voice/intent", json={"transcript": "blorp zzz"}, headers=h)).json()
    assert body["task"] is None and len(body["fallback_tasks"]) == 6
    assert body["explanation"]["en"] and body["explanation"]["ur"]


async def test_unmatched_goes_to_llm_with_redacted_text(client, llm_on):
    seen = {}

    def fake(prompt, schema):
        seen["prompt"] = prompt
        return {"workflow_id": "open_camera", "confidence": 0.8, "explanation_en": "Let's take a picture.",
                "explanation_ur": "آئیں تصویر لیتے ہیں۔"}

    llm_on(fake)
    h = await onboard(client, "v3", "parent", lang="en")
    body = (await client.post("/api/voice/intent", json={"transcript": "I want to capture this moment, my number is 03001234567"}, headers=h)).json()
    assert body["task"] == "camera" and body["source"] == "llm"
    assert "03001234567" not in seen["prompt"] and "[PHONE]" in seen["prompt"]


async def test_llm_rate_limit_falls_back(client, llm_on, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "llm_rate_per_minute", 1)
    llm_on(lambda p, s: {"workflow_id": "open_camera", "confidence": 0.8, "explanation_en": "a", "explanation_ur": "b"})
    h = await onboard(client, "v4", "parent")
    first = (await client.post("/api/voice/intent", json={"transcript": "zzz one"}, headers=h)).json()
    second = (await client.post("/api/voice/intent", json={"transcript": "zzz two"}, headers=h)).json()
    assert first["task"] == "camera" and second["task"] is None
