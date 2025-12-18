"""Session model."""

from pydantic import BaseModel, Field

from .revert_info import RevertInfo
from .session_summary import SessionSummary
from .session_time import SessionTime


class Session(BaseModel):
    id: str
    projectID: str
    directory: str
    title: str
    version: str
    time: SessionTime
    parentID: str | None = None
    summary: SessionSummary | None = None
    revert: RevertInfo | None = None
    bypass_mode: bool = Field(
        default=False,
        description="If True, skip all permission checks (DANGEROUS - use with caution)"
    )
