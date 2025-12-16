"""
Core business logic package.

This package contains transport-agnostic business logic for the agent platform.
The server package provides HTTP bindings around these core operations.
"""

from .events import Event, EventBus, NullEventBus
from .exceptions import CoreError, InvalidOperationError, NotFoundError
from .models import (
    AssistantMessage,
    FileDiff,
    FilePart,
    Message,
    MessageTime,
    ModelInfo,
    Part,
    PartTime,
    PathInfo,
    ReasoningPart,
    RevertInfo,
    Session,
    SessionSummary,
    SessionTime,
    TextPart,
    TokenInfo,
    ToolPart,
    ToolState,
    ToolStateCompleted,
    ToolStatePending,
    ToolStateRunning,
    UserMessage,
    gen_id,
)
from .messages import get_message, list_messages, send_message
from .sessions import (
    abort_session,
    create_session,
    delete_session,
    fork_session,
    get_session,
    get_session_diff,
    list_sessions,
    revert_session,
    unrevert_session,
    update_session,
)
from .snapshots import compute_diff, init_snapshot, restore_snapshot, track_snapshot

__all__ = [
    # Exceptions
    "CoreError",
    "NotFoundError",
    "InvalidOperationError",
    # Events
    "Event",
    "EventBus",
    "NullEventBus",
    # Models
    "Session",
    "SessionTime",
    "SessionSummary",
    "RevertInfo",
    "FileDiff",
    "Message",
    "UserMessage",
    "AssistantMessage",
    "MessageTime",
    "Part",
    "TextPart",
    "ReasoningPart",
    "ToolPart",
    "FilePart",
    "ToolState",
    "ToolStatePending",
    "ToolStateRunning",
    "ToolStateCompleted",
    "PartTime",
    "ModelInfo",
    "TokenInfo",
    "PathInfo",
    "gen_id",
    # Session operations
    "create_session",
    "get_session",
    "list_sessions",
    "update_session",
    "delete_session",
    "fork_session",
    "revert_session",
    "unrevert_session",
    "abort_session",
    "get_session_diff",
    # Message operations
    "list_messages",
    "get_message",
    "send_message",
    # Snapshot operations
    "init_snapshot",
    "track_snapshot",
    "compute_diff",
    "restore_snapshot",
]
