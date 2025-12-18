"""Permission system models."""

import time
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class Level(str, Enum):
    """Permission level for operations."""

    ASK = "ask"
    ALLOW = "allow"
    DENY = "deny"


class Action(str, Enum):
    """User action in response to permission request."""

    APPROVE_ONCE = "once"
    APPROVE_ALWAYS = "always"
    DENY = "deny"
    APPROVE_PATTERN = "pattern"


class BashPermission(BaseModel):
    """Bash permission configuration with pattern-based rules."""

    default: Level = Level.ASK
    patterns: dict[str, Level] = Field(default_factory=dict)


class PermissionsConfig(BaseModel):
    """Permission configuration for all tool types."""

    edit: Level = Level.ASK
    bash: BashPermission = Field(default_factory=BashPermission)
    webfetch: Level = Level.ALLOW


class Request(BaseModel):
    """Permission request for a sensitive operation."""

    id: str
    session_id: str
    message_id: str
    call_id: str | None = None
    operation: str  # "bash", "edit", "webfetch"
    details: dict[str, Any]
    is_dangerous: bool = False
    warning: str | None = None
    requested_at: float = Field(default_factory=time.time)


class Response(BaseModel):
    """User response to a permission request."""

    request_id: str
    action: Action
    pattern: str | None = None  # For "pattern" action
    created_at: float = Field(default_factory=time.time)
