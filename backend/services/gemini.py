"""Gemini gateway (backend only).

Rules:
- Only ever called with REDACTED text.
- Output must be JSON matching a Pydantic schema; anything else is discarded.
- Gemini can only *classify* (scam level / intent id from an allowlist).
  It never returns or triggers device actions.
- Any failure (no key, timeout, quota, bad JSON) returns None and callers
  fall back to rules.
"""

import json
import logging
from typing import Literal, TypeVar

import httpx
from pydantic import BaseModel, Field, ValidationError

from core.config import get_settings

log = logging.getLogger("companion.gemini")
T = TypeVar("T", bound=BaseModel)

API_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


class GeminiScamResult(BaseModel):
    level: Literal["probably_fine", "be_careful", "likely_scam"]
    confidence: float = Field(ge=0, le=1)
    reason_en: str = Field(max_length=300)
    reason_ur: str = Field(max_length=300)


class GeminiIntentResult(BaseModel):
    task_id: str | None
    confidence: float = Field(ge=0, le=1)
    explanation_ur: str = Field(default="", max_length=300)


async def generate_json(prompt: str, schema: dict, model_cls: type[T]) -> T | None:
    s = get_settings()
    if not s.gemini_enabled:
        return None
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
        async with httpx.AsyncClient(timeout=s.gemini_timeout_seconds) as client:
            r = await client.post(
                API_URL.format(model=s.gemini_model),
                headers={"x-goog-api-key": s.gemini_api_key or ""},
                json=body,
            )
        if r.status_code != 200:
            log.warning("gemini http %s: %s", r.status_code, r.text[:200])
            return None
        text = r.json()["candidates"][0]["content"]["parts"][0]["text"]
        return model_cls.model_validate(json.loads(text))
    except (httpx.HTTPError, KeyError, IndexError, json.JSONDecodeError, ValidationError, TypeError) as e:
        log.warning("gemini call failed or invalid output: %s", e)
        return None


SCAM_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "level": {"type": "STRING", "enum": ["probably_fine", "be_careful", "likely_scam"]},
        "confidence": {"type": "NUMBER"},
        "reason_en": {"type": "STRING"},
        "reason_ur": {"type": "STRING"},
    },
    "required": ["level", "confidence", "reason_en", "reason_ur"],
}


async def classify_scam(redacted_text: str) -> GeminiScamResult | None:
    prompt = (
        "You help elderly people in Pakistan spot scam SMS/WhatsApp messages. "
        "Classify the message below. Be cautious, never claim certainty. "
        "reason_en: one short plain-English sentence. reason_ur: the same in simple Urdu. "
        "Numbers and names have been replaced with placeholders.\n\nMESSAGE:\n"
        f"<<<{redacted_text[:2000]}>>>"
    )
    return await generate_json(prompt, SCAM_SCHEMA, GeminiScamResult)


async def classify_intent(transcript: str, allowed: dict[str, str]) -> GeminiIntentResult | None:
    ids = list(allowed.keys())
    schema = {
        "type": "OBJECT",
        "properties": {
            "task_id": {"type": "STRING", "enum": ids + ["none"]},
            "confidence": {"type": "NUMBER"},
            "explanation_ur": {"type": "STRING"},
        },
        "required": ["task_id", "confidence", "explanation_ur"],
    }
    menu = "\n".join(f"- {k}: {v}" for k, v in allowed.items())
    prompt = (
        "An elderly user spoke a request (Urdu, Roman Urdu or English). Pick the ONE task id "
        "from this list that matches, or 'none' if nothing matches. Do not invent ids.\n"
        f"{menu}\n\nREQUEST: <<<{transcript[:500]}>>>\n"
        "explanation_ur: one short, kind Urdu sentence saying what you understood."
    )
    res = await generate_json(prompt, schema, GeminiIntentResult)
    if res is None:
        return None
    if res.task_id in (None, "none") or res.task_id not in allowed:  # allowlist check
        res.task_id = None
    return res
