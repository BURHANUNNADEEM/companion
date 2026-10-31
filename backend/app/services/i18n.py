"""Bilingual (English / Urdu) server-side strings.

Every user-facing sentence the backend returns lives here, in both languages.
Responses carry `{"en": ..., "ur": ...}` objects plus a `text` field in the user's language,
so the app can always show text alongside audio (F7) and switch language instantly.
"""
from __future__ import annotations

SUPPORTED_LANGS = ("ur", "en")

MESSAGES: dict[str, dict[str, str]] = {
    # --- scam verdicts (F6) ---
    "verdict.likely_scam": {"en": "Likely scam", "ur": "غالباً دھوکہ"},
    "verdict.be_careful": {"en": "Be careful", "ur": "احتیاط کریں"},
    "verdict.probably_fine": {"en": "Probably fine", "ur": "شاید ٹھیک ہے"},
    "scam.ask_family": {"en": "When in doubt, ask your family.", "ur": "شک ہو تو اپنے گھر والوں سے پوچھیں۔"},
    "scam.reason.otp_request": {
        "en": "It asks for a secret code, PIN or password.",
        "ur": "یہ پیغام خفیہ کوڈ، پن یا پاس ورڈ مانگ رہا ہے۔",
    },
    "scam.action.otp_request": {
        "en": "Do not share the code. Banks never ask for it. Call your bank using the number on your card.",
        "ur": "کوڈ کسی کو نہ بتائیں۔ بینک کبھی کوڈ نہیں مانگتا۔ اپنے کارڈ پر لکھے نمبر سے بینک کو کال کریں۔",
    },
    "scam.reason.payment_request": {
        "en": "It asks you to send money, pay a fee or buy gift cards.",
        "ur": "یہ پیغام آپ سے پیسے بھیجنے، فیس دینے یا گفٹ کارڈ خریدنے کو کہہ رہا ہے۔",
    },
    "scam.action.payment_request": {
        "en": "Do not send any money. First call your family on their usual number to check.",
        "ur": "کوئی پیسے نہ بھیجیں۔ پہلے اپنے گھر والوں کو ان کے پرانے نمبر پر کال کر کے تصدیق کریں۔",
    },
    "scam.reason.prize_claim": {
        "en": "It says you won a prize or money you did not apply for.",
        "ur": "یہ کہتا ہے کہ آپ نے انعام یا رقم جیتی ہے جس کے لیے آپ نے درخواست نہیں دی۔",
    },
    "scam.action.prize_claim": {
        "en": "Do not reply or open any link. Real prizes never ask for fees or codes.",
        "ur": "جواب نہ دیں اور کوئی لنک نہ کھولیں۔ اصلی انعام کبھی فیس یا کوڈ نہیں مانگتا۔",
    },
    "scam.reason.info_request": {
        "en": "It asks for your ID card, account or card number.",
        "ur": "یہ آپ کا شناختی کارڈ، اکاؤنٹ یا کارڈ نمبر مانگ رہا ہے۔",
    },
    "scam.action.info_request": {
        "en": "Do not send your details. Visit the branch or call the official number yourself.",
        "ur": "اپنی تفصیلات نہ بھیجیں۔ خود برانچ جائیں یا سرکاری نمبر پر کال کریں۔",
    },
    "scam.reason.link_mismatch": {
        "en": "The link does not belong to the company or office it claims to be from.",
        "ur": "لنک اس ادارے کا نہیں ہے جس کا نام پیغام میں لکھا ہے۔",
    },
    "scam.action.link_mismatch": {
        "en": "Do not open the link. Open the official app or call the official number instead.",
        "ur": "لنک نہ کھولیں۔ اس کے بجائے اصلی ایپ کھولیں یا سرکاری نمبر پر کال کریں۔",
    },
    "scam.reason.suspicious_link": {
        "en": "It has a short or unusual link that hides where it really goes.",
        "ur": "اس میں ایک چھوٹا یا عجیب لنک ہے جو اصل جگہ کو چھپاتا ہے۔",
    },
    "scam.action.suspicious_link": {
        "en": "Do not open the link. If it matters, ask your family to check it.",
        "ur": "لنک نہ کھولیں۔ اگر ضروری ہو تو گھر والوں سے چیک کروائیں۔",
    },
    "scam.reason.urgency_threat": {
        "en": "It tries to rush or scare you.",
        "ur": "یہ آپ کو جلدی کرنے یا ڈرانے کی کوشش کر رہا ہے۔",
    },
    "scam.action.urgency_threat": {
        "en": "Take your time. Real banks and offices give you time. Ask your family before doing anything.",
        "ur": "جلدی نہ کریں۔ اصلی بینک اور دفاتر وقت دیتے ہیں۔ کچھ کرنے سے پہلے گھر والوں سے پوچھیں۔",
    },
    "scam.reason.new_number": {
        "en": "Someone says this is their new number and needs help.",
        "ur": "کوئی کہہ رہا ہے کہ یہ اس کا نیا نمبر ہے اور اسے مدد چاہیے۔",
    },
    "scam.action.new_number": {
        "en": "Call the person on their old number to check it is really them.",
        "ur": "اس شخص کو اس کے پرانے نمبر پر کال کر کے تصدیق کریں کہ وہی ہے۔",
    },
    "scam.reason.impersonation": {
        "en": "It uses the name of a bank or government office.",
        "ur": "یہ کسی بینک یا سرکاری ادارے کا نام استعمال کر رہا ہے۔",
    },
    "scam.action.impersonation": {
        "en": "Contact the office yourself using its official number.",
        "ur": "خود ادارے کے سرکاری نمبر پر رابطہ کریں۔",
    },
    "scam.reason.contains_link": {"en": "It contains a link.", "ur": "اس پیغام میں ایک لنک ہے۔"},
    "scam.action.contains_link": {
        "en": "Only open links from people you know and expect.",
        "ur": "صرف جاننے والوں کے اور متوقع لنک ہی کھولیں۔",
    },
    "scam.reason.llm": {"en": "Our helper found warning signs.", "ur": "ہمارے مددگار کو خطرے کی علامات ملیں۔"},
    "scam.reason.none": {
        "en": "We did not find common warning signs.",
        "ur": "ہمیں خطرے کی کوئی عام علامت نہیں ملی۔",
    },
    "scam.action.none": {
        "en": "It looks okay, but never share codes or send money to people you don't know.",
        "ur": "یہ ٹھیک لگتا ہے، لیکن انجان لوگوں کو کبھی کوڈ نہ بتائیں اور نہ پیسے بھیجیں۔",
    },
    # --- navigation (F10) ---
    "nav.refused.sensitive": {
        "en": "For your safety, Companion does not help inside banking, payment or password screens. Please ask your family.",
        "ur": "آپ کی حفاظت کے لیے کمپینین بینک، ادائیگی یا پاس ورڈ والی اسکرینوں میں مدد نہیں کرتا۔ براہ کرم اپنے گھر والوں سے پوچھیں۔",
    },
    "nav.refused.unknown": {
        "en": "I'm not sure what you need. Please pick one of these.",
        "ur": "مجھے یقین نہیں کہ آپ کو کیا چاہیے۔ براہ کرم ان میں سے ایک چنیں۔",
    },
    "nav.done": {"en": "Well done! You did it.", "ur": "شاباش! آپ نے کر لیا۔"},
    # --- alerts (F9) ---
    "alert.repeated_struggle": {
        "en": "Your parent needed help several times today with: {task}.",
        "ur": "آج آپ کے والدین کو کئی بار اس کام میں مدد کی ضرورت پڑی: {task}۔",
    },
    "alert.scam_shared": {
        "en": "Your parent checked a message and it looked like a likely scam. They chose to tell you.",
        "ur": "آپ کے والدین نے ایک پیغام چیک کیا جو غالباً دھوکہ لگا۔ انہوں نے آپ کو بتانا چاہا۔",
    },
    "alert.scam_shared_generic": {
        "en": "Your parent shared a message check with you: {verdict}.",
        "ur": "آپ کے والدین نے پیغام کی جانچ آپ کو بھیجی ہے: {verdict}۔",
    },
    "alert.inactivity": {
        "en": "No activity from your parent for {days} days. Maybe give them a call.",
        "ur": "آپ کے والدین کی طرف سے {days} دن سے کوئی سرگرمی نہیں۔ شاید انہیں فون کر لیں۔",
    },
    # --- email (F9) ---
    "email.invite.subject": {"en": "You're invited to help on Companion", "ur": "کمپینین پر مدد کی دعوت"},
    "email.invite.body": {
        "en": "{name} has invited you to be their helper on Companion.\n\nOpen the app, sign in as Caregiver and enter this code: {code}\nOr open: {url}?code={code}\n\nThe code expires in {hours} hours. You will only see activity summaries, never messages or contacts.",
        "ur": "{name} نے آپ کو کمپینین پر اپنا مددگار بننے کی دعوت دی ہے۔\n\nایپ کھولیں، بطور نگران (Caregiver) سائن ان کریں اور یہ کوڈ درج کریں: {code}\nیا یہ کھولیں: {url}?code={code}\n\nیہ کوڈ {hours} گھنٹوں میں ختم ہو جائے گا۔ آپ صرف سرگرمی کا خلاصہ دیکھیں گے، کبھی پیغامات یا رابطے نہیں۔",
    },
}


def lang_or_default(lang: str | None) -> str:
    return lang if lang in SUPPORTED_LANGS else "ur"


def t(key: str, lang: str = "ur", **kwargs) -> str:
    entry = MESSAGES.get(key)
    if entry is None:
        return key
    text = entry.get(lang_or_default(lang)) or entry["en"]
    return text.format(**kwargs) if kwargs else text


def both(key: str, **kwargs) -> dict[str, str]:
    """Return {"en": ..., "ur": ...} for a key."""
    entry = MESSAGES[key]
    out = {}
    for lang in SUPPORTED_LANGS:
        out[lang] = entry[lang].format(**kwargs) if kwargs else entry[lang]
    return out
