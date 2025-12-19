"""UpdateSessionRequest model."""

from pydantic import BaseModel


class UpdateSessionRequest(BaseModel):
    title: str | None = None
    time: dict | None = None  # { archived: number }
    model: str | None = None
    reasoning_effort: str | None = None
    plugins: list[str] | None = None  # List of plugin names to activate
