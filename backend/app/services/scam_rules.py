"""Rule-based scam detection (F6) for English, Roman Urdu and Urdu script.

Pipeline: rules -> (if inconclusive) Gemini on redacted text -> 3-level verdict with ONE
plain-language reason and ONE recommended action, always hedged + "ask your family".
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from urllib.parse import urlsplit

from app.services.i18n import both, lang_or_default

# ---------- pattern lists ----------
REQUEST_VERBS = [
    "share", "send", "tell", "give", "reply with", "provide", "forward", "enter", "confirm", "verify", "update",
    "bhejein", "bhejain", "bhejo", "bhej do", "batayen", "batain", "batao", "bata dein", "dein", "de dein",
    "بھیجیں", "بھیجو", "بتائیں", "بتاؤ", "دیں", "فراہم کریں", "شیئر کریں", "تصدیق کریں",
]
SECRET_WORDS = [
    "otp", "one time password", "one-time password", "verification code", "security code", "pin", "password",
    "cvv", "code", "passcode", "کوڈ", "پن", "پاس ورڈ", "او ٹی پی",
]
SAFE_OTP_NOTICE = [
    "do not share", "don't share", "never share", "dont share", "do not disclose", "kisi ko na", "kisi ko mat",
    "کسی کو نہ", "کسی سے شیئر نہ", "شیئر نہ کریں",
]
INFO_WORDS = [
    "cnic", "id card", "identity card", "account number", "card number", "atm card", "debit card", "credit card",
    "bank details", "account details", "shanakhti", "شناختی کارڈ", "اکاؤنٹ نمبر", "کارڈ نمبر", "اے ٹی ایم",
    "بینک کی تفصیل",
]
URGENCY_WORDS = [
    "urgent", "immediately", "within 24 hours", "within 2 hours", "today only", "last warning", "final warning",
    "blocked", "will be blocked", "suspended", "deactivated", "will be closed", "legal action", "arrest", "fir ",
    "penalty", "act now", "expire today", "foran", "fori", "band ho jayega", "block ho jayega", "warna",
    "فوری", "فوراً", "بند کر دیا جائے", "بند ہو جائے", "بلاک", "معطل", "گرفتار", "قانونی کارروائی", "آخری موقع", "ورنہ",
]
PRIZE_WORDS = [
    "you have won", "you won", "winner", "lottery", "lucky draw", "prize", "jackpot", "congratulations! you",
    "congratulations you", "selected for", "cash reward", "free gift", "inaam", "inam", "jeet", "qurandazi",
    "انعام", "لاٹری", "قرعہ اندازی", "جیت لیا", "جیت گئے", "مبارک ہو! آپ", "مبارک ہو آپ", "آپ کا نام نکل",
]
PAYMENT_WORDS = [
    "send money", "transfer", "gift card", "processing fee", "registration fee", "delivery fee", "pay now",
    "pay the fee", "advance fee", "deposit", "send rs", "send pkr", "easypaisa", "jazzcash", "paise bhej",
    "paisay bhej", "pese bhej", "raqam bhej", "fees", "fee ", "پیسے بھیج", "رقم بھیج", "فیس", "جمع کروائیں",
    "ٹرانسفر", "ایزی پیسہ", "جاز کیش", "گفٹ کارڈ", "روپے بھیج",
]
NEW_NUMBER_WORDS = [
    "my new number", "this is my new number", "changed my number", "new number", "mera naya number",
    "naya number", "میرا نیا نمبر", "نیا نمبر",
]
TROUBLE_WORDS = ["in trouble", "emergency", "accident", "hospital", "police station", "musibat", "مصیبت", "ایمرجنسی",
                 "حادثہ", "ہسپتال", "تھانے"]
CLICK_WORDS = ["click here", "click the link", "tap the link", "link par click", "link pe click", "لنک پر کلک",
               "لنک کھولیں"]

# Brands / offices that are commonly impersonated, with their official domains.
BRANDS: dict[str, dict] = {
    "hbl": {"words": ["hbl", "habib bank"], "domains": ["hbl.com"]},
    "ubl": {"words": ["ubl", "united bank"], "domains": ["ubldigital.com", "ubl.com.pk"]},
    "mcb": {"words": ["mcb"], "domains": ["mcb.com.pk"]},
    "meezan": {"words": ["meezan"], "domains": ["meezanbank.com"]},
    "allied": {"words": ["allied bank", "abl"], "domains": ["abl.com"]},
    "sbp": {"words": ["state bank", "sbp", "اسٹیٹ بینک"], "domains": ["sbp.org.pk"]},
    "nadra": {"words": ["nadra", "نادرا"], "domains": ["nadra.gov.pk"]},
    "fbr": {"words": ["fbr", "ایف بی آر"], "domains": ["fbr.gov.pk"]},
    "pta": {"words": ["pta", "پی ٹی اے"], "domains": ["pta.gov.pk"]},
    "bisp": {"words": ["bisp", "benazir", "ehsaas", "احساس", "بینظیر", "بے نظیر"], "domains": ["bisp.gov.pk", "ehsaas.gov.pk"]},
    "police": {"words": ["fia", "police", "ایف آئی اے", "پولیس"], "domains": ["fia.gov.pk", "punjabpolice.gov.pk"]},
    "jazzcash": {"words": ["jazzcash", "jazz cash", "جاز کیش"], "domains": ["jazzcash.com.pk"]},
    "easypaisa": {"words": ["easypaisa", "easy paisa", "ایزی پیسہ"], "domains": ["easypaisa.com.pk"]},
    "jazz": {"words": ["jazz", "جاز"], "domains": ["jazz.com.pk"]},
    "telenor": {"words": ["telenor", "ٹیلی نار"], "domains": ["telenor.com.pk"]},
    "zong": {"words": ["zong", "زونگ"], "domains": ["zong.com.pk"]},
    "daraz": {"words": ["daraz"], "domains": ["daraz.pk"]},
    "amazon": {"words": ["amazon"], "domains": ["amazon.com", "amazon.ae"]},
    "bank": {"words": ["bank", "بینک"], "domains": []},
}
SHORTENERS = {"bit.ly", "tinyurl.com", "t.co", "goo.gl", "cutt.ly", "is.gd", "rb.gy", "shorturl.at", "tiny.cc", "ow.ly",
              "rebrand.ly", "s.id", "t.ly", "wa.link"}
SUSPICIOUS_TLDS = (".xyz", ".top", ".club", ".info", ".icu", ".live", ".online", ".site", ".click", ".buzz", ".rest",
                   ".shop", ".monster", ".cfd", ".sbs")
URL_RE = re.compile(r"(?:https?://|www\.)[^\s<>\"']+|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|pk|net|org|info|xyz|top|"
                    r"club|icu|live|online|site|click|ly|gd|at|cc|io|me|buzz|shop|cfd|sbs)(?:/[^\s]*)?", re.I)

WEIGHTS = {
    "otp_request": 0.65,
    "payment_request": 0.5,
    "prize_claim": 0.45,
    "info_request": 0.45,
    "link_mismatch": 0.45,
    "suspicious_link": 0.35,
    "urgency_threat": 0.3,
    "new_number": 0.3,
    "impersonation": 0.2,
    "contains_link": 0.1,
}
STRONG = {"otp_request", "payment_request", "prize_claim", "info_request", "link_mismatch"}
LIKELY_THRESHOLD = 0.6
CAREFUL_THRESHOLD = 0.3


@dataclass
class RuleResult:
    score: float
    flags: list[str] = field(default_factory=list)
    brands: list[str] = field(default_factory=list)
    urls: list[str] = field(default_factory=list)

    @property
    def verdict(self) -> str:
        return verdict_for(self.score)


def verdict_for(score: float) -> str:
    if score >= LIKELY_THRESHOLD:
        return "likely_scam"
    if score >= CAREFUL_THRESHOLD:
        return "be_careful"
    return "probably_fine"


def _norm(text: str) -> str:
    t = unicodedata.normalize("NFKC", text or "").lower()
    return re.sub(r"\s+", " ", t)


def _has(text: str, words: list[str]) -> bool:
    for w in words:
        if re.match(r"^[a-z0-9 .!'\-]+$", w.strip()):
            if re.search(rf"(?<![a-z0-9]){re.escape(w.strip())}(?![a-z0-9])", text):
                return True
        elif w in text:
            return True
    return False


def _near(text: str, a: list[str], b: list[str], window: int = 60) -> bool:
    """True if a word from `a` and a word from `b` occur within `window` characters."""
    def positions(words):
        pos = []
        for w in words:
            w = w.strip()
            if re.match(r"^[a-z0-9 .'\-]+$", w):
                pos += [m.start() for m in re.finditer(rf"(?<![a-z0-9]){re.escape(w)}(?![a-z0-9])", text)]
            else:
                pos += [m.start() for m in re.finditer(re.escape(w), text)]
        return pos

    pa, pb = positions(a), positions(b)
    return any(abs(x - y) <= window for x in pa for y in pb)


def _domain(url: str) -> str:
    u = url if "://" in url else "http://" + url
    host = (urlsplit(u).hostname or "").lower()
    return host[4:] if host.startswith("www.") else host


def _domain_matches(host: str, domains: list[str]) -> bool:
    return any(host == d or host.endswith("." + d) for d in domains)


def run_rules(text: str) -> RuleResult:
    t = _norm(text)
    flags: set[str] = set()

    # Secret codes: a request verb near a secret word, unless it's a genuine "do not share" notice.
    if _near(t, REQUEST_VERBS, SECRET_WORDS) and not _has(t, SAFE_OTP_NOTICE):
        flags.add("otp_request")
    if _near(t, REQUEST_VERBS, INFO_WORDS, window=80) and not _has(t, SAFE_OTP_NOTICE):
        flags.add("info_request")
    if _has(t, URGENCY_WORDS):
        flags.add("urgency_threat")
    if _has(t, PRIZE_WORDS):
        flags.add("prize_claim")
    if _has(t, PAYMENT_WORDS) and (_near(t, REQUEST_VERBS + ["pay", "ادا"], PAYMENT_WORDS, window=80)
                                   or _has(t, PRIZE_WORDS) or _has(t, NEW_NUMBER_WORDS) or _has(t, TROUBLE_WORDS)
                                   or _has(t, ["gift card", "fee", "fees", "فیس", "گفٹ کارڈ"])):
        flags.add("payment_request")
    if _has(t, NEW_NUMBER_WORDS) and (_has(t, TROUBLE_WORDS) or _has(t, PAYMENT_WORDS) or _has(t, ["help", "madad", "مدد"])):
        flags.add("new_number")

    brands = [name for name, b in BRANDS.items() if _has(t, b["words"])]
    urls = [m.group(0).rstrip(".,)") for m in URL_RE.finditer(text or "")]
    if urls:
        flags.add("contains_link")
        if _has(t, CLICK_WORDS):
            flags.add("suspicious_link")
    for url in urls:
        host = _domain(url)
        if not host:
            continue
        if host in SHORTENERS or re.fullmatch(r"\d+\.\d+\.\d+\.\d+", host) or host.endswith(SUSPICIOUS_TLDS):
            flags.add("suspicious_link")
        claimed = [b for b in brands if BRANDS[b]["domains"]]
        if claimed and not any(_domain_matches(host, BRANDS[b]["domains"]) for b in claimed):
            if not (host.endswith(".gov.pk") and any(b in ("nadra", "fbr", "pta", "bisp", "police") for b in claimed)):
                flags.add("link_mismatch")
        if "bank" in brands and not claimed and not host.endswith((".com.pk", ".gov.pk", ".org.pk")):
            flags.add("link_mismatch")

    if brands and (flags - {"contains_link"}):
        flags.add("impersonation")

    if "suspicious_link" in flags or "link_mismatch" in flags:
        flags.discard("contains_link")

    score = min(1.0, sum(WEIGHTS[f] for f in flags))
    ordered = sorted(flags, key=lambda f: -WEIGHTS[f])
    return RuleResult(score=round(score, 3), flags=ordered, brands=brands, urls=urls)


def needs_llm(r: RuleResult) -> bool:
    """Rules are inconclusive: weak signals only, between 'fine' and 'likely scam'."""
    if set(r.flags) & STRONG:
        return False
    if r.score >= LIKELY_THRESHOLD:
        return False
    return 0.1 <= r.score < LIKELY_THRESHOLD


def explain(verdict: str, flags: list[str], lang: str, llm_reason: dict | None = None) -> dict:
    lang = lang_or_default(lang)
    main = flags[0] if flags else None
    if verdict == "probably_fine" and (not main or main == "contains_link"):
        reason = both("scam.reason.none") if not main else both("scam.reason.contains_link")
        action = both("scam.action.none")
    elif main:
        reason = both(f"scam.reason.{main}")
        action = both(f"scam.action.{main}")
    else:
        reason = both("scam.reason.llm")
        action = both("scam.action.urgency_threat")
    if llm_reason and llm_reason.get("en") and llm_reason.get("ur"):
        reason = llm_reason
    label = both(f"verdict.{verdict}")
    ask = both("scam.ask_family")
    return {
        "label": label,
        "reason": reason,
        "action": action,
        "ask_family": ask,
        "text": f"{label[lang]}. {reason[lang]} {action[lang]} {ask[lang]}",
    }
