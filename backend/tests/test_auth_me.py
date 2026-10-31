import pytest

from tests.conftest import H


async def test_missing_token_is_401(client):
    assert (await client.get("/api/me")).status_code == 401
    assert (await client.get("/api/me", headers={"Authorization": "Bearer nonsense"})).status_code == 401


async def test_first_login_creates_user_without_role(client):
    r = await client.get("/api/me", headers=H("u1", "a@b.com"))
    assert r.status_code == 200
    body = r.json()
    assert body["role"] is None and body["language"] == "ur" and body["email"] == "a@b.com"
    assert body["consent"]["completed"] is False


async def test_role_chosen_once_and_trusted_from_server(client):
    h = H("u2")
    assert (await client.put("/api/me/role", json={"role": "parent"}, headers=h)).json()["role"] == "parent"
    assert (await client.put("/api/me/role", json={"role": "parent"}, headers=h)).status_code == 200
    assert (await client.put("/api/me/role", json={"role": "caregiver"}, headers=h)).status_code == 409
    assert (await client.put("/api/me/role", json={"role": "admin"}, headers=h)).status_code == 422
    # role-gated endpoint
    assert (await client.get("/api/caregiver/summary", headers=h)).status_code == 403


async def test_language_switch(client):
    h = H("u3")
    assert (await client.put("/api/me/language", json={"language": "en"}, headers=h)).json()["language"] == "en"
    assert (await client.put("/api/me/language", json={"language": "fr"}, headers=h)).status_code == 422


def test_production_refuses_dev_auth():
    from app.core.config import Settings

    with pytest.raises(ValueError):
        Settings(env="production", auth_mode="dev", admin_token="x")
    with pytest.raises(ValueError):
        Settings(env="production", auth_mode="firebase", admin_token="change-me")
    Settings(env="production", auth_mode="firebase", admin_token="strong-secret")


def test_neon_url_normalisation():
    from app.core.db import normalize_database_url

    url, args = normalize_database_url("postgresql://u:p@ep-x.neon.tech/db?sslmode=require&channel_binding=require")
    assert url.startswith("postgresql+asyncpg://") and "sslmode" not in url and "channel_binding" not in url
    assert args == {"ssl": "require"}


async def test_config_exposes_adjustable_struggle_threshold(client, monkeypatch):
    from app.core.config import get_settings

    r = await client.get("/api/config")
    assert r.json()["struggle"]["threshold"] == 0.8
    monkeypatch.setattr(get_settings(), "struggle_threshold", 1.7)  # e.g. STRUGGLE_THRESHOLD env var
    assert (await client.get("/api/config")).json()["struggle"]["threshold"] == 1.7
