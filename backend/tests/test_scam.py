"""F6 acceptance: recall >= 85% on scam samples, false-positive rate <= 15% on normal messages."""
from sqlalchemy import select

from app.core.db import SessionLocal
from app.models import ScamCheck
from app.services.redaction import redact
from app.services.scam_rules import run_rules
from tests.conftest import onboard

SCAMS = [
    "Dear customer, your HBL account will be blocked within 24 hours. Share the OTP sent to you to verify.",
    "Congratulations! You have won Rs 50,000 in the Jazz lucky draw. Send processing fee of Rs 500 to claim.",
    "BISP: Aap ke 25000 rupay manzoor ho gaye hain. Registration fee 1000 Easypaisa par bhejein.",
    "مبارک ہو! آپ کا نام احساس پروگرام کی قرعہ اندازی میں نکل آیا ہے۔ انعام کے لیے فیس جمع کروائیں۔",
    "آپ کا بینک اکاؤنٹ بند کر دیا جائے گا۔ فوری طور پر اپنا کوڈ اس نمبر پر بھیجیں۔",
    "Your NADRA CNIC has expired. Update now at http://nadra-verify.xyz to avoid penalty.",
    "Ammi this is my new number, I am in trouble please send 20000 to this jazzcash account urgently",
    "امی یہ میرا نیا نمبر ہے، مصیبت میں ہوں فوراً پیسے بھیج دیں",
    "Meezan Bank: Your card is suspended. Click here to reactivate: http://bit.ly/meezan-card",
    "FBR notice: legal action will be taken. Pay your tax penalty immediately via this link www.fbr-pay.top",
    "You are selected for a free gift card worth $500! Reply with your card number to receive it.",
    "Telenor: Aap ka number band ho jayega. Verification code batayen jo abhi aap ko mila.",
    "PTA: Your SIM will be blocked today. Send your CNIC number and account details to confirm ownership.",
    "Daraz winner! You won an iPhone. Pay delivery fee Rs 2000 to receive your prize.",
    "Assalam o alaikum, main bank se baat kar raha hoon. Aap ka ATM card block hai, PIN batayen.",
    "آپ نے 10 لاکھ روپے کا انعام جیت لیا ہے۔ رقم وصول کرنے کے لیے اپنا شناختی کارڈ نمبر بھیجیں۔",
    "URGENT: Your easypaisa account deactivated. Login at http://easypaisa-secure.online to restore.",
    "Police: An FIR has been registered against you. Pay Rs 30000 now or you will be arrested.",
    "Amazon: unusual sign-in. Verify your password at http://amaz0n-security.site immediately.",
    "Your parcel is held at customs. Pay the delivery fee here: http://tinyurl.com/parcel-fee",
    "UBL alert: please confirm your debit card number and expiry to avoid card blocking.",
    "Bhai mera phone kharab hai yeh naya number hai, emergency hai 5000 easypaisa kar do",
    "Last warning! Your WhatsApp will be suspended. Send the 6 digit code you received.",
    "State Bank of Pakistan: your account is under review. Provide your account number for verification.",
    "Jeet gaye! Aap ka inaam 1 lakh. Fees ke liye jazzcash par 1500 bhejo.",
    "آپ کی سم معطل ہو جائے گی۔ تصدیق کے لیے او ٹی پی بتائیں۔",
    "Dear user your electricity will be disconnected tonight. Call this number and pay immediately.",
    "Congratulations you have won a lottery of 5 crore. Contact our agent and send registration fee.",
]

NORMAL = [
    "Your OTP for HBL login is 482913. Do not share it with anyone.",
    "Ammi I will reach home by 7pm, please keep dinner ready.",
    "Beta kal doctor ka appointment 11 baje hai, yaad rakhna.",
    "کل شام کو ہم آپ کے گھر آئیں گے ان شاء اللہ",
    "Your Jazz bundle has been activated. Enjoy 10GB data for 30 days.",
    "Meeting moved to Thursday 3pm in the main office.",
    "Happy birthday Abbu! Lots of love from all of us.",
    "Rs 2,500 has been received in your Easypaisa account from AHMED. Balance Rs 7,430.",
    "Please bring the medicines from the pharmacy on your way back.",
    "Eid Mubarak to you and your family!",
    "آپ کی بجلی کا بل 3200 روپے ہے، آخری تاریخ 15 نومبر۔ شکریہ",
    "Can you send me the photos from the wedding?",
    "Your Daraz order #123456 has been shipped and will arrive in 3 days.",
    "Namaz ke baad masjid ke bahar milte hain.",
    "Reminder: your car service is due next week.",
    "Mama, I sent you the recipe on WhatsApp, check it.",
    "امی جان دوائی وقت پر لے لیجیے گا",
    "The school will remain closed tomorrow due to rain.",
    "Thanks for the lovely dinner yesterday!",
    "Your verification code for Google is 552311. Never share this code.",
    "Bhai match kitne baje shuru ho raha hai?",
    "Your MCB debit card transaction of Rs 1,200 at Imtiaz was successful.",
    "Grandma, we will video call you on Sunday evening.",
    "Watch this video of the kids playing: https://youtube.com/watch?v=abc",
]


