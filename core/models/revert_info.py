"""RevertInfo model."""

from pydantic import BaseModel


class RevertInfo(BaseModel):
    messageID: str
    partID: str | None = None
    snapshot: str | None = None
    diff: str | None = None
