"""
Snapshot operations for file state tracking.

Provides functions for tracking file changes using git-based snapshots.
"""

import logging

from snapshot import Snapshot

logger = logging.getLogger(__name__)

from .exceptions import NotFoundError
from .models import FileDiff
from .state import session_snapshot_history, session_snapshots, sessions


def init_snapshot(session_id: str, directory: str) -> str | None:
    """
    Initialize snapshot tracking for a session.

    Args:
        session_id: The session to initialize snapshots for
        directory: The directory to track

    Returns:
        The initial snapshot hash, or None if initialization failed
    """
    snapshot = Snapshot(directory)
    session_snapshots[session_id] = snapshot
    try:
        initial_hash = snapshot.track()
        session_snapshot_history[session_id] = [initial_hash]
        return initial_hash
    except Exception as e:
        logger.debug("Failed to initialize snapshot for session %s: %s", session_id, e)
        session_snapshot_history[session_id] = []
        return None


def track_snapshot(session_id: str) -> str | None:
    """
    Capture the current file state for a session.

    Args:
        session_id: The session to track

    Returns:
        The snapshot hash, or None if tracking failed
    """
    snapshot = session_snapshots.get(session_id)
    if not snapshot:
        return None
    try:
        return snapshot.track()
    except Exception as e:
        logger.debug("Failed to track snapshot for session %s: %s", session_id, e)
        return None


def compute_diff(
    session_id: str, start_hash: str, end_hash: str
) -> list[FileDiff]:
    """
    Compute file diffs between two snapshots.

    Args:
        session_id: The session to compute diffs for
        start_hash: The starting snapshot hash
        end_hash: The ending snapshot hash

    Returns:
        List of file diffs
    """
    snapshot = session_snapshots.get(session_id)
    if not snapshot:
        return []

    try:
        diffs = snapshot.diff_full(start_hash, end_hash)
        return [
            FileDiff(
                file=d.file,
                before=d.before,
                after=d.after,
                additions=d.additions,
                deletions=d.deletions,
            )
            for d in diffs
        ]
    except Exception as e:
        logger.warning(
            "Failed to compute diff for session %s (start: %s, end: %s): %s",
            session_id,
            start_hash,
            end_hash,
            e,
        )
        return []


def get_changed_files(session_id: str, start_hash: str, end_hash: str) -> list[str]:
    """
    Get list of files changed between two snapshots.

    Args:
        session_id: The session to check
        start_hash: The starting snapshot hash
        end_hash: The ending snapshot hash

    Returns:
        List of changed file paths
    """
    snapshot = session_snapshots.get(session_id)
    if not snapshot:
        return []

    try:
        return snapshot.patch(start_hash, end_hash)
    except Exception as e:
        logger.warning(
            "Failed to get changed files for session %s (start: %s, end: %s): %s",
            session_id,
            start_hash,
            end_hash,
            e,
        )
        return []


def restore_snapshot(session_id: str, target_hash: str) -> None:
    """
    Restore files to a previous snapshot state.

    Args:
        session_id: The session to restore
        target_hash: The snapshot hash to restore to

    Raises:
        NotFoundError: If the session or snapshot is not found
        InvalidOperationError: If restore fails
    """
    snapshot = session_snapshots.get(session_id)
    if not snapshot:
        raise NotFoundError("session snapshot", session_id)

    snapshot.restore(target_hash)


def append_snapshot_history(session_id: str, snapshot_hash: str) -> None:
    """
    Append a snapshot hash to the session's history.

    Args:
        session_id: The session to update
        snapshot_hash: The hash to append
    """
    if session_id in session_snapshot_history:
        session_snapshot_history[session_id].append(snapshot_hash)


def cleanup_snapshots(session_id: str) -> None:
    """
    Clean up snapshot resources for a session.

    Args:
        session_id: The session to clean up
    """
    session_snapshots.pop(session_id, None)
    session_snapshot_history.pop(session_id, None)
