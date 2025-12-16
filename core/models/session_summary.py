"""SessionSummary model."""

from pydantic import BaseModel

from .file_diff import FileDiff


class SessionSummary(BaseModel):
    additions: int
    deletions: int
    files: int
    diffs: list[FileDiff] | None = None
