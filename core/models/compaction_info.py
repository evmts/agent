"""Compaction information model."""

from pydantic import BaseModel, Field


class CompactionInfo(BaseModel):
    """Information about conversation compaction."""

    last_compacted: float | None = Field(
        default=None,
        description="Timestamp of last compaction"
    )
    total_compactions: int = Field(
        default=0,
        description="Total number of compactions performed"
    )
    messages_compacted: int = Field(
        default=0,
        description="Total number of messages compacted"
    )
    tokens_saved: int = Field(
        default=0,
        description="Total tokens saved through compaction"
    )


class CompactionResult(BaseModel):
    """Result of a compaction operation."""

    compacted: bool = Field(
        description="Whether compaction was performed"
    )
    reason: str | None = Field(
        default=None,
        description="Reason if compaction was not performed"
    )
    messages_removed: int = Field(
        default=0,
        description="Number of messages removed during compaction"
    )
    tokens_before: int = Field(
        default=0,
        description="Token count before compaction"
    )
    tokens_after: int = Field(
        default=0,
        description="Token count after compaction"
    )
    summary: str | None = Field(
        default=None,
        description="Generated summary of compacted messages"
    )
