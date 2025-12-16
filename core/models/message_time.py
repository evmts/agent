"""MessageTime model."""

from pydantic import BaseModel


class MessageTime(BaseModel):
    created: float
    completed: float | None = None
