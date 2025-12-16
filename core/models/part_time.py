"""PartTime model."""

from pydantic import BaseModel


class PartTime(BaseModel):
    start: float
    end: float | None = None
