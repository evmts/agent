"""CreateSessionRequest model."""

from pydantic import BaseModel


class CreateSessionRequest(BaseModel):
    parentID: str | None = None
    title: str | None = None
