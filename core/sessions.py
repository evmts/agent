"""
Session operations.

Provides functions for managing sessions including CRUD operations,
forking, reverting, and diff computation.
"""

import logging
import time

from config.defaults import DEFAULT_MODEL, DEFAULT_REASONING_EFFORT, GHOST_COMMIT_CONFIG
from config.features import feature_manager

from .events import Event, EventBus
from .exceptions import InvalidOperationError, NotFoundError
from .models import (
    FileDiff,
    GhostCommitInfo,
    RevertInfo,
    Session,
    SessionSummary,
    SessionTime,
    gen_id,
)
from .snapshots import (
    cleanup_snapshots,
    compute_diff,
    get_changed_files,
    init_snapshot,
    restore_snapshot,
    GhostCommitManager,
)
from .state import (
    active_tasks,
    session_messages,
    session_snapshot_history,
    sessions,
    session_ghost_commits,
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
    bypass_mode: bool = False,
) -> Session:
    """
    Create a new session.

    Args:
        directory: Working directory for the session
        event_bus: EventBus for publishing events
        title: Optional session title
        parent_id: Optional parent session ID
        bypass_mode: If True, skip all permission checks (DANGEROUS)

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
        bypass_mode=bypass_mode,
        model=DEFAULT_MODEL,
        reasoning_effort=DEFAULT_REASONING_EFFORT,
    )
    sessions[session.id] = session
    session_messages[session.id] = []

    # Initialize snapshot tracking
    init_snapshot(session.id, directory)

    # Initialize ghost commit manager if enabled
    if feature_manager.is_enabled("ghost_commit"):
        ghost_manager = GhostCommitManager(directory, session.id)
        session_ghost_commits[session.id] = ghost_manager
        session.ghost_commit = GhostCommitInfo(enabled=True, turn_number=0, commit_refs=[])
        logger.info("Ghost commits enabled for session %s", session.id)

    if bypass_mode:
        logger.warning("⚠️  Session created in BYPASS MODE: %s - All permission checks disabled", session.id)
    else:
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
    model: str | None = None,
    reasoning_effort: str | None = None,
    plugins: list[str] | None = None,
) -> Session:
    """
    Update a session's title, archived status, model, reasoning effort, or plugins.

    Args:
        session_id: The session ID
        event_bus: EventBus for publishing events
        title: New title (optional)
        archived: Archived timestamp (optional)
        model: Model ID to use (optional)
        reasoning_effort: Reasoning effort level (optional)
        plugins: List of plugin names to activate (optional)

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
    if model is not None:
        session.model = model
    if reasoning_effort is not None:
        session.reasoning_effort = reasoning_effort
    if plugins is not None:
        session.plugins = plugins
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

    # Cleanup ghost commits if enabled
    ghost_manager = session_ghost_commits.pop(session_id, None)
    if ghost_manager:
        squash = GHOST_COMMIT_CONFIG.get("squash_on_close", False)
        ghost_manager.cleanup_ghost_commits(squash=squash)
        logger.info("Ghost commits cleaned up for session %s (squash=%s)", session_id, squash)

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
    title: str | None = None,
) -> Session:
    """
    Fork a session at a specific message.

    Args:
        session_id: The session ID to fork
        event_bus: EventBus for publishing events
        message_id: Optional message ID to fork at
        title: Optional title for the new session

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
        title=title or f"{parent.title} (fork)",
        version=parent.version,
        time=SessionTime(created=now, updated=now),
        parentID=session_id,
        fork_point=message_id,
    )
    sessions[new_session.id] = new_session

    # Copy messages up to the fork point
    messages_to_copy = []
    for msg in session_messages.get(session_id, []):
        messages_to_copy.append(msg)
        if message_id and msg["info"]["id"] == message_id:
            break
    session_messages[new_session.id] = messages_to_copy.copy()

    # Initialize snapshot at fork point
    init_snapshot(new_session.id, parent.directory)

    logger.info("Forked session %s -> %s at message %s", session_id, new_session.id, message_id or "latest")

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


async def undo_turns(
    session_id: str,
    event_bus: EventBus,
    count: int = 1,
) -> tuple[int, int, list[str], str | None]:
    """
    Undo the last N turns in a session, reverting both messages and files.

    A turn consists of a user message followed by all assistant messages until
    the next user message.

    Args:
        session_id: The session ID
        event_bus: EventBus for publishing events
        count: Number of turns to undo (must be >= 1)

    Returns:
        Tuple of (turns_undone, messages_removed, files_reverted, snapshot_restored)

    Raises:
        NotFoundError: If the session is not found
        InvalidOperationError: If restore fails
    """
    session = get_session(session_id)
    messages = session_messages.get(session_id, [])
    history = session_snapshot_history.get(session_id, [])

    if not messages:
        return (0, 0, [], None)

    # Find turn boundaries (user messages are turn starts)
    turn_starts = [i for i, m in enumerate(messages) if m["info"]["role"] == "user"]

    # Can't undo if we only have one turn or less
    if len(turn_starts) < 2:
        return (0, 0, [], None)

    # Calculate actual number of turns we can undo
    undo_count = min(count, len(turn_starts) - 1)

    # Find the message index to revert to (start of the turn to remove)
    # If we have turns at indices [0, 5, 10] and we undo 1 turn, we remove turn starting at index 10
    # undo_point is the index of the first message to remove
    undo_point = turn_starts[-undo_count]

    # Get snapshot to restore (the one BEFORE this turn started)
    # The snapshot history is: [initial, after_turn1, after_turn2, ...]
    # turn_starts[i] corresponds to history[i] (snapshot before turn i) or history[i+1] (after turn i)
    # We want the snapshot from BEFORE the turn at undo_point started
    # That's the snapshot after the previous turn, which is at history index matching the turn index
    snapshot_hash: str | None = None
    files_reverted: list[str] = []

    # Find which turn number we're undoing to
    turn_index = len(turn_starts) - undo_count - 1
    # We want the snapshot after that turn (history[turn_index + 1])
    # But history[0] is initial, so history[i+1] is after turn i
    snapshot_index = turn_index + 1

    if snapshot_index < len(history):
        snapshot_hash = history[snapshot_index]

        # Revert files to that snapshot
        if snapshot_hash:
            logger.info(
                "Undoing %d turn(s) for session %s, reverting to snapshot %s",
                undo_count,
                session_id,
                snapshot_hash[:8],
            )
            try:
                restore_snapshot(session_id, snapshot_hash)

                # Get list of files that were changed
                if undo_point < len(history) - 1:
                    files_reverted = get_changed_files(
                        session_id, snapshot_hash, history[-1]
                    )
            except Exception as e:
                logger.error("Failed to restore snapshot for session %s: %s", session_id, e)
                raise InvalidOperationError(f"Failed to restore snapshot: {e}")

    # Calculate how many messages we're removing
    messages_removed = len(messages) - undo_point

    # Truncate messages at undo point
    session_messages[session_id] = messages[:undo_point]

    # Truncate snapshot history to match
    if session_id in session_snapshot_history:
        session_snapshot_history[session_id] = history[: snapshot_index + 1]

    # Update session timestamp
    session.time.updated = time.time()
    sessions[session_id] = session

    logger.info(
        "Undo complete for session %s: %d turn(s), %d message(s) removed, %d file(s) reverted",
        session_id,
        undo_count,
        messages_removed,
        len(files_reverted),
    )

    await event_bus.publish(
        Event(type="session.updated", properties={"info": session.model_dump()})
    )

    return (undo_count, messages_removed, files_reverted, snapshot_hash)
