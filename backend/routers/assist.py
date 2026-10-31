"""Struggle detection support + task suggestions."""

from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from core.auth import get_current_user
from core.config import Settings, get_settings
from core.db import get_db
from models import Event, User
from schemas.api import StruggleIn, SuggestionFeedbackIn
from services import privacy, progress, struggle, suggestions, workflows

router = APIRouter(prefix="/api", tags=["struggle & suggestions"])
CurrentUser = Annotated[User, Depends(get_current_user)]
DB = Annotated[AsyncSession, Depends(get_db)]
Cfg = Annotated[Settings, Depends(get_settings)]


@router.get("/struggle/config")
async def struggle_config(_: CurrentUser, s: Cfg):
    """Thresholds the app should use for on-device detection (tunable via env)."""
    return struggle.public_config(s)


@router.post("/struggle/evaluate")
async def struggle_evaluate(body: StruggleIn, user: CurrentUser, db: DB, s: Cfg):
    await privacy.require_tracking(db, user.id)
    if body.task_id:
        workflows.get(body.task_id)
    task_active = body.task_id is not None
    r = struggle.evaluate(
        s,
        back_count=body.back_count, idle_seconds=body.idle_seconds,
        max_same_target_taps=body.max_same_target_taps, wrong_taps=body.wrong_taps,
        max_screen_visits=body.max_screen_visits, distinct_screens=body.distinct_screens,
        seconds_without_completion=body.seconds_without_completion,
        median_step_ms=body.median_step_ms, task_active=task_active,
    )
    out = {**r, "action": "none", "new_help_level": body.current_help_level, "suggestions": None}
    if not r["triggered"]:
        return out

    db.add(Event(user_id=user.id, event_type="struggle_detected", item_id=body.task_id,
                 properties={"signals": r["signals"], "score": r["score"], "step": body.step_index}))
    if task_active:
        if body.attempt_id is not None and body.step_index is not None:
            res = await progress.record_struggle(db, user.id, body.attempt_id, body.step_index,
                                                 body.current_help_level, s)
            out["new_help_level"] = res["new_help_level"]
        else:
            await db.commit()
            out["new_help_level"] = progress.raise_level(body.current_help_level)
        out["action"] = "raise_help"
        out["message_ur"], out["message_en"] = "کیا میں مدد کروں؟", "Need a hand?"
    else:
        sug = await suggestions.suggest(db, user.id, s, hour=body.hour)
        if sug["suggestions"]:
            db.add(Event(user_id=user.id, event_type="suggestion_shown",
                         properties={"tasks": [x["task_id"] for x in sug["suggestions"]]}))
            out["action"] = "show_suggestions"
        await db.commit()
        out["suggestions"] = sug
    return out


@router.get("/suggestions")
async def get_suggestions(user: CurrentUser, db: DB, s: Cfg,
                          hour: Annotated[int | None, Query(ge=0, le=23)] = None,
                          last_task: str | None = None):
    return await suggestions.suggest(db, user.id, s, hour=hour, last_task=last_task)


@router.post("/suggestions/feedback", status_code=201)
async def suggestion_feedback(body: SuggestionFeedbackIn, user: CurrentUser, db: DB):
    await privacy.require_tracking(db, user.id)
    if body.task_id:
        workflows.get(body.task_id)
    etype = {"accepted": "suggestion_accepted", "dismissed": "suggestion_dismissed",
             "something_else": "something_else_tapped"}[body.outcome]
    db.add(Event(user_id=user.id, event_type=etype, item_id=body.task_id, properties={}))
    await db.commit()
    return {"ok": True}
