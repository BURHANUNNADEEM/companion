"""Task suggestion engine (F3).

score(task) = 3.0 * P(task | last task)          (sequence counts)
            + 2.0 * P(task | hour +-1)            (time-of-day counts)
            + 0.5 * P(task)                       (overall frequency)
            + 0.6 * default-for-daypart bonus     (new users / cold start)
            + feedback (accepted +, dismissed -)
Never executes anything; always offers "Something else"; backs off after N consecutive dismissals.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import Event
from app.services.tasks import DEFAULTS_BY_DAYPART, TASKS, daypart, is_task

SEQ_GAP = timedelta(hours=6)


@dataclass
class Completed:
    task: str
    at: datetime          # server timestamp (ordering / sequence gaps)
    hour: int | None = None  # client local hour, if reported

    @property
    def local_hour(self) -> int:
        return self.hour if self.hour is not None else self.at.hour


def _hour_close(a: int, b: int) -> bool:
    d = abs(a - b) % 24
    return min(d, 24 - d) <= 1


def rank_tasks(
    history: list[Completed],
    hour: int,
    last_task: str | None,
    accepted: Counter | None = None,
    dismissed: Counter | None = None,
    k: int = 3,
) -> list[str]:
    accepted = accepted or Counter()
    dismissed = dismissed or Counter()
    history = sorted(history, key=lambda c: c.at)

    seq: dict[str, Counter] = defaultdict(Counter)
    for prev, nxt in zip(history, history[1:]):
        if nxt.at - prev.at <= SEQ_GAP:
            seq[prev.task][nxt.task] += 1
    hour_counts = Counter(c.task for c in history if _hour_close(c.local_hour, hour))
    overall = Counter(c.task for c in history)

    def p(counter: Counter, task: str) -> float:
        total = sum(counter.values())
        return counter[task] / total if total else 0.0

    defaults = DEFAULTS_BY_DAYPART[daypart(hour)]
    scores: dict[str, float] = {}
    for task in TASKS:
        s = 0.0
        if last_task and last_task in seq:
            s += 3.0 * p(seq[last_task], task)
        s += 2.0 * p(hour_counts, task)
        s += 0.5 * p(overall, task)
        if task in defaults:
            s += 0.6 * (len(defaults) - defaults.index(task)) / len(defaults)
        s += min(0.6, 0.15 * accepted[task]) - min(0.9, 0.2 * dismissed[task])
        if not TASKS[task]["tile"] and overall[task] == 0:
            s -= 0.5  # don't suggest settings-type tasks the user never does
        scores[task] = s
    return sorted(scores, key=lambda t: (-scores[t], t))[:k]


async def load_history(db: AsyncSession, user_id: str, days: int = 60):
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = (
        await db.execute(
            select(Event)
            .where(
                Event.user_id == user_id,
                Event.created_at >= since,
                Event.event_type.in_(["task_completed", "suggestion_accepted", "suggestion_dismissed",
                                      "something_else_tapped", "suggestion_shown"]),
            )
            .order_by(Event.created_at)
            .limit(5000)
        )
    ).scalars().all()
    history: list[Completed] = []
    accepted: Counter = Counter()
    dismissed: Counter = Counter()
    outcomes: list[tuple[str, datetime]] = []
    for e in rows:
        props = e.properties or {}
        if e.event_type == "task_completed" and is_task(e.item_id):
            h = props.get("hour")
            local = h if isinstance(h, int) and not isinstance(h, bool) and 0 <= h <= 23 else None
            history.append(Completed(e.item_id, e.created_at, local))
        elif e.event_type == "suggestion_accepted":
            if is_task(e.item_id):
                accepted[e.item_id] += 1
            outcomes.append(("accepted", e.created_at))
        elif e.event_type == "suggestion_dismissed":
            if is_task(e.item_id):
                dismissed[e.item_id] += 1
            outcomes.append(("dismissed", e.created_at))
        elif e.event_type == "something_else_tapped":
            outcomes.append(("something_else", e.created_at))
    return history, accepted, dismissed, outcomes


def backoff_state(outcomes: list[tuple[str, datetime]], now: datetime | None = None) -> dict:
    s = get_settings()
    now = now or datetime.now(timezone.utc)
    n = s.suggestion_backoff_dismissals
    recent = [o for o in outcomes if o[0] in ("accepted", "dismissed")][-n:]
    if len(recent) == n and all(o[0] == "dismissed" for o in recent):
        last = recent[-1][1]
        if last.tzinfo is None:
            last = last.replace(tzinfo=timezone.utc)
        until = last + timedelta(minutes=s.suggestion_backoff_minutes)
        if now < until:
            return {"active": True, "until": until.isoformat()}
    return {"active": False, "until": None}
