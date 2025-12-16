"""ForkRequest model."""

from pydantic import BaseModel


class ForkRequest(BaseModel):
    messageID: str | None = None
