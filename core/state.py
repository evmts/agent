"""
In-memory state storage.

This module contains the global state for sessions, messages, and snapshots.
In a production system, this could be replaced with a database-backed implementation.
"""

import asyncio
from typing import Any

from snapshot import Snapshot

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
