"""LLM gateway to Gemini (F8).

Rules enforced here:
* All calls are server-side; the API key never ships in the app.
* Input is ALWAYS redacted before sending (callers pass redacted text; we redact again defensively).
* Output must be JSON and is validated with Pydantic; anything invalid -> None (caller falls back).
* Per-user rate limit, request timeout, small in-memory cache.
* When LLM_ENABLED=false or no key is configured, every function returns None and the app
  keeps working with the rule-based paths.
"""
from __future__ import annotations

import hashlib
import json
import logging
from collections import OrderedDict
from typing import Literal

import httpx
from pydantic import BaseModel, Field, ValidationError

from app.core.config import get_settings
from app.core.ratelimit import limiter
from app.services.redaction import redact

log = logging.getLogger(__name__)

GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


class IntentLLMOut(BaseModel):
    workflow_id: str | None = None
    contact: str | None = Field(default=None, max_length=40)
    destination: str | None = Field(default=None, max_length=80)
    confidence: float = Field(ge=0, le=1)
    explanation_en: str = Field(default="", max_length=300)
    explanation_ur: str = Field(default="", max_length=300)


class ScamLLMOut(BaseModel):
    verdict: Literal["likely_scam", "be_careful", "probably_fine"]
    confidence: float = Field(ge=0, le=1)
    reason_en: str = Field(default="", max_length=300)
    reason_ur: str = Field(default="", max_length=300)


class _Cache:
    def __init__(self, size: int = 256) -> None:
        self.size = size
        self.data: OrderedDict[str, dict] = OrderedDict()

    def get(self, key: str) -> dict | None:
        if key in self.data:
            self.data.move_to_end(key)
            return self.data[key]
        return None

    def put(self, key: str, value: dict) -> None:
        self.data[key] = value
        self.data.move_to_end(key)
        while len(self.data) > self.size:
            self.data.popitem(last=False)


_cache = _Cache()

# Test hook: set to a callable(prompt, schema) -> dict to fake Gemini in tests.
_fake_transport = None


def llm_available() -> bool:
    s = get_settings()
    return bool(s.llm_enabled and (s.gemini_api_key or _fake_transport))


async def _call_gemini(prompt: str, schema: dict) -> dict | None:
    s = get_settings()
    if _fake_transport is not None:
        return _fake_transport(prompt, schema)
    body = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.1,
            "responseMimeType": "application/json",
            "responseSchema": schema,
            "maxOutputTokens": 400,
        },
    }
    try:
        async with httpx.AsyncClient(timeout=s.llm_timeout_seconds) as client:
            r = await client.post(
                GEMINI_URL.format(model=s.gemini_model),
                params={"key": s.gemini_api_key},
                json=body,
            )
        if r.status_code != 200:
            log.warning("gemini status %s", r.status_code)
            return None
        data = r.json()
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        return json.loads(text)
    except (httpx.HTTPError, KeyError, IndexError, ValueError) as exc:
        log.warning("gemini call failed: %s", type(exc).__name__)
        return None


async def _guarded(user_id: str, purpose: str, prompt: str, schema: dict) -> dict | None:
    if not llm_available():
        return None
    s = get_settings()
    if not limiter.allow(f"llm:{user_id}", s.llm_rate_per_minute):
        log.info("llm rate limit hit for user")
        return None
    key = hashlib.sha256(f"{purpose}|{prompt}".encode()).hexdigest()
    cached = _cache.get(key)
    if cached is not None:
        return cached
    out = await _call_gemini(prompt, schema)
    if out is not None:
        _cache.put(key, out)
    return out


INTENT_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "workflow_id": {"type": "STRING", "nullable": True},
        "contact": {"type": "STRING", "nullable": True},
        "destination": {"type": "STRING", "nullable": True},
        "confidence": {"type": "NUMBER"},
        "explanation_en": {"type": "STRING"},
        "explanation_ur": {"type": "STRING"},
    },
    "required": ["workflow_id", "confidence", "explanation_en", "explanation_ur"],
}

SCAM_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "verdict": {"type": "STRING", "enum": ["likely_scam", "be_careful", "probably_fine"]},
        "confidence": {"type": "NUMBER"},
        "reason_en": {"type": "STRING"},
        "reason_ur": {"type": "STRING"},
    },
    "required": ["verdict", "confidence", "reason_en", "reason_ur"],
}


async def parse_intent(user_id: str, transcript: str, workflows: dict[str, str]) -> IntentLLMOut | None:
    catalog = "\n".join(f"- {wid}: {desc}" for wid, desc in workflows.items())
    prompt = (
        "You help an older person use their Android phone. Their words may be Urdu, Roman Urdu or English.\n"
        "Choose ONE workflow id from this list, or null if none fits. Never invent ids. Never output actions.\n"
        f"{catalog}\n\n"
        "Extract `contact` (who to call/message, e.g. 'son', 'Ali') and `destination` (a place) if present.\n"
        "Write explanation_en and explanation_ur: ONE short, kind sentence (max 15 words) telling the person "
        "what you will help them do. No numbers, no links.\n"
        f'Person said: "{redact(transcript)}"'
    )
    raw = await _guarded(user_id, "intent", prompt, INTENT_SCHEMA)
    if raw is None:
        return None
    try:
        return IntentLLMOut.model_validate(raw)
    except ValidationError:
        log.info("intent llm output failed validation")
        return None


async def classify_scam(user_id: str, redacted_text: str) -> ScamLLMOut | None:
    prompt = (
        "Classify this phone message (Urdu, Roman Urdu or English) for an older person in Pakistan.\n"
        "verdict: likely_scam, be_careful or probably_fine. Never claim certainty.\n"
        "reason_en / reason_ur: ONE plain sentence (max 20 words) explaining the main warning sign, "
        "or why it looks normal. Personal data was replaced by tokens like [PHONE].\n"
        f'Message: """{redact(redacted_text)}"""'
    )
    raw = await _guarded(user_id, "scam", prompt, SCAM_SCHEMA)
    if raw is None:
        return None
    try:
        return ScamLLMOut.model_validate(raw)
    except ValidationError:
        log.info("scam llm output failed validation")
        return None
