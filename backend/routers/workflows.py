from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from core.auth import get_current_user
from core.config import Settings, get_settings
from core.db import get_db
from models import Event, User
from schemas.api import WorkflowResolveIn
from services import progress, workflows

router = APIRouter(prefix="/api/workflows", tags=["navigation workflows"])
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("")
async def list_workflows(_: CurrentUser):
    return {"workflows": [workflows.to_dict(w, include_steps=False) for w in workflows.WORKFLOWS.values()]}


@router.get("/{workflow_id}")
async def get_workflow(workflow_id: str, user: CurrentUser,
                       db: Annotated[AsyncSession, Depends(get_db)],
                       s: Annotated[Settings, Depends(get_settings)],
                       contact_id: Annotated[str, Query(pattern=r"^[a-zA-Z0-9_]{1,32}$")] = "helper"):
    wf = workflows.get(workflow_id)
    p = await progress.get_progress(db, user.id, workflow_id)
    d = workflows.to_dict(wf, contact_id=contact_id)
    d["starting_help_level"] = progress.starting_level(p, s)
    return d


@router.post("/{workflow_id}/resolve")
async def resolve_workflow(workflow_id: str, body: WorkflowResolveIn, user: CurrentUser,
                           db: Annotated[AsyncSession, Depends(get_db)]):
    """Returns a validated launch target from a fixed allowlist. The app opens it only
    after the user taps the final step; the backend never performs device actions."""
    wf = workflows.get(workflow_id)
    launch = workflows.resolve_launch(wf, body.contact_phone)
    db.add(Event(user_id=user.id, event_type="nav_resolved", item_id=wf.id,
                 properties={"kind": launch["kind"]}))  # never the phone number
    await db.commit()
    return {"workflow_id": wf.id, "launch": launch,
            "steps": workflows.to_dict(wf, contact_id=body.contact_id)["steps"]}