def _flagged(text: str) -> bool:
    return run_rules(text).verdict in ("likely_scam", "be_careful")


def test_recall_and_false_positive_rate():
    recall = sum(_flagged(t) for t in SCAMS) / len(SCAMS)
    fpr = sum(_flagged(t) for t in NORMAL) / len(NORMAL)
    missed = [t for t in SCAMS if not _flagged(t)]
    false_pos = [t for t in NORMAL if _flagged(t)]
    print(f"recall={recall:.0%} fpr={fpr:.0%}\nmissed={missed}\nfalse_pos={false_pos}")
    assert recall >= 0.85
    assert fpr <= 0.15


def test_redaction():
    out = redact("Dear Ali Khan, call 0300-1234567 or +92 321 7654321, CNIC 35202-1234567-1, "
                 "acct 0123456789012, code 4829, mail a.b@x.com, IBAN PK36SCBL0000001123456702. محترم احمد صاحب")
    for secret in ("Ali", "1234567", "7654321", "35202", "0123456789012", "4829", "a.b@x.com", "PK36", "احمد"):
        assert secret not in out, secret
    for token in ("[NAME]", "[PHONE]", "[CNIC]", "[CODE]", "[EMAIL]", "[IBAN]"):
        assert token in out


async def test_check_endpoint_bilingual_and_hedged(client):
    h = await onboard(client, "s1", "parent", lang="ur")
    body = (await client.post("/api/scam/check", json={"text": SCAMS[0]}, headers=h)).json()
    assert body["verdict"] == "likely_scam" and "otp_request" in body["reasons"]
    e = body["explanation"]
    assert e["label"]["ur"] == "غالباً دھوکہ" and e["label"]["en"] == "Likely scam"
    assert e["ask_family"]["en"] == "When in doubt, ask your family."
    assert "Banks never ask" in e["action"]["en"] and e["action"]["ur"]
    assert e["text"].startswith("غالباً دھوکہ")
    assert "certain" not in e["text"].lower() and "100%" not in e["text"]


async def test_message_text_not_stored_by_default(client):
    h = await onboard(client, "s2", "parent")
    await client.post("/api/scam/check", json={"text": SCAMS[1], "source": "share"}, headers=h)
    async with SessionLocal() as db:
        row = (await db.execute(select(ScamCheck))).scalar_one()
    assert row.redacted_text is None and row.verdict and row.reasons and row.source == "share"


async def test_text_stored_redacted_only_with_consent(client):
    h = await onboard(client, "s3", "parent", store_text=True)
    await client.post("/api/scam/check", json={"text": "Dear Ali, send code to 03001234567"}, headers=h)
    async with SessionLocal() as db:
        row = (await db.execute(select(ScamCheck))).scalar_one()
    assert "03001234567" not in row.redacted_text and "Ali" not in row.redacted_text


async def test_inconclusive_goes_to_llm_with_redaction(client, llm_on):
    seen = {}

    def fake(prompt, schema):
        seen["p"] = prompt
        return {"verdict": "be_careful", "confidence": 0.7, "reason_en": "It pushes you to act fast.",
                "reason_ur": "یہ آپ کو جلدی کرنے پر مجبور کرتا ہے۔"}

    llm_on(fake)
    h = await onboard(client, "s4", "parent", lang="en")
    body = (await client.post("/api/scam/check", json={"text": "Mr Bilal Ahmed urgent reply now 03001112223"}, headers=h)).json()
    assert body["engine"] == "llm" and body["verdict"] == "be_careful"
    assert body["explanation"]["reason"]["en"] == "It pushes you to act fast."
    assert "03001112223" not in seen["p"] and "Bilal" not in seen["p"]


async def test_llm_outage_falls_back_to_rules(client, llm_on):
    llm_on(lambda p, s: None)
    h = await onboard(client, "s5", "parent")
    body = (await client.post("/api/scam/check", json={"text": "urgent reply now"}, headers=h)).json()
    assert body["engine"] == "rules" and body["verdict"] in ("be_careful", "probably_fine")


async def test_llm_invalid_json_ignored(client, llm_on):
    llm_on(lambda p, s: {"verdict": "definitely_safe_trust_me", "confidence": 2})
    h = await onboard(client, "s6", "parent")
    body = (await client.post("/api/scam/check", json={"text": "urgent reply now"}, headers=h)).json()
    assert body["engine"] == "rules"
