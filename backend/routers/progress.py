from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from core.auth import get_current_user
from core.config import Settings, get_settings
from core.db import get_db
from models import User
from schemas.api import SeedIn, TaskCompleteIn, TaskStartIn, TaskStruggleIn
from services import progress, workflows

router = APIRouter(prefix="/api", tags=["progress & tasks"])
CurrentUser = Annotated[User, Depends(get_current_user)]
DB = Annotated[AsyncSession, Depends(get_db)]
Cfg = Annotated[Settings, Depends(get_settings)]


@router.get("/progress")
async def all_progress(user: CurrentUser, db: DB, s: Cfg):
    items = await progress.all_progress(db, user.id, s)
    return {
        "tasks": items,
        "summary": {
            "confident": [t["task_id"] for t in items if t["stage"] == "confident"],
            "learning": [t["task_id"] for t in items if t["stage"] in ("learning", "getting_there")],
            "not_tried": [t["task_id"] for t in items if t["stage"] == "new"],
            "total_independent_completions": sum(t["independent_completions"] for t in items),
        },
    }


@router.get("/progress/{task_id}")
async def task_progress(task_id: str, user: CurrentUser, db: DB, s: Cfg):
    workflows.get(task_id)
    return progress.progress_dict(task_id, await progress.get_progress(db, user.id, task_id), s)


@router.post("/tasks/{task_id}/start", status_code=201)
async def start_task(task_id: str, user: CurrentUser, db: DB, s: Cfg, body: TaskStartIn | None = None):
    return await progress.start_attempt(db, user.id, task_id, s, at_least=body.at_least if body else None)


@router.post("/tasks/attempts/{attempt_id}/struggle")
async def task_struggle(attempt_id: int, body: TaskStruggleIn, user: CurrentUser, db: DB, s: Cfg):
    return await progress.record_struggle(db, user.id, attempt_id, body.step_index, body.current_help_level, s)


@router.post("/tasks/attempts/{attempt_id}/complete")
async def complete_task(attempt_id: int, body: TaskCompleteIn, user: CurrentUser, db: DB, s: Cfg):
    return await progress.complete_attempt(db, user.id, attempt_id, s, body.duration_ms, body.abandoned)


@router.post("/progress/reset")
async def reset_progress(user: CurrentUser, db: DB):
    """Demo helper: clears progress and attempts (keeps consent and events)."""
    await progress.reset(db, user.id)
    return {"ok": True}


@router.post("/progress/{task_id}/seed")
async def seed_progress(task_id: str, body: SeedIn, user: CurrentUser, db: DB, s: Cfg):
    """Demo helper: jump to 'attempt N' without doing the task N times."""
    return await progress.seed(db, user.id, task_id, body.clean_completions, s)
