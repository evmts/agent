"""PromptRequest model."""

from pydantic import BaseModel

from core import ModelInfo


class PromptRequest(BaseModel):
    parts: list[dict]  # TextPartInput | FilePartInput
    messageID: str | None = None
    model: ModelInfo | None = None
    agent: str | None = None
    noReply: bool | None = None
    system: str | None = None
    tools: dict[str, bool] | None = None
