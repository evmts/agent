"""ToolState models."""

from typing import Any, Literal

from pydantic import BaseModel

from .part_time import PartTime


class ToolStatePending(BaseModel):
    status: Literal["pending"] = "pending"
    input: dict[str, Any]
    raw: str


class ToolStateRunning(BaseModel):
    status: Literal["running"] = "running"
    input: dict[str, Any]
    title: str | None = None
    metadata: dict[str, Any] | None = None
    time: PartTime


class ToolStateCompleted(BaseModel):
    status: Literal["completed"] = "completed"
    input: dict[str, Any]
    output: str
    title: str | None = None
    metadata: dict[str, Any] | None = None
    time: PartTime


ToolState = ToolStatePending | ToolStateRunning | ToolStateCompleted
