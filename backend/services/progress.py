"""Help-that-fades ladder: per-task progress, start/complete attempts."""

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import Settings
from core.errors import AppError
from models import TaskAttempt, TaskProgress
from services import workflows

HELP_LEVELS = ["none", "nudge", "highlight", "full"]
STAGES = {
    "new": ("🌰", "ابھی شروع نہیں کیا", "Not tried yet"),
    "learning": ("🌱", "سیکھ رہی ہیں", "Learning"),
    "getting_there": ("🌿", "تقریباً آ گیا", "Getting there"),
    "confident": ("🌳", "خود کر لیتی ہیں", "Confident"),
}


def starting_level(p: TaskProgress | None, s: Settings) -> str:
    c = p.clean_completions if p else 0
    if c >= s.ladder_clean_for_none:
        return "none"
    if c >= s.ladder_clean_for_highlight:
        return "highlight"
    return "full"


def stage(p: TaskProgress | None, s: Settings) -> str:
    if p is None or p.completions == 0:
        return "new"
    if p.clean_completions >= s.ladder_clean_for_mastery:
        return "confident"
    if p.clean_completions >= 1:
        return "getting_there"
    return "learning"


def raise_level(level: str) -> str:
    i = HELP_LEVELS.index(level) if level in HELP_LEVELS else 0
    return HELP_LEVELS[min(i + 1, len(HELP_LEVELS) - 1)]


def progress_dict(task_id: str, p: TaskProgress | None, s: Settings) -> dict:
    st = stage(p, s)
    emoji, ur, en = STAGES[st]
    wf = workflows.WORKFLOWS.get(task_id)
    stuck = None
    if p and p.struggle_by_step:
        k, _ = max(p.struggle_by_step.items(), key=lambda kv: kv[1])
        idx = int(k)
        if wf and idx < len(wf.steps):
            stuck = {"step_index": idx, "text_ur": wf.steps[idx].text_ur, "text_en": wf.steps[idx].text_en}
    return {
        "task_id": task_id,
        "title_ur": wf.title_ur if wf else task_id,
        "title_en": wf.title_en if wf else task_id,
        "stage": st,
        "stage_emoji": emoji,
        "stage_label_ur": ur,
        "stage_label_en": en,
        "starting_help_level": starting_level(p, s),
        "attempts": p.attempts if p else 0,
        "completions": p.completions if p else 0,
        "clean_completions": p.clean_completions if p else 0,
        "independent_completions": p.independent_completions if p else 0,
        "mastered": bool(p and p.mastered),
        "last_done_at": p.last_done_at.isoformat() if p and p.last_done_at else None,
        "most_struggled_step": stuck,
    }


async def get_progress(db: AsyncSession, user_id: int, task_id: str) -> TaskProgress | None:
    return (await db.execute(
        select(TaskProgress).where(TaskProgress.user_id == user_id, TaskProgress.task_id == task_id)
    )).scalar_one_or_none()


async def _get_or_create(db: AsyncSession, user_id: int, task_id: str) -> TaskProgress:
    p = await get_progress(db, user_id, task_id)
    if p is None:
        p = TaskProgress(user_id=user_id, task_id=task_id, attempts=0, completions=0, clean_completions=0,
                         independent_completions=0, mastered=False, struggle_by_step={})
        db.add(p)
        await db.flush()
    return p


async def all_progress(db: AsyncSession, user_id: int, s: Settings) -> list[dict]:
    rows = (await db.execute(select(TaskProgress).where(TaskProgress.user_id == user_id))).scalars().all()
    by_id = {r.task_id: r for r in rows}
    return [progress_dict(tid, by_id.get(tid), s) for tid in workflows.WORKFLOWS]


async def start_attempt(db: AsyncSession, user_id: int, task_id: str, s: Settings,
                        at_least: str | None = None) -> dict:
    workflows.get(task_id)  # allowlist check
    p = await _get_or_create(db, user_id, task_id)
    level = starting_level(p, s)
    if at_least in HELP_LEVELS and HELP_LEVELS.index(at_least) > HELP_LEVELS.index(level):
        level = at_least
    p.attempts += 1
    a = TaskAttempt(user_id=user_id, task_id=task_id, status="started", start_help_level=level, struggle_count=0)
    db.add(a)
    await db.commit()
    await db.refresh(a)
    return {"attempt_id": a.id, "task_id": task_id, "start_help_level": level,
            "progress": progress_dict(task_id, p, s)}


