"""ForkRequest model."""

from pydantic import BaseModel


class ForkRequest(BaseModel):
    messageID: str | None = None
    title: str | None = None
