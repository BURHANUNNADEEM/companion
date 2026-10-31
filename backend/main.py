import asyncio
import logging
import sys

if sys.platform == "win32":  # psycopg async needs the selector loop on Windows
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import get_settings
from core.db import get_db
from core.errors import register_error_handlers
from routers import assist, consent, events, me, progress, scam, voice, workflows

logging.basicConfig(level=logging.INFO)
settings = get_settings()

app = FastAPI(
    title="Companion Backend",
    version="1.0.0",
    description="Help that fades: struggle detection, task guidance, scam checks. "
    "All /api routes need `Authorization: Bearer <Firebase ID token>`.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials="*" not in settings.cors_origin_list,
    allow_methods=["*"],
    allow_headers=["*"],
)
register_error_handlers(app)

for r in (me, consent, events, assist, scam, voice, workflows, progress):
    app.include_router(r.router)


@app.get("/health")
def health():
    return {"status": "ok", "gemini_configured": settings.gemini_enabled}


@app.get("/health/db")
async def health_db(db: AsyncSession = Depends(get_db)):
    await db.execute(text("SELECT 1"))
    return {"db": "ok"}
