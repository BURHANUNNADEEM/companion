from datetime import datetime

from pydantic import BaseModel, Field


class EventIn(BaseModel):
    event_type: str = Field(min_length=1, max_length=64)
    item_id: str | None = Field(default=None, max_length=128)
    properties: dict = Field(default_factory=dict)
    occurred_at: datetime | None = None  # client time; server time used if omitted


class EventBatchIn(BaseModel):
    session_id: str | None = Field(default=None, max_length=64)
    events: list[EventIn] = Field(min_length=1, max_length=500)
