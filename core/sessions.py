"""
Session operations.

Provides functions for managing sessions including CRUD operations,
forking, reverting, and diff computation.
"""

import logging
import time

from .events import Event, EventBus
from .exceptions import InvalidOperationError, NotFoundError
from .models import (
    FileDiff,
    RevertInfo,
    Session,
    SessionSummary,
    SessionTime,
    gen_id,
)
from .snapshots import cleanup_snapshots, compute_diff, init_snapshot, restore_snapshot
from .state import (
    active_tasks,
    session_messages,
    session_snapshot_history,
    sessions,
)

logger = logging.getLogger(__name__)


# =============================================================================
# Constants
# =============================================================================

DEFAULT_PROJECT_ID = "default"
DEFAULT_VERSION = "1.0.0"
DEFAULT_SESSION_TITLE = "New Session"


# =============================================================================
# Session CRUD
# =============================================================================


async def create_session(
    directory: str,
    event_bus: EventBus,
    title: str | None = None,
    parent_id: str | None = None,
) -> Session:
    """
    Create a new session.

    Args:
        directory: Working directory for the session
        event_bus: EventBus for publishing events
        title: Optional session title
        parent_id: Optional parent session ID

    Returns:
        The created session
    """
    now = time.time()
    session = Session(
        id=gen_id("ses_"),
        projectID=DEFAULT_PROJECT_ID,
        directory=directory,
        title=title or DEFAULT_SESSION_TITLE,
        version=DEFAULT_VERSION,
        time=SessionTime(created=now, updated=now),
        parentID=parent_id,
    )
    sessions[session.id] = session
    session_messages[session.id] = []

    # Initialize snapshot tracking
    init_snapshot(session.id, directory)

    logger.info("Session created: %s", session.id)

    await event_bus.publish(
        Event(type="session.created", properties={"info": session.model_dump()})
    )
    return session


def get_session(session_id: str) -> Session:
    """
    Get a session by ID.

    Args:
        session_id: The session ID

    Returns:
        The session

    Raises:
        NotFoundError: If the session is not found
    """
    if session_id not in sessions:
        raise NotFoundError("Session", session_id)
    return sessions[session_id]


def list_sessions() -> list[Session]:
    """
    List all sessions sorted by most recently updated.

    Returns:
        List of sessions sorted by update time (newest first)
    """
    return sorted(sessions.values(), key=lambda s: s.time.updated, reverse=True)


async def update_session(
    session_id: str,
    event_bus: EventBus,
    title: str | None = None,
    archived: float | None = None,
) -> Session:
    """
    Update a session's title or archived status.

    Args:
        session_id: The session ID
        event_bus: EventBus for publishing events
        title: New title (optional)
        archived: Archived timestamp (optional)

    Returns:
        The updated session

    Raises:
        NotFoundError: If the session is not found
    """
    session = get_session(session_id)

    if title is not None:
        session.title = title
    if archived is not None:
        session.time.archived = archived
    session.time.updated = time.time()
    sessions[session_id] = session

    await event_bus.publish(
        Event(type="session.updated", properties={"info": session.model_dump()})
    )
    return session


async def delete_session(session_id: str, event_bus: EventBus) -> bool:
    """
    Delete a session.

    Args:
        session_id: The session ID
        event_bus: EventBus for publishing events

    Returns:
        True if deleted successfully

    Raises:
        NotFoundError: If the session is not found
    """
    if session_id not in sessions:
        raise NotFoundError("Session", session_id)

    logger.info("Deleting session: %s", session_id)

    session = sessions.pop(session_id)
    session_messages.pop(session_id, None)
    cleanup_snapshots(session_id)

    await event_bus.publish(
        Event(type="session.deleted", properties={"info": session.model_dump()})
    )
    return True


# =============================================================================
# Session Actions
# =============================================================================


def abort_session(session_id: str) -> bool:
    """
    Abort an active session task.

    Args:
        session_id: The session ID

    Returns:
        True if aborted successfully

    Raises:
        NotFoundError: If the session is not found
    """
    if session_id not in sessions:
        raise NotFoundError("Session", session_id)

    if session_id in active_tasks:
        logger.info("Aborting session task: %s", session_id)
        active_tasks[session_id].cancel()
        del active_tasks[session_id]

    return True


