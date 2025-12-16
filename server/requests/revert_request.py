"""RevertRequest model."""

from pydantic import BaseModel


class RevertRequest(BaseModel):
    messageID: str
    partID: str | None = None
