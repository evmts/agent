"""Part models."""

from typing import Literal

from pydantic import BaseModel

from .part_time import PartTime
from .tool_state import ToolState


class TextPart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["text"] = "text"
    text: str
    time: PartTime | None = None


class ReasoningPart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["reasoning"] = "reasoning"
    text: str
    time: PartTime


class ToolPart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["tool"] = "tool"
    tool: str
    state: ToolState


class FilePart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["file"] = "file"
    mime: str
    url: str
    filename: str | None = None


Part = TextPart | ReasoningPart | ToolPart | FilePart
