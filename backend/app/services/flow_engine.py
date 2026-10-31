"""Deterministic Flow Engine (F10, core feature).

The LLM may only *name* a workflow and suggest typed slot values. This engine:
  1. rejects any workflow id that is not in workflows.json,
  2. validates slots (known name, type, length, character set),
  3. applies the sensitive-topic denylist (banking, payments, passwords, OTP, installs...),
  4. builds steps ONLY from the predefined template (the LLM never writes steps/actions),
  5. enforces limits (<= max_steps, timeout) and allowed action kinds/intents,
  6. sanitises any LLM-written explanation (no links, no digits, length cap).
"""
from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

from app.services.i18n import SUPPORTED_LANGS, both, lang_or_default

WORKFLOWS_PATH = Path(__file__).resolve().parent.parent / "flows" / "workflows.json"

ALLOWED_ACTION_KINDS = {"open_intent", "external_hint", "in_app_route", "in_app_hint"}
ALLOWED_COMPLETIONS = {"intent_launched", "returned_to_app", "user_confirm", "screen_reached", "tap_target"}
ALLOWED_SLOT_PARAMS = {"contact", "destination", "helper"}  # "helper" is resolved on-device only
ALLOWED_RELATIONS = {"son", "daughter", "family", "doctor", "wife", "husband", "brother", "sister"}

# Secret/credential topics: always refused.
SECRET_TERMS = [
    "otp", "one time password", "password", "passcode", "pin code", "pin number", "cvv",
    "پاس ورڈ", "او ٹی پی", "پن کوڈ", "خفیہ کوڈ",
    "pass word",
]
# Money / sensitive apps / installs / security: refused unless the workflow is a plain phone call
# (calling your bank is exactly what the scam helper recommends).
MONEY_TERMS = [
    "bank app", "banking", "mobile banking", "jazzcash", "jazz cash", "easypaisa", "easy paisa", "sadapay",
    "nayapay", "raast", "payment", "pay bill", "pay the bill", "transfer money", "send money", "money transfer",
    "paise bhej", "paisay bhej", "pese bhej", "install", "download app", "purchase", "buy ", "credit card",
    "security setting", "screen lock", "lock screen", "fingerprint", "factory reset",
    "بینک ایپ", "بینکنگ", "جاز کیش", "ایزی پیسہ", "ادائیگی", "پیسے بھیج", "رقم بھیج", "انسٹال", "خرید",
    "بل جمع", "اسکرین لاک", "فنگر پرنٹ",
]
BANK_WORDS = ["bank", "بینک"]

_SLOT_CHARS = re.compile(r"^[\w\s.'\-؀-ۿ]+$", re.UNICODE)
_URL = re.compile(r"(https?://\S+|www\.\S+|\S+\.(com|pk|net|org|io|xyz)\S*)", re.I)
_DIGITS = re.compile(r"\d{3,}")


class FlowError(ValueError):
    pass


@dataclass
class PlanRequest:
    workflow_id: str | None
    slots: dict = field(default_factory=dict)
    utterance: str = ""
    explanation: dict | None = None  # {"en":..., "ur":...} from the LLM (optional)
    language: str = "ur"
    source: str = "direct"  # direct | rules | llm


@lru_cache
def load_registry() -> dict:
    data = json.loads(WORKFLOWS_PATH.read_text(encoding="utf-8"))
    validate_registry(data)
    return data


def workflows_by_id() -> dict[str, dict]:
    return {w["id"]: w for w in load_registry()["workflows"]}


def workflow_catalog() -> dict[str, str]:
    """id -> short English description (for the LLM prompt)."""
    return {w["id"]: w["title"]["en"] for w in load_registry()["workflows"]}


def validate_registry(data: dict) -> None:
    """Fail fast at startup if workflows.json contains anything outside the allow-lists."""
    limits = data["limits"]
    intents = set(data["allowed_intents"])
    routes = set(data["allowed_in_app_routes"])
    seen = set()
    for w in data["workflows"]:
        wid = w["id"]
        if wid in seen:
            raise FlowError(f"duplicate workflow {wid}")
        seen.add(wid)
        for lang in SUPPORTED_LANGS:
            if lang not in w["title"] or lang not in w["intro_default"]:
                raise FlowError(f"{wid}: missing {lang} title/intro")
        if not 1 <= len(w["steps"]) <= limits["max_steps"]:
            raise FlowError(f"{wid}: step count out of range")
        for s in w["steps"]:
            a = s["action"]
            if a["kind"] not in ALLOWED_ACTION_KINDS:
                raise FlowError(f"{wid}/{s['id']}: action kind {a['kind']} not allowed")
            if a["kind"] == "open_intent" and a["intent"] not in intents:
                raise FlowError(f"{wid}/{s['id']}: intent {a['intent']} not allowed")
            if a["kind"] == "in_app_route" and a["route"] not in routes:
                raise FlowError(f"{wid}/{s['id']}: route not allowed")
            for p in a.get("params", []):
                if p not in ALLOWED_SLOT_PARAMS:
                    raise FlowError(f"{wid}/{s['id']}: param {p} not allowed")
            if s["completion"]["type"] not in ALLOWED_COMPLETIONS:
                raise FlowError(f"{wid}/{s['id']}: completion not allowed")
            h = s["highlight"]
            for k in ("x", "y", "w", "h"):
                if not 0 <= h[k] <= 1:
                    raise FlowError(f"{wid}/{s['id']}: highlight out of bounds")
            if s["arrow"] not in ("up", "down", "left", "right"):
                raise FlowError(f"{wid}/{s['id']}: bad arrow")
            for lang in SUPPORTED_LANGS:
                if lang not in s["hint"]:
                    raise FlowError(f"{wid}/{s['id']}: missing {lang} hint")


