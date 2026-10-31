"""Privacy redaction applied before ANY text leaves the backend for an LLM (F6, F8, §9).

Removes phone numbers, CNIC/ID numbers, IBAN/account/card numbers, e-mail addresses,
one-time codes and names that follow a salutation (English, Roman Urdu and Urdu script).
"""
from __future__ import annotations

import re

_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("[EMAIL]", re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")),
    ("[IBAN]", re.compile(r"\bPK\d{2}[A-Z]{4}\d{16}\b", re.I)),
    ("[CNIC]", re.compile(r"\b\d{5}-?\d{7}-?\d\b")),
    ("[CARD]", re.compile(r"\b(?:\d[ -]?){13,19}\b")),
    ("[PHONE]", re.compile(r"(?:\+?92[\s-]?|0)3\d{2}[\s-]?\d{7}\b")),
    ("[PHONE]", re.compile(r"\+\d[\d\s-]{7,15}\d")),
    ("[ACCOUNT]", re.compile(r"\b\d{8,}\b")),
    ("[CODE]", re.compile(r"\b\d{4,7}\b")),
]

# Names after salutations. Captures 1-2 following words.
_NAME_EN = re.compile(
    r"\b(Dear|Hi|Hello|Mr\.?|Mrs\.?|Ms\.?|Miss|Sir|Madam|Janab|Mohtaram|Mohtarma|Bhai|Baji|Sahib)\s+"
    r"([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)"
)
_NAME_UR = re.compile(r"(محترم|محترمہ|جناب|پیارے|عزیز)\s+(\S+(?:\s+(?!صاحب)\S+)?)")
_NAME_FROM = re.compile(r"\b(this is|I am|I'm|main|mein)\s+([A-Z][a-z]+)\b")
# Explicit person names right after a call/message verb in voice transcripts ("call Ali").
_NAME_CALL = re.compile(r"\b(call|phone|ring|message|text|whatsapp)\s+([A-Z][a-z]+)\b")


def redact(text: str) -> str:
    if not text:
        return ""
    out = text
    out = _NAME_EN.sub(lambda m: f"{m.group(1)} [NAME]", out)
    out = _NAME_UR.sub(lambda m: f"{m.group(1)} [NAME]", out)
    out = _NAME_FROM.sub(lambda m: f"{m.group(1)} [NAME]", out)
    out = _NAME_CALL.sub(lambda m: f"{m.group(1)} [NAME]", out)
    for token, pattern in _PATTERNS:
        out = pattern.sub(token, out)
    return out[:4000]
