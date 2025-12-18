"""CreateSessionRequest model."""

from pydantic import BaseModel, Field


class CreateSessionRequest(BaseModel):
    parentID: str | None = None
    title: str | None = None
    bypass_mode: bool = Field(
        default=False,
        description="Enable bypass mode to skip all permission checks (DANGEROUS)"
    )
