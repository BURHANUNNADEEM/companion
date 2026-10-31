from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # --- existing (unchanged) ---
    database_url: str
    firebase_project_id: str

    # --- app ---
    app_env: str = "dev"  # dev | prod
    cors_origins: str = "*"  # comma-separated list, or "*"

    # Local testing only: accept "Bearer dev-<anything>" as a user id.
    # NEVER enable in production.
    dev_auth_enabled: bool = False

    # --- Gemini (optional; app works fully without it) ---
    gemini_api_key: str | None = None
    gemini_model: str = "gemini-2.5-flash"
    gemini_timeout_seconds: float = 8.0

    # --- struggle detection thresholds (change via env, no code change) ---
    struggle_backtrack_count: int = 3
    struggle_backtrack_window_s: int = 20
    struggle_idle_min_s: int = 8
    struggle_idle_max_s: int = 20
    struggle_idle_pace_multiplier: float = 2.5
    struggle_repeated_tap_count: int = 3
    struggle_loop_visits: int = 3
    struggle_no_completion_s: int = 45
    struggle_wrong_tap_count: int = 2
    struggle_trigger_threshold: float = 1.0

    # --- help ladder ---
    ladder_clean_for_highlight: int = 1
    ladder_clean_for_none: int = 3
    ladder_clean_for_mastery: int = 3

    # --- suggestions ---
    suggestions_max: int = 3
    suggestions_backoff_dismissals: int = 3
    suggestions_backoff_minutes: int = 10

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()] or ["*"]

    @property
    def gemini_enabled(self) -> bool:
        return bool(self.gemini_api_key)


@lru_cache
def get_settings() -> Settings:
    return Settings()