def _norm(text: str) -> str:
    return unicodedata.normalize("NFKC", text or "").lower()


def is_sensitive(utterance: str, workflow_id: str | None, slots: dict) -> bool:
    blob = _norm(" ".join([utterance or ""] + [str(v) for v in slots.values()]))
    if any(term in blob for term in SECRET_TERMS):
        return True
    if any(term in blob for term in MONEY_TERMS):
        return True
    # "open my bank" etc. -> refused; "call my bank" -> allowed (plain phone call).
    if workflow_id != "call_contact" and any(b in blob for b in BANK_WORDS):
        return True
    return False


def clean_slot(value, spec: dict) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise FlowError("slot must be text")
    v = unicodedata.normalize("NFKC", value).strip()
    v = re.sub(r"\s+", " ", v)
    if not v:
        return None
    if len(v) > spec.get("max_len", 40):
        raise FlowError("slot too long")
    if not _SLOT_CHARS.match(v):
        raise FlowError("slot has disallowed characters")
    if _URL.search(v):
        raise FlowError("slot may not contain links")
    return v


def sanitize_explanation(text: str | None, limit: int = 160) -> str | None:
    if not text:
        return None
    t = "".join(ch for ch in text if unicodedata.category(ch)[0] != "C")
    t = _URL.sub("", t)
    t = _DIGITS.sub("", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t[:limit] or None


RELATION_LABELS = {
    "son": {"en": "your son", "ur": "اپنے بیٹے"},
    "daughter": {"en": "your daughter", "ur": "اپنی بیٹی"},
    "family": {"en": "your family", "ur": "اپنے گھر والوں"},
    "doctor": {"en": "your doctor", "ur": "اپنے ڈاکٹر"},
    "wife": {"en": "your wife", "ur": "اپنی بیگم"},
    "husband": {"en": "your husband", "ur": "اپنے شوہر"},
    "brother": {"en": "your brother", "ur": "اپنے بھائی"},
    "sister": {"en": "your sister", "ur": "اپنی بہن"},
}


def _display_slots(slots: dict, lang: str) -> dict:
    out = dict(slots)
    contact = slots.get("contact")
    if contact and contact in RELATION_LABELS:
        out["contact"] = RELATION_LABELS[contact][lang]
    elif not contact and slots.get("relation") in RELATION_LABELS:
        out["contact"] = RELATION_LABELS[slots["relation"]][lang]
    return out


def _fmt(template: dict, slots: dict) -> dict:
    out = {}
    for lang in SUPPORTED_LANGS:
        try:
            out[lang] = template[lang].format(**_display_slots(slots, lang))
        except KeyError:
            return {}
    return out


def build_plan(req: PlanRequest) -> dict:
    registry = load_registry()
    lang = lang_or_default(req.language)
    wf = workflows_by_id().get(req.workflow_id or "")
    if wf is None:
        raise FlowError("unknown_workflow")

    # 2. slots: drop unknown names silently, validate known ones.
    slots: dict[str, str] = {}
    for name, spec in wf.get("slots", {}).items():
        cleaned = clean_slot(req.slots.get(name), spec)
        if cleaned:
            slots[name] = cleaned
    # Canonical relation ("son", "daughter"...) lets the phone resolve the contact locally.
    if "contact" in wf.get("slots", {}) and req.slots.get("relation") in ALLOWED_RELATIONS:
        slots["relation"] = req.slots["relation"]

    # 3. denylist
    if is_sensitive(req.utterance, wf["id"], slots):
        return refused_plan("sensitive", lang)

    # 4. steps from template only
    steps = []
    for i, s in enumerate(wf["steps"]):
        hint = _fmt(s["hint"], slots) if slots or "{" not in s["hint"]["en"] else {}
        if not hint:
            hint = dict(s.get("hint_default") or s["hint"])
        action = {k: v for k, v in s["action"].items()}
        if "params" in action:
            action["params"] = {p: slots.get(p) for p in action["params"]}
            if "helper" in action["params"]:
                action["params"]["helper"] = "__device_helper__"  # resolved on the phone
        steps.append({
            "index": i,
            "id": s["id"],
            "screen": s["screen"],
            "target": s["target"],
            "highlight": s["highlight"],
            "arrow": s["arrow"],
            "hint": hint,
            "text": hint[lang],
            "action": action,
            "completion": s["completion"],
        })

    # 5. limits
    limits = registry["limits"]
    if len(steps) > limits["max_steps"]:
        raise FlowError("too_many_steps")

    # 6. explanation: LLM text sanitised, else template
    intro = None
    if req.explanation:
        en = sanitize_explanation(req.explanation.get("en"))
        ur = sanitize_explanation(req.explanation.get("ur"))
        if en and ur:
            intro = {"en": en, "ur": ur}
    if intro is None:
        intro = (_fmt(wf["intro"], slots) if "intro" in wf and slots else {}) or dict(wf["intro_default"])

    return {
        "status": "ok",
        "workflow_id": wf["id"],
        "task": wf["task"],
        "title": wf["title"],
        "intro": intro,
        "text": intro[lang],
        "slots": slots,
        "steps": steps,
        "total_steps": len(steps),
        "tier2_skill": wf.get("tier2_skill"),
        "limits": limits,
        "done": both("nav.done"),
        "source": req.source,
    }


def refused_plan(reason: str, lang: str) -> dict:
    from app.services.tasks import HOME_TILES, task_view

    msg = both("nav.refused.sensitive" if reason == "sensitive" else "nav.refused.unknown")
    return {
        "status": "refused",
        "reason": reason,
        "message": msg,
        "text": msg[lang_or_default(lang)],
        "steps": [],
        "fallback_tasks": [task_view(t, lang) for t in HOME_TILES],
    }
