"""Scam check pipeline: rules first, Gemini only when rules are inconclusive."""

from dataclasses import asdict

from sqlalchemy.ext.asyncio import AsyncSession

from models import ScamCheck
from services import gemini, scam_rules
from services.scam_rules import LEVEL_ORDER

LABELS = {
    "probably_fine": ("شاید ٹھیک ہے", "Probably fine"),
    "be_careful": ("احتیاط کریں", "Be careful"),
    "likely_scam": ("یہ دھوکہ لگتا ہے", "Likely scam"),
}
ASK_FAMILY_UR = "شک ہو تو اپنے گھر والوں سے پوچھ لیں۔"
ASK_FAMILY_EN = "When in doubt, ask your family."


async def check(db: AsyncSession, user_id: int, text: str, input_source: str,
                ai_allowed: bool, store_text: bool) -> dict:
    rv = scam_rules.check(text)
    level, source = rv.level, "rules"
    reasons = [asdict(r) for r in rv.reasons]
    ai_used = False

    if not rv.conclusive and ai_allowed:
        g = await gemini.classify_scam(scam_rules.redact(text))
        if g is not None:
            ai_used = True
            source = "rules+gemini"
            # AI can raise the warning level, never lower what the rules found.
            if LEVEL_ORDER[g.level] > LEVEL_ORDER[level] and g.confidence >= 0.6:
                level = g.level
            reasons.append({"rule_id": "ai_review", "weight": 0, "reason_ur": g.reason_ur, "reason_en": g.reason_en})

    action_ur, action_en = rv.action_ur, rv.action_en
    if level != rv.level and level != "probably_fine":
        action_ur, action_en = "جواب نہ دیں، لنک نہ کھولیں اور کچھ نہ بھیجیں۔", "Do not reply, open links or send anything."

    row = ScamCheck(
        user_id=user_id, verdict=level, score=rv.score,
        reasons=[{"rule_id": r["rule_id"], "weight": r["weight"]} for r in reasons],
        source=source, input_source=input_source,
        redacted_text=scam_rules.redact(text) if store_text else None,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)

    label_ur, label_en = LABELS[level]
    spoken = f"{label_ur}۔ {reasons[0]['reason_ur'] + ' ' if reasons else ''}{action_ur} {ASK_FAMILY_UR}"
    return {
        "check_id": row.id,
        "verdict": level,
        "label_ur": label_ur,
        "label_en": label_en,
        "score": rv.score,
        "reasons": reasons,
        "action_ur": action_ur,
        "action_en": action_en,
        "lesson_ur": rv.lesson_ur,
        "lesson_en": rv.lesson_en,
        "ask_family_ur": ASK_FAMILY_UR,
        "ask_family_en": ASK_FAMILY_EN,
        "spoken_ur": spoken,
        "source": source,
        "ai_used": ai_used,
        "text_stored": store_text,
    }
