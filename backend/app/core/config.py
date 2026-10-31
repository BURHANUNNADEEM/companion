"""Application settings, read from environment variables (see .env.example)."""
from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # --- runtime ---
    env: Literal["development", "test", "production"] = "development"
    api_prefix: str = "/api"
    cors_origins: str = "*"

    # --- database (Neon Postgres in production, SQLite allowed for local/test) ---
    database_url: str = "sqlite+aiosqlite:///./companion.db"

    # --- auth (F5) ---
    auth_mode: Literal["firebase", "dev"] = "dev"
    firebase_project_id: str = ""
    # Either a path to the service-account JSON, or the JSON itself (raw or base64).
    firebase_credentials: str = ""

    # --- LLM (F8) ---
    llm_enabled: bool = False
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.0-flash-lite"
    llm_timeout_seconds: float = 6.0
    llm_rate_per_minute: int = 10
    llm_min_confidence: float = 0.6

    # --- struggle detection (F2) - adjustable without a code change, served via /api/config ---
    struggle_threshold: float = 0.8
    struggle_w_backtracking: float = 0.8
    struggle_w_idle: float = 0.5
    struggle_w_repeated_taps: float = 0.8
    struggle_w_looping: float = 0.6
    struggle_w_no_completion: float = 0.4
    struggle_back_count: int = 3
    struggle_back_window_s: int = 20
    struggle_idle_s: int = 10
    struggle_repeat_taps: int = 3
    struggle_repeat_window_s: int = 5
    struggle_loop_visits: int = 3
    struggle_no_completion_s: int = 45
    struggle_cooldown_s: int = 60

    # --- suggestions (F3) ---
    suggestion_backoff_dismissals: int = 3
    suggestion_backoff_minutes: int = 30

    # --- caregiver (F9) ---
    invite_ttl_hours: int = 24
    inactivity_days_default: int = 2
    repeated_struggle_alert_count: int = 3
    admin_token: str = "change-me"

    # --- email (F9) ---
    email_backend: Literal["console", "smtp"] = "console"
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from: str = "Companion <no-reply@example.com>"
    smtp_use_tls: bool = True
    app_invite_url: str = "https://companion.example/invite"

    @model_validator(mode="after")
    def _guard_production(self) -> "Settings":
        if self.env == "production":
            if self.auth_mode == "dev":
                raise ValueError("AUTH_MODE=dev is not allowed when ENV=production")
            if self.admin_token in ("", "change-me"):
                raise ValueError("ADMIN_TOKEN must be set in production")
        return self

    @property
    def cors_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    def struggle_config(self) -> dict:
        return {
            "threshold": self.struggle_threshold,
            "cooldown_s": self.struggle_cooldown_s,
            "weights": {
                "backtracking": self.struggle_w_backtracking,
                "idle": self.struggle_w_idle,
                "repeated_taps": self.struggle_w_repeated_taps,
                "looping": self.struggle_w_looping,
                "no_completion": self.struggle_w_no_completion,
            },
            "rules": {
                "back_count": self.struggle_back_count,
                "back_window_s": self.struggle_back_window_s,
                "idle_s": self.struggle_idle_s,
                "repeat_taps": self.struggle_repeat_taps,
                "repeat_window_s": self.struggle_repeat_window_s,
                "loop_visits": self.struggle_loop_visits,
                "no_completion_s": self.struggle_no_completion_s,
            },
        }


@lru_cache
def get_settings() -> Settings:
    return Settings()
