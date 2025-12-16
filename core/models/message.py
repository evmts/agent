"""Message models."""

from typing import Any, Literal

from pydantic import BaseModel

from .message_time import MessageTime
from .model_info import ModelInfo
from .path_info import PathInfo
from .token_info import TokenInfo


class UserMessage(BaseModel):
    id: str
    sessionID: str
    role: Literal["user"] = "user"
    time: MessageTime
    agent: str
    model: ModelInfo
    system: str | None = None
    tools: dict[str, bool] | None = None


class AssistantMessage(BaseModel):
    id: str
    sessionID: str
    role: Literal["assistant"] = "assistant"
    time: MessageTime
    parentID: str
    modelID: str
    providerID: str
    mode: str
    path: PathInfo
    cost: float
    tokens: TokenInfo
    finish: str | None = None
    summary: bool | None = None
    error: dict[str, Any] | None = None


Message = UserMessage | AssistantMessage
