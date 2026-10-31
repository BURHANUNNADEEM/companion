from pydantic import BaseModel, Field


class EventIn(BaseModel):
    event_type: str
    item_id: str | None = None
    properties: dict = Field(default_factory=dict)