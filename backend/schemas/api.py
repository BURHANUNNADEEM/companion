from typing import Literal

from pydantic import BaseModel, Field

HelpLevel = Literal["none", "nudge", "highlight", "full"]


class ProfileUpdate(BaseModel):
    display_name: str | None = Field(default=None, max_length=80)
    language: Literal["ur", "en"] | None = None


class ConsentIn(BaseModel):
    tracking: bool | None = None
    ai_processing: bool | None = None
    store_scam_text: bool | None = None


class StruggleIn(BaseModel):
    """Counters for the CURRENT window only. No content, no coordinates."""

    task_id: str | None = None
    attempt_id: int | None = None
    step_index: int | None = Field(default=None, ge=0)
    current_help_level: HelpLevel = "none"
    back_count: int = Field(default=0, ge=0)
    idle_seconds: float = Field(default=0, ge=0)
    max_same_target_taps: int = Field(default=0, ge=0)
    wrong_taps: int = Field(default=0, ge=0)
    max_screen_visits: int = Field(default=0, ge=0)
    distinct_screens: int = Field(default=0, ge=0)
    seconds_without_completion: float = Field(default=0, ge=0)
    median_step_ms: int | None = Field(default=None, ge=0)
    hour: int | None = Field(default=None, ge=0, le=23)


class SuggestionFeedbackIn(BaseModel):
    task_id: str | None = None
    outcome: Literal["accepted", "dismissed", "something_else"]


class ScamCheckIn(BaseModel):
    text: str = Field(min_length=1, max_length=5000)
    source: Literal["paste", "share", "ocr", "voice"] = "paste"


class VoiceIntentIn(BaseModel):
    transcript: str = Field(min_length=1, max_length=500)
    language: Literal["ur", "en", "auto"] = "auto"


class WorkflowResolveIn(BaseModel):
    contact_phone: str | None = Field(default=None, max_length=20)
    contact_id: str = Field(default="helper", pattern=r"^[a-zA-Z0-9_]{1,32}$")


class TaskStartIn(BaseModel):
    at_least: HelpLevel | None = None  # e.g. "highlight" when started from a suggestion


class TaskStruggleIn(BaseModel):
    step_index: int = Field(ge=0, le=50)
    current_help_level: HelpLevel = "none"


class TaskCompleteIn(BaseModel):
    duration_ms: int | None = Field(default=None, ge=0, le=3_600_000)
    abandoned: bool = False


class SeedIn(BaseModel):
    clean_completions: int = Field(ge=0, le=10)


class DeleteConfirm(BaseModel):
    confirm: Literal["DELETE"]
