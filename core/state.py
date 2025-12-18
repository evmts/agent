"""
In-memory state storage.

This module contains the global state for sessions, messages, and snapshots.
In a production system, this could be replaced with a database-backed implementation.
"""

import asyncio
from typing import Any

from snapshot import Snapshot
from agent.tools.file_time import FileTimeTracker

from .models import Session


# =============================================================================
# Session Storage
# =============================================================================

sessions: dict[str, Session] = {}
session_messages: dict[str, list[dict[str, Any]]] = {}  # sessionID -> [{info, parts}]


# =============================================================================
# Snapshot Storage
# =============================================================================

session_snapshots: dict[str, Snapshot] = {}  # sessionID -> Snapshot instance
session_snapshot_history: dict[str, list[str]] = {}  # sessionID -> [tree SHA hashes]


# =============================================================================
# Task Management
# =============================================================================

active_tasks: dict[str, asyncio.Task[Any]] = {}  # sessionID -> running task
session_subtasks: dict[str, list[dict[str, Any]]] = {}  # sessionID -> list of subtask results


# =============================================================================
# File Time Tracking
# =============================================================================

session_file_trackers: dict[str, FileTimeTracker] = {}  # sessionID -> FileTimeTracker


def get_file_tracker(session_id: str) -> FileTimeTracker:
    """
    Get or create a file time tracker for a session.

    Args:
        session_id: Session identifier

    Returns:
        FileTimeTracker instance for the session
    """
    if session_id not in session_file_trackers:
        session_file_trackers[session_id] = FileTimeTracker()
    return session_file_trackers[session_id]
