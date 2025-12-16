"""TokenInfo model."""

from pydantic import BaseModel


class TokenInfo(BaseModel):
    input: int
    output: int
    reasoning: int = 0
    cache: dict[str, int] | None = None
