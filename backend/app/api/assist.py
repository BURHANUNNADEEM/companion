"""/api/config, /api/suggestions, /api/voice/intent, /api/navigation/* (F2, F3, F7, F8, F10)."""
from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_current_user
from app.core.config import get_settings
from app.core.db import get_db
from app.models import User
from app.services import flow_engine
from app.services.flow_engine import FlowError, PlanRequest, build_plan, refused_plan
from app.services.i18n import both, lang_or_default
from app.services.intent import understand
from app.services.suggestions import backoff_state, load_history, rank_tasks
from app.services.tasks import HOME_TILES, TASKS, is_task, task_view

router = APIRouter()


# ---------------- config (F2: thresholds adjustable without a code change) ----------------
@router.get("/config", tags=["config"])
async def get_config():
    s = get_settings()
    return {
        "struggle": s.struggle_config(),
        "home_tiles": [task_view(t, "en") | {"text": None} for t in HOME_TILES],
        "llm_enabled": s.llm_enabled and bool(s.gemini_api_key),
        "languages": ["ur", "en"],
    }


# ---------------- suggestions (F3) ----------------
@router.get("/suggestions", tags=["suggestions"])
async def get_suggestions(
    hour: int | None = Query(default=None, ge=0, le=23),
    last_task: str | None = Query(default=None, max_length=32),
    k: int = Query(default=3, ge=1, le=3),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    lang = lang_or_default(user.language)
    hour = datetime.now().hour if hour is None else hour
    history, accepted, dismissed, outcomes = await load_history(db, user.id)
    backoff = backoff_state(outcomes)
    if backoff["active"]:
        return {"suggestions": [], "something_else": True, "backoff": backoff}
    last = last_task if is_task(last_task) else (history[-1].task if history else None)
    ranked = rank_tasks(history, hour, last, accepted, dismissed, k=k)
    prompt = {"en": "Need a hand? Maybe one of these:", "ur": "کیا مدد چاہیے؟ شاید ان میں سے کوئی:"}
    return {
        "suggestions": [task_view(t, lang) | {"rank": i + 1} for i, t in enumerate(ranked)],
        "something_else": True,
        "something_else_label": {"en": "Something else", "ur": "کچھ اور"},
        "prompt": prompt,
        "not_now_label": {"en": "Not now", "ur": "ابھی نہیں"},
        "backoff": backoff,
        "is_default": not history,
    }


# ---------------- voice intent (F7/F8) ----------------
class VoiceIn(BaseModel):
    transcript: str = Field(min_length=1, max_length=500)
    locale: str | None = Field(default=None, max_length=10)


@router.post("/voice/intent", tags=["voice"])
async def voice_intent(body: VoiceIn, user: User = Depends(get_current_user)):
    lang = lang_or_default(user.language)
    res = await understand(user.id, body.transcript)
    task = None
    if res.workflow_id:
        task = flow_engine.workflows_by_id()[res.workflow_id]["task"]
        expl = None
        if res.explanation:
            en = flow_engine.sanitize_explanation(res.explanation.get("en"))
            ur = flow_engine.sanitize_explanation(res.explanation.get("ur"))
            expl = {"en": en, "ur": ur} if en and ur else None
        if expl is None:
            expl = flow_engine.workflows_by_id()[res.workflow_id]["intro_default"]
        return {
            "task": task,
            "workflow_id": res.workflow_id,
            "slots": res.slots,
            "confidence": res.confidence,
            "source": res.source,
            "explanation": expl,
            "text": expl[lang],
        }
    msg = both("nav.refused.unknown")
    return {
        "task": None,
        "workflow_id": None,
        "slots": {},
        "confidence": res.confidence,
        "source": res.source,
        "explanation": msg,
        "text": msg[lang],
        "fallback_tasks": [task_view(t, lang) for t in HOME_TILES],
    }


# ---------------- navigation engine (F10) ----------------
class PlanIn(BaseModel):
    utterance: str | None = Field(default=None, max_length=500)
    workflow_id: str | None = Field(default=None, max_length=64)
    task: str | None = Field(default=None, max_length=32)
    slots: dict = Field(default_factory=dict)


@router.get("/navigation/workflows", tags=["navigation"])
async def list_workflows(user: User = Depends(get_current_user)):
    lang = lang_or_default(user.language)
    reg = flow_engine.load_registry()
    return {
        "limits": reg["limits"],
        "workflows": [
            {"id": w["id"], "task": w["task"], "title": w["title"], "text": w["title"][lang],
             "steps": len(w["steps"]), "tier2_skill": w.get("tier2_skill")}
            for w in reg["workflows"]
        ],
    }


@router.post("/navigation/plan", tags=["navigation"])
async def navigation_plan(body: PlanIn, user: User = Depends(get_current_user)):
    """LLM/rules understand -> Flow Engine validates -> safe ordered steps with targets, arrows, hints."""
    lang = lang_or_default(user.language)
    workflow_id, slots, explanation, source = body.workflow_id, dict(body.slots), None, "direct"
    if not workflow_id and body.task:
        if body.task not in TASKS:
            raise HTTPException(422, "unknown_task")
        workflow_id = TASKS[body.task]["workflow"]
    if not workflow_id:
        if not body.utterance:
            raise HTTPException(422, "utterance_or_workflow_required")
        # Secret/money topics are refused before anything else, even if no workflow matches.
        if flow_engine.is_sensitive(body.utterance, None, {}) and not _is_plain_call(body.utterance):
            return refused_plan("sensitive", lang)
        res = await understand(user.id, body.utterance)
        if not res.workflow_id:
            return refused_plan("unknown", lang)
        workflow_id, source, explanation = res.workflow_id, res.source, res.explanation
        slots = {**res.slots, **slots}
    try:
        return build_plan(PlanRequest(workflow_id=workflow_id, slots=slots, utterance=body.utterance or "",
                                      explanation=explanation, language=lang, source=source))
    except FlowError as exc:
        if str(exc) == "unknown_workflow":
            return refused_plan("unknown", lang)
        raise HTTPException(422, f"invalid_plan: {exc}") from exc


def _is_plain_call(utterance: str) -> bool:
    from app.services.intent import match_rules

    r = match_rules(utterance)
    return r.workflow_id == "call_contact" and not flow_engine.is_sensitive(utterance, "call_contact", {})
