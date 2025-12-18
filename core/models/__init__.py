"""
Domain models for the agent platform.

These are the core data structures used throughout the application.
"""

from .compaction_info import CompactionInfo, CompactionResult
from .file_diff import FileDiff
from .ghost_commit_info import GhostCommitInfo
from .message import AssistantMessage, Message, UserMessage
from .message_time import MessageTime
from .model_info import ModelInfo
from .part import FilePart, Part, ReasoningPart, TextPart, ToolPart
from .part_time import PartTime
from .path_info import PathInfo
from .revert_info import RevertInfo
from .session import Session
from .session_summary import SessionSummary
from .session_time import SessionTime
from .token_info import TokenInfo
from .tool_state import ToolState, ToolStateCompleted, ToolStatePending, ToolStateRunning
from .utils import gen_id

__all__ = [
    # Utils
    "gen_id",
    # Time models
    "SessionTime",
    "MessageTime",
    "PartTime",
    # Session models
    "FileDiff",
    "SessionSummary",
    "RevertInfo",
    "CompactionInfo",
    "CompactionResult",
    "GhostCommitInfo",
    "Session",
    # Provider info
    "ModelInfo",
    "TokenInfo",
    "PathInfo",
    # Message models
    "UserMessage",
    "AssistantMessage",
    "Message",
    # Part models
    "TextPart",
    "ReasoningPart",
    "ToolStatePending",
    "ToolStateRunning",
    "ToolStateCompleted",
    "ToolState",
    "ToolPart",
    "FilePart",
    "Part",
]
