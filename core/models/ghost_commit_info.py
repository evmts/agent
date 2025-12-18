"""Ghost commit info model."""

from pydantic import BaseModel, Field


class GhostCommitInfo(BaseModel):
    """Information about ghost commits in a session."""

    enabled: bool = Field(
        default=False,
        description="Whether ghost commits are enabled for this session"
    )
    turn_number: int = Field(
        default=0,
        description="Current turn number"
    )
    commit_refs: list[str] = Field(
        default_factory=list,
        description="List of ghost commit hashes"
    )
