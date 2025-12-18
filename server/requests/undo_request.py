"""Undo request model."""

from pydantic import BaseModel, Field


class UndoRequest(BaseModel):
    """Request to undo N turns in a session."""

    count: int = Field(
        default=1,
        ge=1,
        description="Number of turns to undo (must be >= 1)"
    )


class UndoResult(BaseModel):
    """Result of undo operation."""

    turns_undone: int = Field(
        description="Number of turns actually undone"
    )
    messages_removed: int = Field(
        description="Number of messages removed from history"
    )
    files_reverted: list[str] = Field(
        description="List of files that were reverted"
    )
    snapshot_restored: str | None = Field(
        default=None,
        description="Snapshot hash that was restored to"
    )
