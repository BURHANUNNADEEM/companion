"""Predefined, allowlisted navigation workflows.

The backend only DESCRIBES steps and returns a validated launch target.
It never executes anything; the app shows guidance and the user taps.
"""

import re
from dataclasses import asdict, dataclass, field
from urllib.parse import quote

from core.errors import AppError


@dataclass(frozen=True)
class Step:
    screen_id: str
    target_id: str
    text_ur: str
    text_en: str
    why_ur: str
    why_en: str
    hint_ur: str
    hint_en: str


@dataclass(frozen=True)
class Workflow:
    id: str
    title_ur: str
    title_en: str
    launch_kind: str  # dial | whatsapp_chat | sms | *_settings | camera | none
    needs_phone: bool
    is_practice: bool
    keywords: tuple[str, ...]  # voice-intent matching (en / roman ur / ur); '!' = strong keyword
    steps: tuple[Step, ...] = field(default_factory=tuple)


def _settings_menu_step(lesson_id: str, ur: str, en: str) -> Step:
    return Step("settings_menu", f"item_{lesson_id}", f"{ur} پر دبائیں", f"Tap {en}",
                "یہ چھوٹا سبق ہے، پھر ہم اصلی سیٹنگ کھولیں گے۔", "A short lesson, then we open the real settings.",
                "فہرست میں نام ڈھونڈیں", "Find it in the list")


def _open_settings_step() -> Step:
    return Step("settings_lesson", "btn_open_settings", "سیٹنگ کھولیں والا بٹن دبائیں", "Tap Open settings",
                "یہ فون کی اصلی سیٹنگ کھولے گا۔ بٹن آپ خود آن کریں گی۔", "This opens the real settings. You switch it on yourself.",
                "نیچے نیلا بٹن", "The blue button at the bottom")


