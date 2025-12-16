"""UpdateSessionRequest model."""

from pydantic import BaseModel


class UpdateSessionRequest(BaseModel):
    title: str | None = None
    time: dict | None = None  # { archived: number }
