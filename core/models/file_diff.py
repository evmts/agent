"""FileDiff model."""

from pydantic import BaseModel


class FileDiff(BaseModel):
    file: str
    before: str
    after: str
    additions: int
    deletions: int