WORKFLOWS: dict[str, Workflow] = {
    "call_family": Workflow(
        "call_family", "فون کرنا", "Make a call", "dial", True, False,
        ("call", "phone", "ring", "fone", "phone karo", "call karo", "baat karni", "baat karao", "فون", "کال", "بات کرنی", "بات کرا"),
        (
            Step("home", "tile_call", "فون کرنے کے لیے یہ ہرا بٹن دبائیں", "Tap the green Call button",
                 "یہ کال کا بٹن ہے۔ اسے دبانے سے آپ کے لوگوں کی فہرست کھلے گی۔",
                 "This is the Call button. It opens your list of people.",
                 "فون والی تصویر ڈھونڈیں", "Look for the phone picture"),
            Step("contacts", "contact_{contact_id}", "نام پر دبائیں", "Tap the person's name",
                 "جس سے بات کرنی ہو، اس کے نام پر دبائیں۔", "Tap the person you want to talk to.",
                 "نام والی فہرست میں دیکھیں", "Look in the list of names"),
            Step("confirm_call", "btn_call_green", "ہرا بٹن دبا کر کال ملائیں", "Tap the green button to call",
                 "ہرا بٹن کال ملاتا ہے، لال بٹن کال بند کرتا ہے۔ کچھ خراب نہیں ہوگا۔",
                 "Green starts a call, red ends it. Nothing will break.",
                 "ہرا رنگ = کال ملانا", "Green means call"),
        ),
    ),
    "whatsapp_video": Workflow(
        "whatsapp_video", "واٹس ایپ ویڈیو کال", "WhatsApp video call", "whatsapp_chat", True, True,
        ("!whatsapp", "!video", "!watsapp", "!video call", "shakal", "dekh kar", "!واٹس ایپ", "!ویڈیو", "دیکھ کر"),
        (
            Step("home", "tile_whatsapp", "واٹس ایپ کا بٹن دبائیں", "Tap the WhatsApp button",
                 "اس سے آپ بچوں کو دیکھ کر بات کر سکتی ہیں۔", "You can see your family while you talk.",
                 "ہری بات والی تصویر ڈھونڈیں", "Look for the green speech bubble"),
            Step("wa_contacts", "contact_{contact_id}", "نام پر دبائیں", "Tap the person's name",
                 "نام دبانے سے ان کی بات چیت کھلے گی۔", "Tap the person to open your chat.",
                 "نام والی فہرست میں دیکھیں", "Look in the list of names"),
            Step("wa_chat_practice", "btn_wa_video", "اوپر کیمرے والا نشان دبائیں", "Tap the camera icon at the top",
                 "کیمرے کا نشان ویڈیو کال ہے۔ یہ مشق ہے، اصلی کال نہیں ہوگی۔",
                 "The camera icon is a video call. This is practice, no real call.",
                 "اوپر دائیں طرف دیکھیں", "Look at the top right"),
        ),
    ),
    "scam_check": Workflow(
        "scam_check", "پیغام چیک کرنا", "Check a message", "none", False, False,
        ("!scam", "!fraud", "check message", "message check", "!dhoka", "sahi hai", "پیغام", "!دھوکہ", "چیک"),
        (
            Step("home", "tile_check_message", "پیغام چیک کریں والا بٹن دبائیں", "Tap Check a message",
                 "کوئی پیغام عجیب لگے تو یہاں چیک کریں۔", "If a message looks strange, check it here.",
                 "ڈھال والی تصویر ڈھونڈیں", "Look for the shield picture"),
            Step("scam_check", "btn_paste", "پیسٹ دبا کر پیغام یہاں لائیں", "Tap Paste",
                 "پیسٹ کا مطلب ہے کاپی کیا ہوا پیغام یہاں رکھنا۔", "Paste puts the copied message here.",
                 "ڈبے کے نیچے بٹن دیکھیں", "Look under the box"),
            Step("scam_check", "btn_check", "اب چیک کریں دبائیں", "Now tap Check",
                 "ہم بتائیں گے یہ محفوظ ہے یا دھوکہ، اور کیوں۔", "We will say if it looks safe or like a scam, and why.",
                 "بڑا نیلا بٹن", "The big blue button"),
        ),
    ),
    "wifi": Workflow(
        "wifi", "وائی فائی چلانا", "Turn on Wi-Fi", "wifi_settings", False, False,
        ("!wifi", "!wi-fi", "internet", "net", "net nahi", "!وائی فائی", "انٹرنیٹ"),
        (
            Step("home", "tile_wifi", "وائی فائی کا بٹن دبائیں", "Tap the Wi-Fi button",
                 "اس سے فون کی وائی فائی سیٹنگ کھلے گی۔ وہاں اوپر والا بٹن آن کریں۔",
                 "This opens Wi-Fi settings. Turn on the switch at the top there.",
                 "لہروں والی تصویر ڈھونڈیں", "Look for the wave picture"),
        ),
    ),
    "open_camera": Workflow(
        "open_camera", "تصویر کھینچنا", "Take a photo", "camera", False, False,
        ("!camera", "photo", "picture", "tasveer", "selfie", "!کیمرہ", "تصویر"),
        (
            Step("home", "tile_camera", "کیمرے کا بٹن دبائیں", "Tap the Camera button",
                 "کیمرہ کھلے گا۔ تصویر کے لیے نیچے گول بٹن دبائیں۔",
                 "The camera opens. Tap the round button at the bottom to take a photo.",
                 "کیمرے کی تصویر ڈھونڈیں", "Look for the camera picture"),
        ),
    ),
    "hotspot": Workflow(
        "hotspot", "ہاٹ اسپاٹ (انٹرنیٹ شیئر کرنا)", "Share internet (hotspot)", "wireless_settings", False, False,
        ("!hotspot", "!hot spot", "net share", "internet share", "!ہاٹ اسپاٹ", "انٹرنیٹ شیئر"),
        (_settings_menu_step("hotspot", "ہاٹ اسپاٹ", "Hotspot"), _open_settings_step()),
    ),
    "sound": Workflow(
        "sound", "آواز اونچی کرنا", "Make sound louder", "sound_settings", False, False,
        ("!volume", "!sound", "awaz", "!ringtone", "ghanti", "!آواز", "گھنٹی"),
        (_settings_menu_step("sound", "آواز", "Sound"), _open_settings_step()),
    ),
    "display": Workflow(
        "display", "لکھائی بڑی کرنا", "Bigger text and brightness", "display_settings", False, False,
        ("!font", "!text size", "bara likhna", "!brightness", "roshni", "!لکھائی", "روشنی"),
        (_settings_menu_step("display", "لکھائی", "Text size"), _open_settings_step()),
    ),
    "bluetooth": Workflow(
        "bluetooth", "بلوٹوتھ چلانا", "Turn on Bluetooth", "bluetooth_settings", False, False,
        ("!bluetooth", "!headphone", "speaker", "!بلوٹوتھ", "ہیڈفون"),
        (_settings_menu_step("bluetooth", "بلوٹوتھ", "Bluetooth"), _open_settings_step()),
    ),
    "bank_practice": Workflow(
        "bank_practice", "بینک کی محفوظ مشق", "Safe banking practice", "none", False, True,
        ("!bank", "paise bhejne", "money send", "!بینک", "پیسے بھیج"),
        (
            Step("home", "tile_bank", "بینک کی مشق والا بٹن دبائیں", "Tap Banking practice",
                 "یہ صرف مشق ہے، کوئی اصلی پیسے نہیں جائیں گے۔", "Practice only, no real money moves.",
                 "بینک کی عمارت والی تصویر", "The bank building picture"),
            Step("bank_practice", "btn_bank_review", "نام اور رقم چیک کر کے بٹن دبائیں", "Check name and amount, then tap",
                 "پیسے بھیجنے سے پہلے نام اور رقم دو بار پڑھیں۔", "Read the name and amount twice before sending.",
                 "نیچے والا بٹن", "The button at the bottom"),
            Step("bank_otp", "btn_refuse_otp", "کوڈ نہ بتائیں، فون بند کریں", "Do not share the code, hang up",
                 "بینک کبھی فون پر کوڈ نہیں مانگتا۔", "Banks never ask for the code on the phone.",
                 "ہرا بٹن", "The green button"),
        ),
    ),
}

