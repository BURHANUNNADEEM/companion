import os
import tempfile

_DB = os.path.join(tempfile.mkdtemp(), "test.db")
os.environ.update({
    "ENV": "test",
    "AUTH_MODE": "dev",
    "DATABASE_URL": f"sqlite+aiosqlite:///{_DB}",
    "LLM_ENABLED": "false",
    "EMAIL_BACKEND": "console",
    "ADMIN_TOKEN": "test-admin",
})

import httpx  # noqa: E402
import pytest  # noqa: E402

from app.core.db import Base, engine  # noqa: E402
from app.core.ratelimit import limiter  # noqa: E402
from app.main import app  # noqa: E402
from app.services import email as email_service  # noqa: E402
from app.services import llm  # noqa: E402


@pytest.fixture(autouse=True)
async def fresh_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    limiter.reset()
    email_service.OUTBOX.clear()
    llm._cache.data.clear()
    llm._fake_transport = None
    yield


@pytest.fixture
async def client():
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


def H(uid: str, email: str | None = None) -> dict:
    token = f"dev:{uid}:{email}" if email else f"dev:{uid}"
    return {"Authorization": f"Bearer {token}"}


async def onboard(client, uid: str, role: str, *, lang="ur", email=None, sharing=False, tracking=True,
                  store_text=False, name=None):
    h = H(uid, email)
    r = await client.put("/api/me/role", json={"role": role}, headers=h)
    assert r.status_code == 200, r.text
    await client.put("/api/me/language", json={"language": lang}, headers=h)
    if name:
        await client.put("/api/me/profile", json={"display_name": name}, headers=h)
    r = await client.put("/api/consent", json={
        "activity_tracking": tracking, "caregiver_sharing": sharing,
        "scam_text_storage": store_text, "ai_disclosure": True,
    }, headers=h)
    assert r.status_code == 200
    return h


@pytest.fixture
def llm_on(monkeypatch):
    """Enable the LLM path with a fake Gemini transport. Usage: llm_on(lambda prompt, schema: {...})."""
    from app.core.config import get_settings

    s = get_settings()
    monkeypatch.setattr(s, "llm_enabled", True)

    def _set(fn):
        llm._fake_transport = fn

    yield _set
    llm._fake_transport = None
