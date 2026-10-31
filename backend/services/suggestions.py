"""Task suggestions from the user's own completed-task history.

score = 2 x P(next | last task) + 1 x share at this time of day
      + 0.3 x overall share + small default prior.
Backs off after N consecutive dismissals. Never executes anything.
"""

from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import Settings
from models import Event, TaskAttempt
from services import workflows

DEFAULTS = ["call_family", "whatsapp_video", "scam_check"]


def bucket(hour: int) -> str:
    if 5 <= hour < 12:
        return "morning"
    if 12 <= hour < 17:
        return "afternoon"
    if 17 <= hour < 22:
        return "evening"
    return "night"


async def _in_backoff(db: AsyncSession, user_id: int, s: Settings) -> bool:
    since = datetime.now(timezone.utc) - timedelta(minutes=s.suggestions_backoff_minutes)
    rows = (await db.execute(
        select(Event.event_type).where(
            Event.user_id == user_id,
            Event.created_at >= since,
            Event.event_type.in_(["suggestion_dismissed", "suggestion_accepted"]),
        ).order_by(Event.created_at.desc(), Event.id.desc()).limit(s.suggestions_backoff_dismissals)
    )).scalars().all()
    return len(rows) >= s.suggestions_backoff_dismissals and all(r == "suggestion_dismissed" for r in rows)


async def suggest(db: AsyncSession, user_id: int, s: Settings, hour: int | None = None,
                  last_task: str | None = None) -> dict:
    if await _in_backoff(db, user_id, s):
        return {"suggestions": [], "backoff": True, "always_offer_something_else": True}

    done = (await db.execute(
        select(TaskAttempt.task_id, TaskAttempt.ended_at).where(
            TaskAttempt.user_id == user_id, TaskAttempt.status == "completed"
        ).order_by(TaskAttempt.ended_at)
    )).all()
    seq = [t for t, _ in done]
    if last_task is None and seq:
        last_task = seq[-1]
    hour = datetime.now(timezone.utc).hour if hour is None else hour
    b = bucket(hour)

    trans: dict[str, Counter] = defaultdict(Counter)
    for a, nxt in zip(seq, seq[1:]):
        trans[a][nxt] += 1
    by_bucket = Counter(t for t, ended in done if ended and bucket(ended.hour) == b)
    totals = Counter(seq)

    tr = trans.get(last_task or "", Counter())
    tr_sum, b_sum, t_sum = sum(tr.values()), sum(by_bucket.values()), sum(totals.values())
    scores = {}
    for tid in workflows.WORKFLOWS:
        prior = 0.1 * (len(DEFAULTS) - DEFAULTS.index(tid)) / len(DEFAULTS) if tid in DEFAULTS else 0.0
        scores[tid] = (
            (2.0 * tr[tid] / tr_sum if tr_sum else 0)
            + (1.0 * by_bucket[tid] / b_sum if b_sum else 0)
            + (0.3 * totals[tid] / t_sum if t_sum else 0)
            + prior
        )
    ranked = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)[: s.suggestions_max]
    return {
        "suggestions": [
            {"task_id": t, "score": round(sc, 3),
             "title_ur": workflows.WORKFLOWS[t].title_ur, "title_en": workflows.WORKFLOWS[t].title_en}
            for t, sc in ranked
        ],
        "backoff": False,
        "always_offer_something_else": True,
        "prompt_ur": "کیا میں مدد کروں؟",
        "prompt_en": "Need a hand?",
    }
