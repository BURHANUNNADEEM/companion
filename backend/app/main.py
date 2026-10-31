"""FastAPI entrypoint. Run: uvicorn app.main:app --reload"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import assist, caregiver, consent, events, me, scam
from app.core.config import get_settings
from app.services.flow_engine import load_registry

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    load_registry()  # validates workflows.json against the allow-lists; fails fast if unsafe
    yield


def create_app() -> FastAPI:
    s = get_settings()
    app = FastAPI(
        title="Companion API",
        version="0.3.0",
        description="Backend for the Companion Android app (bilingual Urdu/English). See docs/API.md.",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware, allow_origins=s.cors_list, allow_methods=["*"], allow_headers=["*"],
        allow_credentials=False,
    )
    for r in (me.router, consent.router, events.router, assist.router, scam.router, caregiver.router):
        app.include_router(r, prefix=s.api_prefix)

    @app.get("/health", tags=["health"])
    async def health():
        return {"status": "ok"}

    return app


app = create_app()
