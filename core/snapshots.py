"""
Snapshot operations for file state tracking.

Provides functions for tracking file changes using git-based snapshots.
"""

import logging
import subprocess
from datetime import datetime
from typing import Optional

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
        logger.debug("Snapshot initialized for session %s: %s", session_id, initial_hash[:8])
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
        commit_hash = snapshot.track()
        logger.debug("Snapshot tracked for session %s: %s", session_id, commit_hash[:8])
        return commit_hash
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

    logger.info("Restoring snapshot %s for session %s", target_hash[:8], session_id)
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


class GhostCommitManager:
    """Manages ghost commits for fine-grained undo points during agent sessions."""

    def __init__(self, working_dir: str, session_id: str):
        """
        Initialize ghost commit manager.

        Args:
            working_dir: The working directory for git operations
            session_id: The session ID for tracking
        """
        self.working_dir = working_dir
        self.session_id = session_id
        self.commit_refs: list[str] = []

    def create_ghost_commit(self, turn_number: int, summary: str = "") -> Optional[str]:
        """
        Create a ghost commit for the current turn.

        Args:
            turn_number: The turn number for the commit message
            summary: Optional summary for the commit message

        Returns:
            The commit hash, or None if no changes or error
        """
        try:
            # Check for changes
            status = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=self.working_dir,
                capture_output=True,
                text=True,
                timeout=10,
            )

            if not status.stdout.strip():
                logger.debug("No changes to commit for turn %d", turn_number)
                return None  # No changes to commit

            # Stage all changes (including untracked)
            subprocess.run(
                ["git", "add", "-A"],
                cwd=self.working_dir,
                check=True,
                timeout=10,
            )

            # Create commit message
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            if summary:
                message = f"[agent] Turn {turn_number}: {summary}"
            else:
                message = f"[agent] Turn {turn_number} ({timestamp})"

            # Create commit
            result = subprocess.run(
                ["git", "commit", "-m", message, "--no-verify"],
                cwd=self.working_dir,
                capture_output=True,
                text=True,
                timeout=10,
            )

            if result.returncode != 0:
                logger.warning("Ghost commit failed: %s", result.stderr)
                return None

            # Get commit hash
            hash_result = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=self.working_dir,
                capture_output=True,
                text=True,
                timeout=5,
            )

            commit_hash = hash_result.stdout.strip()
            self.commit_refs.append(commit_hash)
            logger.info("Created ghost commit for turn %d: %s", turn_number, commit_hash[:8])

            return commit_hash

        except subprocess.CalledProcessError as e:
            logger.warning("Ghost commit error for turn %d: %s", turn_number, e)
            return None
        except subprocess.TimeoutExpired:
            logger.warning("Ghost commit timeout for turn %d", turn_number)
            return None
        except Exception as e:
            logger.warning("Unexpected error creating ghost commit for turn %d: %s", turn_number, e)
            return None

    def revert_to_turn(self, turn_number: int) -> bool:
        """
        Revert to the state after a specific turn.

        Args:
            turn_number: The turn number to revert to (0-indexed)

        Returns:
            True if successful, False otherwise
        """
        if turn_number < 0 or turn_number >= len(self.commit_refs):
            logger.warning("Invalid turn number %d (have %d commits)", turn_number, len(self.commit_refs))
            return False

        commit_ref = self.commit_refs[turn_number]

        try:
            subprocess.run(
                ["git", "reset", "--hard", commit_ref],
                cwd=self.working_dir,
                check=True,
                timeout=10,
            )
            # Trim commit_refs to this point
            self.commit_refs = self.commit_refs[:turn_number + 1]
            logger.info("Reverted to turn %d: %s", turn_number, commit_ref[:8])
            return True
        except subprocess.CalledProcessError as e:
            logger.error("Failed to revert to turn %d: %s", turn_number, e)
            return False
        except subprocess.TimeoutExpired:
            logger.error("Timeout reverting to turn %d", turn_number)
            return False

    def cleanup_ghost_commits(self, squash: bool = False) -> None:
        """
        Clean up ghost commits at session end.

        Args:
            squash: If True, squash all commits into one; if False, soft reset
        """
        if not self.commit_refs:
            logger.debug("No ghost commits to clean up for session %s", self.session_id)
            return

        try:
            if squash and len(self.commit_refs) > 1:
                # Squash all ghost commits into one
                first_parent = subprocess.run(
                    ["git", "rev-parse", f"{self.commit_refs[0]}^"],
                    cwd=self.working_dir,
                    capture_output=True,
                    text=True,
                    timeout=5,
                ).stdout.strip()

                subprocess.run(
                    ["git", "reset", "--soft", first_parent],
                    cwd=self.working_dir,
                    check=True,
                    timeout=10,
                )
                subprocess.run(
                    ["git", "commit", "-m", f"[agent] Session {self.session_id}", "--no-verify"],
                    cwd=self.working_dir,
                    check=True,
                    timeout=10,
                )
                logger.info("Squashed %d ghost commits for session %s", len(self.commit_refs), self.session_id)
            else:
                # Just soft reset to before first ghost commit
                first_parent = subprocess.run(
                    ["git", "rev-parse", f"{self.commit_refs[0]}^"],
                    cwd=self.working_dir,
                    capture_output=True,
                    text=True,
                    timeout=5,
                ).stdout.strip()

                subprocess.run(
                    ["git", "reset", "--soft", first_parent],
                    cwd=self.working_dir,
                    check=True,
                    timeout=10,
                )
                logger.info("Soft reset %d ghost commits for session %s", len(self.commit_refs), self.session_id)
        except subprocess.CalledProcessError as e:
            logger.warning("Ghost commit cleanup failed for session %s: %s", self.session_id, e)
        except subprocess.TimeoutExpired:
            logger.warning("Ghost commit cleanup timeout for session %s", self.session_id)
        except Exception as e:
            logger.warning("Unexpected error during ghost commit cleanup: %s", e)

    def get_turn_diff(self, turn_number: int) -> Optional[str]:
        """
        Get diff for a specific turn.

        Args:
            turn_number: The turn number to get diff for (0-indexed)

        Returns:
            The diff output, or None if error
        """
        if turn_number < 0 or turn_number >= len(self.commit_refs):
            logger.warning("Invalid turn number %d for diff", turn_number)
            return None

        try:
            if turn_number == 0:
                parent = f"{self.commit_refs[0]}^"
            else:
                parent = self.commit_refs[turn_number - 1]

            result = subprocess.run(
                ["git", "diff", parent, self.commit_refs[turn_number]],
                cwd=self.working_dir,
                capture_output=True,
                text=True,
                timeout=10,
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            logger.error("Failed to get diff for turn %d: %s", turn_number, e)
            return None
        except subprocess.TimeoutExpired:
            logger.error("Timeout getting diff for turn %d", turn_number)
            return None
