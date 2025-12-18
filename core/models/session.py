"""Session model."""

from pydantic import BaseModel, Field

from .compaction_info import CompactionInfo
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
    fork_point: str | None = Field(
        default=None,
        description="Message ID where this session was forked from parent"
    )
    summary: SessionSummary | None = None
    revert: RevertInfo | None = None
    compaction: CompactionInfo | None = None
    token_count: int = Field(
        default=0,
        description="Current estimated token count for the session"
    )
    bypass_mode: bool = Field(
        default=False,
        description="If True, skip all permission checks (DANGEROUS - use with caution)"
    )
    model: str | None = Field(
        default=None,
        description="Model ID to use for this session (e.g., claude-opus-4-5-20251101)"
    )
    reasoning_effort: str | None = Field(
        default=None,
        description="Reasoning effort level: minimal, low, medium, or high"
    )
