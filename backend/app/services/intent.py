"""Natural-language intent understanding for voice / free text (F7, F8, F10).

1. Fast rule-based matcher (English, Roman Urdu, Urdu script) -> workflow + slots.
2. If no rule matches, Gemini maps the (redacted) transcript to ONE workflow id from the registry.
3. Low confidence -> no workflow; the app shows the task list instead.
The result is then passed to the Flow Engine, which is the only thing that can build steps.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

from app.core.config import get_settings
from app.services import llm
from app.services.flow_engine import workflow_catalog, workflows_by_id

# Ordered: first match wins (more specific first).
RULES: list[tuple[str, list[str]]] = [
    ("whatsapp_video_call", ["video call", "videocall", "video kal", "ویڈیو کال", "وڈیو کال", "ویڈیو"]),
    ("whatsapp_chat", ["whatsapp", "whats app", "watsapp", "watsap", "واٹس ایپ", "واٹس اپ", "وٹس ایپ"]),
    ("share_photo", ["send photo", "send a photo", "send the photo", "share photo", "share a photo", "send picture",
                     "photo bhej", "tasveer bhej", "tasweer bhej", "تصویر بھیج", "فوٹو بھیج"]),
    ("open_camera", ["camera", "take a photo", "take a picture", "take photo", "selfie", "photo khench", "tasveer khench",
                     "tasweer khench", "کیمرا", "کیمرہ", "تصویر کھینچ", "تصویر لے", "فوٹو کھینچ"]),
    ("open_photos", ["photos", "photo", "pictures", "picture", "gallery", "tasveer", "tasveerein", "tasweer", "tasaveer",
                     "تصویریں", "تصاویر", "تصویر", "فوٹو", "گیلری"]),
    ("wifi_on", ["wifi", "wi-fi", "wi fi", "wireless", "internet", "net nahi", "وائی فائی", "وائیفائی", "انٹرنیٹ", "نیٹ"]),
    ("bluetooth_on", ["bluetooth", "blue tooth", "بلوٹوتھ", "بلو ٹوتھ"]),
    ("sound_settings", ["volume", "sound", "louder", "quieter", "awaz", "awaaz", "آواز", "والیوم"]),
    ("display_settings", ["brightness", "brighter", "too dark", "screen is dark", "screen dark", "roshni", "روشنی", "اسکرین تاریک",
                          "سکرین"]),
    ("open_maps", ["map", "maps", "directions", "direction", "way to", "how do i get to", "navigate", "rasta", "raasta",
                   "راستہ", "نقشہ", "نقشے"]),
    ("scam_check", ["scam", "fraud", "fake", "is this real", "check this message", "check a message", "check message",
                    "dhoka", "dhoka", "farad", "دھوکہ", "دھوکا", "فراڈ", "جعلی", "پیغام چیک", "میسج چیک"]),
    ("call_contact", ["call", "phone", "ring", "dial", "kal karo", "fon", "کال", "فون", "ملاؤ", "ملائیں", "ملا دو"]),
    ("open_messages", ["message", "messages", "sms", "text", "msg", "paigham", "پیغام", "پیغامات", "میسج", "ایس ایم ایس"]),
    ("ask_family", ["help", "family", "madad", "ghar walon", "مدد", "گھر والوں", "گھر والے"]),
]

RELATIONS = {
    "son": ["son", "beta", "bete", "betay", "بیٹا", "بیٹے", "بیٹے کو"],
    "daughter": ["daughter", "beti", "بیٹی"],
    "family": ["family", "ghar", "گھر والوں", "گھر والے"],
    "doctor": ["doctor", "dr", "ڈاکٹر"],
    "wife": ["wife", "biwi", "begum", "بیوی", "بیگم"],
    "husband": ["husband", "shohar", "شوہر", "میاں"],
    "brother": ["brother", "bhai", "بھائی"],
    "sister": ["sister", "behen", "bahen", "بہن"],
}

_CONTACT_PATTERNS = [
    # Roman Urdu: "ali ko call karo", "bete ko phone milao"
    re.compile(r"\b([a-z]+(?:\s[a-z]+)?)\s+ko\s+(?:call|phone|fon|kal|message|msg|video|whatsapp)", re.I),
    # Urdu script: "علی کو فون کرو", "بیٹے کو کال کریں"
    re.compile(r"(\S+(?:\s\S+)?)\s+کو\s+(?:کال|فون|پیغام|میسج|ویڈیو|واٹس)"),
    # English: "call my son", "call Ali", "message to my daughter", "whatsapp ali", "video call my son"
    re.compile(r"\b(?:call|phone|ring|dial|message|text|whatsapp|sms)\s+(?:to\s+)?(?:my\s+)?([a-z][a-z ]{0,30}?)(?:\s+(?:on|please|now|for)\b|[.?!,]|$)", re.I),
    re.compile(r"\b(?:to|with)\s+my\s+([a-z]+)\b", re.I),
]
_DEST_PATTERNS = [
    re.compile(r"\b(?:way to|directions to|get to|go to|navigate to)\s+(?:the\s+)?([\w ]{2,60})", re.I),
    re.compile(r"\b([a-z ]{2,40}?)\s+(?:ka|ki)\s+(?:rasta|raasta)", re.I),
    re.compile(r"(\S+(?:\s\S+)?)\s+(?:کا|کی)\s+راستہ"),
]
_STOP_CONTACT = {"a", "the", "me", "someone", "somebody", "now", "please", "message", "photo", "video", "my", "him", "her",
                 "کسی", "مجھے", "karo", "kar", "do", "karein", "kardo", "milao", "lagao", "on", "off",
                 "میرے", "میری"}


@dataclass
class IntentResult:
    workflow_id: str | None
    slots: dict = field(default_factory=dict)
    confidence: float = 0.0
    source: str = "none"  # rules | llm | none
    explanation: dict | None = None


def _norm(text: str) -> str:
    t = unicodedata.normalize("NFKC", text or "").lower()
    return re.sub(r"\s+", " ", t).strip()


def _contains(text: str, kw: str) -> bool:
    if re.match(r"^[a-z0-9 \-]+$", kw):
        return re.search(rf"(?<![a-z]){re.escape(kw)}(?![a-z])", text) is not None
    return kw in text


def extract_contact(text: str) -> tuple[str | None, str | None]:
    raw = None
    for p in _CONTACT_PATTERNS:
        m = p.search(text)
        if m:
            cand = m.group(1).strip(" .?!,")
            words = [w for w in cand.split() if w not in _STOP_CONTACT]
            if words:
                raw = " ".join(words)[:40]
                break
    relation = None
    hay = f" {raw or text} "
    for rel, words in RELATIONS.items():
        if any(_contains(hay, w) for w in words):
            relation = rel
            break
    if raw and relation and raw in RELATIONS[relation]:
        raw = relation
    return raw, relation


def extract_destination(text: str) -> str | None:
    for p in _DEST_PATTERNS:
        m = p.search(text)
        if m:
            return m.group(1).strip(" .?!,")[:80] or None
    return None


def match_rules(transcript: str) -> IntentResult:
    text = _norm(transcript)
    if not text:
        return IntentResult(None)
    for wid, keywords in RULES:
        if any(_contains(text, kw) for kw in keywords):
            slots: dict = {}
            spec = workflows_by_id()[wid].get("slots", {})
            if "contact" in spec:
                contact, relation = extract_contact(text)
                if contact:
                    slots["contact"] = contact
                if relation:
                    slots["relation"] = relation
            if "destination" in spec:
                dest = extract_destination(text)
                if dest:
                    slots["destination"] = dest
            return IntentResult(wid, slots, 0.9, "rules")
    return IntentResult(None)


async def understand(user_id: str, transcript: str) -> IntentResult:
    result = match_rules(transcript)
    if result.workflow_id:
        return result
    out = await llm.parse_intent(user_id, transcript, workflow_catalog())
    if out is None:
        return IntentResult(None, source="none")
    if not out.workflow_id or out.workflow_id not in workflows_by_id():
        return IntentResult(None, confidence=out.confidence, source="llm")
    if out.confidence < get_settings().llm_min_confidence:
        return IntentResult(None, confidence=out.confidence, source="llm")
    slots = {k: v for k, v in (("contact", out.contact), ("destination", out.destination)) if v}
    return IntentResult(
        out.workflow_id,
        slots,
        out.confidence,
        "llm",
        {"en": out.explanation_en, "ur": out.explanation_ur},
    )