# Fixed Android targets the app may open. No free-form URIs ever.
_LAUNCH_TEMPLATES = {
    "dial": "tel:+{phone}",
    "whatsapp_chat": "https://wa.me/{phone}",
    "sms": "sms:+{phone}",
    "wifi_settings": "android.settings.WIFI_SETTINGS",
    "wireless_settings": "android.settings.WIRELESS_SETTINGS",
    "sound_settings": "android.settings.SOUND_SETTINGS",
    "display_settings": "android.settings.DISPLAY_SETTINGS",
    "bluetooth_settings": "android.settings.BLUETOOTH_SETTINGS",
    "camera": "android.media.action.STILL_IMAGE_CAMERA",
}
_PHONE_RE = re.compile(r"^\d{10,15}$")


def get(workflow_id: str) -> Workflow:
    wf = WORKFLOWS.get(workflow_id)
    if wf is None:
        raise AppError(404, "unknown_workflow", f"Workflow '{workflow_id}' is not in the allowlist",
                       {"allowed": list(WORKFLOWS)})
    return wf


def normalize_phone(raw: str) -> str:
    digits = re.sub(r"[\s\-()+]", "", raw)
    if digits.startswith("00"):
        digits = digits[2:]
    if digits.startswith("0") and len(digits) == 11:  # Pakistani local 03xx… -> 923xx…
        digits = "92" + digits[1:]
    if not _PHONE_RE.match(digits):
        raise AppError(422, "invalid_phone", "Phone must be 10-15 digits, e.g. 923001234567")
    return digits


def to_dict(wf: Workflow, contact_id: str = "helper", include_steps: bool = True) -> dict:
    d = {
        "id": wf.id,
        "title_ur": wf.title_ur,
        "title_en": wf.title_en,
        "launch_kind": wf.launch_kind,
        "needs_phone": wf.needs_phone,
        "is_practice": wf.is_practice,
        "step_count": len(wf.steps),
    }
    if include_steps:
        steps = []
        for i, s in enumerate(wf.steps):
            sd = asdict(s)
            sd["target_id"] = s.target_id.replace("{contact_id}", contact_id)
            sd["index"] = i
            steps.append(sd)
        d["steps"] = steps
    return d


def resolve_launch(wf: Workflow, phone: str | None) -> dict:
    """Validated launch descriptor. The APP decides whether to open it; backend never acts."""
    if wf.launch_kind == "none":
        return {"kind": "none", "uri": None, "android_action": None, "user_must_tap": True}
    if wf.needs_phone:
        if not phone:
            raise AppError(422, "phone_required", "This workflow needs contact_phone")
        uri = _LAUNCH_TEMPLATES[wf.launch_kind].format(phone=quote(normalize_phone(phone)))
        return {"kind": wf.launch_kind, "uri": uri, "android_action": None, "user_must_tap": True,
                "practice_first": wf.is_practice}
    return {"kind": wf.launch_kind, "uri": None, "android_action": _LAUNCH_TEMPLATES[wf.launch_kind],
            "user_must_tap": True}
