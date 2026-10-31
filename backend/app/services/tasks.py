"""Task catalog shared by home tiles, suggestions, voice and navigation.

Note (documented deviation): the PRD lists "Pay a bill" as an *example* tile, but its
non-goals exclude payments and operating banking apps, so the sixth tile is a WhatsApp
video call instead.
"""
from __future__ import annotations

TASKS: dict[str, dict] = {
    "call": {"label": {"en": "Call", "ur": "کال کریں"}, "workflow": "call_contact", "tile": True},
    "messages": {"label": {"en": "Messages", "ur": "پیغامات"}, "workflow": "open_messages", "tile": True},
    "photos": {"label": {"en": "Photos", "ur": "تصویریں"}, "workflow": "open_photos", "tile": True},
    "whatsapp": {"label": {"en": "WhatsApp video call", "ur": "واٹس ایپ ویڈیو کال"}, "workflow": "whatsapp_video_call", "tile": True},
    "scam_check": {"label": {"en": "Check a message", "ur": "پیغام چیک کریں"}, "workflow": "scam_check", "tile": True},
    "ask_family": {"label": {"en": "Ask my family", "ur": "گھر والوں سے مدد"}, "workflow": "ask_family", "tile": True},
    "whatsapp_chat": {"label": {"en": "WhatsApp message", "ur": "واٹس ایپ پیغام"}, "workflow": "whatsapp_chat", "tile": False},
    "camera": {"label": {"en": "Camera", "ur": "کیمرا"}, "workflow": "open_camera", "tile": False},
    "share_photo": {"label": {"en": "Send a photo", "ur": "تصویر بھیجیں"}, "workflow": "share_photo", "tile": False},
    "wifi": {"label": {"en": "Wi-Fi", "ur": "وائی فائی"}, "workflow": "wifi_on", "tile": False},
    "bluetooth": {"label": {"en": "Bluetooth", "ur": "بلوٹوتھ"}, "workflow": "bluetooth_on", "tile": False},
    "sound": {"label": {"en": "Sound / volume", "ur": "آواز"}, "workflow": "sound_settings", "tile": False},
    "display": {"label": {"en": "Screen brightness", "ur": "اسکرین کی روشنی"}, "workflow": "display_settings", "tile": False},
    "maps": {"label": {"en": "Directions", "ur": "راستہ"}, "workflow": "open_maps", "tile": False},
}

HOME_TILES = [k for k, v in TASKS.items() if v["tile"]]

# Sensible defaults for new users, by part of day (F3).
DEFAULTS_BY_DAYPART = {
    "morning": ["call", "photos", "messages"],      # 05-11
    "afternoon": ["messages", "whatsapp", "call"],  # 12-16
    "evening": ["whatsapp", "call", "photos"],      # 17-21
    "night": ["call", "messages", "photos"],        # 22-04
}


def daypart(hour: int) -> str:
    if 5 <= hour <= 11:
        return "morning"
    if 12 <= hour <= 16:
        return "afternoon"
    if 17 <= hour <= 21:
        return "evening"
    return "night"


def task_view(task_id: str, lang: str) -> dict:
    t = TASKS[task_id]
    return {
        "task": task_id,
        "workflow_id": t["workflow"],
        "label": t["label"],
        "text": t["label"].get(lang, t["label"]["en"]),
    }


def is_task(task_id: str | None) -> bool:
    return bool(task_id) and task_id in TASKS
