"""Rule-based scam detection. English, Roman Urdu and Urdu script.

Runs first, with no network. Gemini is only consulted when rules are
inconclusive (see services/scam_service.py).
"""

import re
from dataclasses import dataclass, field

LIKELY_SCAM, BE_CAREFUL, PROBABLY_FINE = "likely_scam", "be_careful", "probably_fine"
LEVEL_ORDER = {PROBABLY_FINE: 0, BE_CAREFUL: 1, LIKELY_SCAM: 2}

OFFICIAL_DOMAINS = {
    "hbl.com", "meezanbank.com", "ubldigital.com", "mcb.com.pk", "bankalfalah.com",
    "jazzcash.com.pk", "easypaisa.com.pk", "bisp.gov.pk", "nadra.gov.pk", "fbr.gov.pk",
    "sbp.org.pk", "pta.gov.pk", "gov.pk",
}
SHORTENERS = {"bit.ly", "tinyurl.com", "goo.gl", "cutt.ly", "t.me", "wa.link", "rb.gy", "is.gd", "shorturl.at"}
BAD_TLDS = {"xyz", "top", "click", "info", "online", "site", "live", "buzz", "icu", "shop", "cfd", "sbs"}

URL_RE = re.compile(
    r"((https?://|www\.)\S+|\b([a-z0-9-]+\.)+(com|pk|net|org|info|xyz|top|click|online|site|live|ly|me|gl|gd|at|link|buzz|icu|shop|cfd|sbs|io|co)\b(/\S*)?)",
    re.IGNORECASE,
)
CLAIMS_OFFICIAL_RE = re.compile(
    r"\b(hbl|meezan|ubl|mcb|alfalah|jazz ?cash|easy ?paisa|bisp|benazir|ehsaas|nadra|fbr|bank|state bank)\b|(بینک|جاز کیش|ایزی پیسہ|بینظیر|نادرا)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Rule:
    id: str
    weight: int
    patterns: tuple[str, ...]
    reason_ur: str
    reason_en: str
    action_ur: str
    action_en: str
    lesson_ur: str
    lesson_en: str


RULES: tuple[Rule, ...] = (
    Rule(
        "asks_code", 5,
        (r"\b(otp|one[\s-]?time|verification code|pin|password|passcode|cvv)\b",
         r"\bcode\s+(bhej|send|share|bata|btaa?)", r"(کوڈ|پن کوڈ|پاس ورڈ|خفیہ نمبر)"),
        "یہ آپ سے کوڈ، پن یا پاس ورڈ مانگ رہا ہے۔", "It asks for a code, PIN or password.",
        "کوڈ کسی کو نہ بتائیں۔ بینک اور حکومت کبھی کوڈ نہیں مانگتے۔",
        "Do not share the code. Banks and the government never ask for it.",
        "کوڈ = چابی۔ اپنی چابی کسی کو نہیں دیتے۔", "A code is like your house key. Never give it to anyone.",
    ),
    Rule(
        "personal_info", 3,
        (r"\b(cnic|id card|account (no|number)|card (no|number)|atm)\b", r"(شناختی کارڈ|اکاؤنٹ نمبر|کارڈ نمبر)"),
        "یہ آپ کا شناختی کارڈ یا اکاؤنٹ نمبر مانگ رہا ہے۔", "It asks for your ID card or account number.",
        "اپنی معلومات نہ بھیجیں۔ کارڈ کے پیچھے والے نمبر پر بینک کو فون کریں۔",
        "Do not send your details. Call your bank using the number on the back of your card.",
        "ذاتی معلومات صرف خود جا کر دیں، پیغام میں کبھی نہیں۔", "Give personal details only in person, never by message.",
    ),
    Rule(
        "prize", 3,
        (r"\b(won|winner|prize|lottery|lucky draw|congratulations|congrats|inaam|jeet\s?gay?e?)\b",
         r"(انعام|مبارک ہو|جیت گئے|جیت گئی|لکی ڈرا)"),
        "یہ کہہ رہا ہے کہ آپ نے انعام جیتا ہے۔", "It says you have won a prize.",
        "جواب نہ دیں اور لنک نہ کھولیں۔", "Do not reply and do not open the link.",
        "جس مقابلے میں حصہ نہیں لیا، اس کا انعام نہیں ملتا۔", "You cannot win a contest you never entered.",
    ),
    Rule(
        "asks_money", 3,
        (r"\b(processing fee|registration fee|delivery fee|send (money|rs|pkr|payment)|advance|transfer (rs|pkr|money))\b",
         r"\b(paise|paisay)\s+(bhej|send|jama)", r"(فیس|پیسے بھیج|رقم بھیج|جمع کروائیں)"),
        "یہ آپ سے پیسے یا فیس مانگ رہا ہے۔", "It asks you to pay money or a fee.",
        "پیسے نہ بھیجیں۔ اصلی امداد یا انعام کے لیے فیس نہیں لی جاتی۔",
        "Do not send money. Real aid or prizes never need a fee.",
        "پیسے لینے کے لیے پیسے دینے پڑیں تو یہ دھوکہ ہے۔", "If you must pay to receive money, it is a scam.",
    ),
    Rule(
        "urgency", 2,
        (r"\b(urgent|immediately|within 24|blocked?|suspend(ed)?|expire[sd]?|last chance|foran)\b",
         r"(فوراً|فوری|بند ہو جائے|بلاک|آخری موقع)"),
        "یہ آپ کو جلدی کرنے یا ڈرانے کی کوشش کر رہا ہے۔", "It tries to rush or scare you.",
        "جلدی نہ کریں۔ پہلے گھر والوں سے بات کریں۔", "Slow down. Talk to your family first.",
        "جو پیغام ڈرائے یا جلدی کروائے، اس پر رک جائیں۔", "If a message rushes or scares you, stop and wait.",
    ),
    Rule(
        "gov_aid", 2,
        (r"\b(bisp|benazir|ehsaas|kafaalat|nadra|fbr)\b", r"(بینظیر|احساس|کفالت|نادرا)"),
        "یہ سرکاری امداد (بی آئی ایس پی / احساس) کا نام استعمال کر رہا ہے۔",
        "It uses the name of government aid (BISP / Ehsaas).",
        "سرکاری امداد کی تصدیق صرف 8171 سروس سے کریں، کسی لنک سے نہیں۔",
        "Verify government aid only through the official 8171 service, never through a link.",
        "حکومت لنک بھیج کر پیسے نہیں دیتی۔", "The government does not pay through links.",
    ),
    Rule(
        "call_back", 1,
        (r"\b(call (this|on|us)|is number par)\b", r"(اس نمبر پر کال|فون کریں)"),
        "یہ آپ سے کسی نامعلوم نمبر پر فون کروانا چاہتا ہے۔", "It asks you to call an unknown number.",
        "نامعلوم نمبر پر فون نہ کریں۔", "Do not call unknown numbers.",
        "صرف وہ نمبر ملائیں جو آپ پہلے سے جانتی ہیں۔", "Only call numbers you already know.",
    ),
)
_COMPILED = [(r, [re.compile(p, re.IGNORECASE) for p in r.patterns]) for r in RULES]


@dataclass
class Reason:
    rule_id: str
    weight: int
    reason_ur: str
    reason_en: str


@dataclass
class RuleVerdict:
    level: str
    score: int
    reasons: list[Reason] = field(default_factory=list)
    action_ur: str = ""
    action_en: str = ""
    lesson_ur: str = ""
    lesson_en: str = ""
    has_link: bool = False

    @property
    def conclusive(self) -> bool:
        """True when rules alone are confident: clear scam, or nothing suspicious at all."""
        return self.level == LIKELY_SCAM or (self.score == 0 and not self.has_link)


def _domain(url: str) -> str:
    u = re.sub(r"^https?://", "", url.lower())
    u = u.split("/")[0].split("?")[0]
    return u[4:] if u.startswith("www.") else u


def _is_official(d: str) -> bool:
    return any(d == o or d.endswith("." + o) for o in OFFICIAL_DOMAINS)


def level_for(score: int) -> str:
    return LIKELY_SCAM if score >= 5 else BE_CAREFUL if score >= 2 else PROBABLY_FINE


def check(text: str) -> RuleVerdict:
    t = text.strip()
    hits = [r for r, pats in _COMPILED if any(p.search(t) for p in pats)]
    reasons = [Reason(r.id, r.weight, r.reason_ur, r.reason_en) for r in hits]

    domains = {
        d for d in (_domain(m.group(0)) for m in URL_RE.finditer(t))
        if "." in d and not re.fullmatch(r"\d+(\.\d+)*", d)
    }
    unofficial = {d for d in domains if not _is_official(d)}
    if unofficial:
        risky = {d for d in unofficial if d in SHORTENERS or d.rsplit(".", 1)[-1] in BAD_TLDS}
        if CLAIMS_OFFICIAL_RE.search(t):
            reasons.append(Reason("link_mismatch", 3,
                                  "یہ بینک یا حکومت کا نام لیتا ہے مگر لنک ان کا اصلی نہیں ہے۔",
                                  "It claims to be a bank or the government, but the link is not their real website."))
        elif risky:
            reasons.append(Reason("risky_link", 2, "اس میں چھپا ہوا یا مشکوک لنک ہے۔",
                                  "It contains a hidden or suspicious link."))
        else:
            reasons.append(Reason("has_link", 1, "اس میں ایک لنک ہے۔", "It contains a link."))

    reasons.sort(key=lambda r: r.weight, reverse=True)
    score = sum(r.weight for r in reasons)
    level = level_for(score)
    top = max(hits, key=lambda r: r.weight) if hits else None
    link_top = bool(reasons) and "link" in reasons[0].rule_id

    if level == PROBABLY_FINE:
        action_ur = "یہ عام پیغام لگتا ہے، پھر بھی کوڈ یا پیسے کبھی نہ بھیجیں۔"
        action_en = "This looks like a normal message, but never send codes or money."
    elif link_top or top is None:
        action_ur, action_en = "لنک نہ کھولیں اور جواب نہ دیں۔", "Do not open the link and do not reply."
    else:
        action_ur, action_en = top.action_ur, top.action_en

    return RuleVerdict(
        level=level,
        score=score,
        reasons=reasons,
        action_ur=action_ur,
        action_en=action_en,
        lesson_ur=top.lesson_ur if top else "اصلی ادارے لنک بھیج کر معلومات نہیں مانگتے۔",
        lesson_en=top.lesson_en if top else "Real organisations do not ask for details through links.",
        has_link=bool(domains),
    )


def redact(text: str) -> str:
    """Remove CNICs, emails, phone/account numbers and long digit runs before any AI call."""
    t = re.sub(r"\b\d{5}-\d{7}-\d\b", "[CNIC]", text)
    t = re.sub(r"[\w.+-]+@[\w-]+\.[\w.]+", "[EMAIL]", t)
    t = re.sub(r"\+?\d[\d\s-]{7,}\d", "[NUMBER]", t)
    return t