def get_session_diff(
    session_id: str, message_id: str | None = None
) -> list[FileDiff]:
    """
    Get file diffs for a session.

    Args:
        session_id: The session ID
        message_id: Optional message ID to diff up to

    Returns:
        List of file diffs

    Raises:
        NotFoundError: If the session is not found
    """
    if session_id not in sessions:
        raise NotFoundError("Session", session_id)

    history = session_snapshot_history.get(session_id, [])

    if len(history) < 2:
        # Fall back to cached summary diffs
        session = sessions[session_id]
        if session.summary and session.summary.diffs:
            return session.summary.diffs
        return []

    # Determine target index based on message_id
    if message_id:
        messages = session_messages.get(session_id, [])
        target_index = None
        for i, msg in enumerate(messages):
            if msg["info"]["id"] == message_id:
                target_index = i
                break
        if target_index is not None and target_index < len(history):
            return compute_diff(session_id, history[0], history[target_index])

    # Default: diff from session start to current
    return compute_diff(session_id, history[0], history[-1])


async def fork_session(
    session_id: str,
    event_bus: EventBus,
    message_id: str | None = None,
) -> Session:
    """
    Fork a session at a specific message.

    Args:
        session_id: The session ID to fork
        event_bus: EventBus for publishing events
        message_id: Optional message ID to fork at

    Returns:
        The new forked session

    Raises:
        NotFoundError: If the session is not found
    """
    parent = get_session(session_id)
    now = time.time()

    new_session = Session(
        id=gen_id("ses_"),
        projectID=parent.projectID,
        directory=parent.directory,
        title=f"{parent.title} (fork)",
        version=parent.version,
        time=SessionTime(created=now, updated=now),
        parentID=session_id,
    )
    sessions[new_session.id] = new_session

    # Copy messages up to the fork point
    messages_to_copy = []
    for msg in session_messages.get(session_id, []):
        messages_to_copy.append(msg)
        if message_id and msg["info"]["id"] == message_id:
            break
    session_messages[new_session.id] = messages_to_copy.copy()

    logger.info("Forked session %s -> %s", session_id, new_session.id)

    await event_bus.publish(
        Event(type="session.created", properties={"info": new_session.model_dump()})
    )
    return new_session


async def revert_session(
    session_id: str,
    message_id: str,
    event_bus: EventBus,
    part_id: str | None = None,
) -> Session:
    """
    Revert session to a specific message, restoring files to that state.

    Args:
        session_id: The session ID
        message_id: The message ID to revert to
        event_bus: EventBus for publishing events
        part_id: Optional part ID

    Returns:
        The updated session

    Raises:
        NotFoundError: If the session is not found
        InvalidOperationError: If restore fails
    """
    session = get_session(session_id)
    history = session_snapshot_history.get(session_id, [])

    # Find the snapshot hash corresponding to the target message
    messages = session_messages.get(session_id, [])
    target_index: int | None = None
    for i, msg in enumerate(messages):
        if msg["info"]["id"] == message_id:
            target_index = i
            break

    target_hash: str | None = None
    if target_index is not None and target_index < len(history):
        target_hash = history[target_index]

    # Restore files if we have a valid snapshot
    if target_hash:
        logger.info("Reverting session %s to snapshot %s", session_id, target_hash[:8])
        try:
            restore_snapshot(session_id, target_hash)
        except Exception as e:
            logger.error("Failed to restore snapshot for session %s: %s", session_id, e)
            raise InvalidOperationError(f"Failed to restore snapshot: {e}")

    session.revert = RevertInfo(
        messageID=message_id,
        partID=part_id,
        snapshot=target_hash,
    )
    session.time.updated = time.time()
    sessions[session_id] = session

    await event_bus.publish(
        Event(type="session.updated", properties={"info": session.model_dump()})
    )
    return session


async def unrevert_session(session_id: str, event_bus: EventBus) -> Session:
    """
    Undo revert on a session.

    Args:
        session_id: The session ID
        event_bus: EventBus for publishing events

    Returns:
        The updated session

    Raises:
        NotFoundError: If the session is not found
    """
    session = get_session(session_id)
    session.revert = None
    session.time.updated = time.time()
    sessions[session_id] = session

    await event_bus.publish(
        Event(type="session.updated", properties={"info": session.model_dump()})
    )
    return session


def update_session_summary(session_id: str, summary: SessionSummary) -> None:
    """
    Update a session's summary (used after message streaming).

    Args:
        session_id: The session ID
        summary: The new summary
    """
    if session_id in sessions:
        sessions[session_id].summary = summary
        sessions[session_id].time.updated = time.time()
