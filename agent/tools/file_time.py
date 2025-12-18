"""
File time tracking for read-before-write enforcement.

This module provides session-scoped tracking of file read operations and
enforces that files must be read before they can be modified.
"""

import os
from datetime import datetime
from pathlib import Path
from typing import Dict


class FileTimeTracker:
    """
    Tracks file read timestamps and enforces read-before-write safety.

    For each file path, stores the modification time when it was last read.
    This allows detection of external modifications and enforcement of
    read-before-write requirements.
    """

    def __init__(self):
        """Initialize an empty file time tracker."""
        # Maps normalized file path -> modification time at last read
        self._last_read: Dict[str, datetime] = {}

    def _normalize_path(self, file_path: str) -> str:
        """
        Normalize a file path to its canonical absolute form.

        Resolves symlinks and converts to absolute path for consistent tracking.

        Args:
            file_path: Path to normalize (relative or absolute)

        Returns:
            Canonical absolute path
        """
        # Convert to absolute path
        abs_path = os.path.abspath(file_path)

        # Resolve symlinks to get canonical path
        try:
            real_path = os.path.realpath(abs_path)
            return real_path
        except (OSError, RuntimeError):
            # If symlink resolution fails, use absolute path
            return abs_path

    def mark_read(self, file_path: str) -> None:
        """
        Mark a file as read at the current time.

        Records the file's current modification time for later comparison.
        Should be called after successful file reads.

        Args:
            file_path: Path to the file that was read
        """
        normalized = self._normalize_path(file_path)

        # Get current modification time
        try:
            stat_info = os.stat(normalized)
            mtime = datetime.fromtimestamp(stat_info.st_mtime)
            self._last_read[normalized] = mtime
        except (OSError, FileNotFoundError):
            # If file doesn't exist or can't be stat'd, we still track the read attempt
            # This allows the file to be created afterward
            self._last_read[normalized] = datetime.now()

    def assert_not_modified(self, file_path: str) -> None:
        """
        Assert that a file has been read and not modified since.

        Enforces read-before-write safety by checking:
        1. File has been read in this session
        2. File hasn't been modified since it was read

        Args:
            file_path: Path to the file to check

        Raises:
            ValueError: If file hasn't been read or has been modified
        """
        normalized = self._normalize_path(file_path)

        # Check if file has been read
        if normalized not in self._last_read:
            raise ValueError(
                f"File {file_path} has not been read in this session. "
                "You MUST use the Read tool first before writing to existing files"
            )

        # Check if file exists
        if not os.path.exists(normalized):
            # File was deleted after being read - this is okay
            # Write will create a new file
            return

        # Get current modification time
        try:
            stat_info = os.stat(normalized)
            current_mtime = datetime.fromtimestamp(stat_info.st_mtime)
        except (OSError, FileNotFoundError):
            # File became inaccessible - allow the write to proceed
            # The write operation itself will fail if there's a real problem
            return

        # Compare modification times
        last_read_time = self._last_read[normalized]
        if current_mtime > last_read_time:
            # Format timestamps for clear error message
            last_mod_str = current_mtime.isoformat(timespec='milliseconds')
            last_read_str = last_read_time.isoformat(timespec='milliseconds')
            raise ValueError(
                f"File {file_path} has been modified since it was last read.\n"
                f"Last modification: {last_mod_str}\n"
                f"Last read: {last_read_str}\n\n"
                f"Please use the Read tool again to get the latest contents before modifying it."
            )

    def is_read(self, file_path: str) -> bool:
        """
        Check if a file has been read in this session.

        Args:
            file_path: Path to check

        Returns:
            True if file has been read, False otherwise
        """
        normalized = self._normalize_path(file_path)
        return normalized in self._last_read

    def mark_written(self, file_path: str) -> None:
        """
        Update tracking after successful write.

        Records the file's new modification time after a write operation.
        This prevents false positives when checking if the agent's own
        writes triggered external modification warnings.

        Args:
            file_path: Path to the file that was written
        """
        normalized = self._normalize_path(file_path)

        try:
            stat_info = os.stat(normalized)
            mtime = datetime.fromtimestamp(stat_info.st_mtime)
            self._last_read[normalized] = mtime
        except (OSError, FileNotFoundError):
            # File doesn't exist after write (unlikely) - clear tracking
            self.clear_file(file_path)

    def clear_file(self, file_path: str) -> None:
        """
        Remove tracking for a specific file.

        Use this when a file is deleted or when you want to reset
        tracking for a specific file without clearing all tracking data.

        Args:
            file_path: Path to the file to stop tracking
        """
        normalized = self._normalize_path(file_path)
        self._last_read.pop(normalized, None)

    def clear(self) -> None:
        """Clear all tracked file read times."""
        self._last_read.clear()

    def get_read_time(self, file_path: str) -> datetime | None:
        """
        Get the time when a file was last read.

        Args:
            file_path: Path to check

        Returns:
            Datetime when file was last read, or None if not read
        """
        normalized = self._normalize_path(file_path)
        return self._last_read.get(normalized)