async def _own_attempt(db: AsyncSession, user_id: int, attempt_id: int) -> TaskAttempt:
    a = await db.get(TaskAttempt, attempt_id)
    if a is None or a.user_id != user_id:
        raise AppError(404, "attempt_not_found", "Task attempt not found")
    return a


async def record_struggle(db: AsyncSession, user_id: int, attempt_id: int, step_index: int,
                          current_level: str, s: Settings) -> dict:
    a = await _own_attempt(db, user_id, attempt_id)
    if a.status != "started":
        raise AppError(409, "attempt_closed", "This attempt is already finished")
    p = await _get_or_create(db, user_id, a.task_id)
    m = dict(p.struggle_by_step or {})
    m[str(step_index)] = m.get(str(step_index), 0) + 1
    p.struggle_by_step = m
    a.struggle_count += 1
    await db.commit()
    return {"attempt_id": a.id, "new_help_level": raise_level(current_level), "struggle_count": a.struggle_count}


async def complete_attempt(db: AsyncSession, user_id: int, attempt_id: int, s: Settings,
                           duration_ms: int | None, abandoned: bool = False) -> dict:
    a = await _own_attempt(db, user_id, attempt_id)
    if a.status != "started":
        raise AppError(409, "attempt_closed", "This attempt is already finished")
    p = await _get_or_create(db, user_id, a.task_id)
    a.ended_at = datetime.now(timezone.utc)
    a.duration_ms = duration_ms
    if abandoned:
        a.status = "abandoned"
        a.clean = False
        await db.commit()
        return {"attempt_id": a.id, "status": a.status, "progress": progress_dict(a.task_id, p, s),
                "celebration": None}

    was_mastered = p.mastered
    clean = a.struggle_count == 0
    a.status, a.clean = "completed", clean
    p.completions += 1
    p.last_done_at = a.ended_at
    if clean:
        p.clean_completions += 1
        if a.start_help_level == "none":
            p.independent_completions += 1
    if p.clean_completions >= s.ladder_clean_for_mastery:
        p.mastered = True
    await db.commit()

    wf = workflows.get(a.task_id)
    just = p.mastered and not was_mastered
    st = stage(p, s)
    emoji = STAGES[st][0]
    if just:
        ur, en = (f"شاباش! اب آپ {wf.title_ur} خود کر لیتی ہیں۔ {emoji}",
                  f"Well done! You can now do \"{wf.title_en}\" on your own. {emoji}")
    elif clean and a.start_help_level == "none":
        n = p.independent_completions
        ur, en = (f"آپ نے {wf.title_ur} {n} بار بغیر مدد کے کیا! {emoji}",
                  f"You did \"{wf.title_en}\" without help {n} time(s)! {emoji}")
    elif clean:
        ur, en = f"بہت اچھے! اگلی بار ہم کم مدد کریں گے۔ {emoji}", f"Great! Next time we will help a little less. {emoji}"
    else:
        ur, en = f"ہو گیا! ہر بار آسان ہو جائے گا۔ {emoji}", f"Done! It gets easier every time. {emoji}"
    return {
        "attempt_id": a.id,
        "status": a.status,
        "clean": clean,
        "progress": progress_dict(a.task_id, p, s),
        "celebration": {"just_mastered": just, "stage": st, "emoji": emoji, "message_ur": ur, "message_en": en},
    }


async def reset(db: AsyncSession, user_id: int) -> None:
    from sqlalchemy import delete
    await db.execute(delete(TaskAttempt).where(TaskAttempt.user_id == user_id))
    await db.execute(delete(TaskProgress).where(TaskProgress.user_id == user_id))
    await db.commit()


async def seed(db: AsyncSession, user_id: int, task_id: str, clean: int, s: Settings) -> dict:
    """Demo helper: pretend the task was done well `clean` times."""
    workflows.get(task_id)
    p = await _get_or_create(db, user_id, task_id)
    p.attempts = p.completions = p.clean_completions = clean
    p.mastered = clean >= s.ladder_clean_for_mastery
    p.last_done_at = datetime.now(timezone.utc)
    await db.commit()
    return progress_dict(task_id, p, s)
