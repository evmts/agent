"""SessionTime model."""

from pydantic import BaseModel


class SessionTime(BaseModel):
    created: float
    updated: float
    archived: float | None = None
