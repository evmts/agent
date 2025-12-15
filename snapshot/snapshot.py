"""
Snapshot system for capturing and restoring file system state.

Uses Git tree objects (not commits) for lightweight state capture.
Inspired by opencode's snapshot implementation.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import TYPE_CHECKING

import git
from git import Repo

if TYPE_CHECKING:
    from git.objects.tree import Tree


class FileDiff:
    """Represents changes to a single file."""

    def __init__(
        self,
        file: str,
        before: str,
        after: str,
        additions: int,
        deletions: int,
    ):
        self.file = file
        self.before = before
        self.after = after
        self.additions = additions
        self.deletions = deletions


class Snapshot:
    """
    Manages file system snapshots using an isolated Git bare repository.

    Uses git tree objects (not commits) for lightweight state capture.
    Storage location: .agent/snapshots/ within the project directory.
    """

    def __init__(self, project_dir: str):
        """
        Initialize snapshot system for a project.

        Args:
            project_dir: The project working directory to track
        """
        self.project_dir = Path(project_dir).resolve()
        self.snapshot_dir = self.project_dir / ".agent" / "snapshots"
        self._repo: Repo | None = None
        self._initialized = False

    def _ensure_init(self) -> None:
        """Ensure the snapshot git repository is initialized."""
        if self._initialized and self._repo is not None:
            return

        # Create snapshot directory
        self.snapshot_dir.mkdir(parents=True, exist_ok=True)

        # Check if already initialized
        if not (self.snapshot_dir / "HEAD").exists():
            # Initialize bare repository
            self._repo = Repo.init(self.snapshot_dir, bare=True)
        else:
            # Open existing repository
            self._repo = Repo(self.snapshot_dir)

        # Set up exclude file to ignore .agent directory
        info_dir = self.snapshot_dir / "info"
        info_dir.mkdir(exist_ok=True)
        exclude_file = info_dir / "exclude"
        exclude_content = "# Exclude snapshot storage from being tracked\n.agent/\n"
        if not exclude_file.exists() or exclude_file.read_text() != exclude_content:
            exclude_file.write_text(exclude_content)

        self._initialized = True

    @property
    def repo(self) -> Repo:
        """Get the GitPython repository instance."""
        self._ensure_init()
        if self._repo is None:
            raise RuntimeError("Repository not initialized")
        return self._repo

    def track(self) -> str:
        """
        Capture current filesystem state as a git tree object.

        Returns:
            str: The tree SHA hash identifying this snapshot (40-char hex string)
        """
        self._ensure_init()
        
        # Create a temporary Git object to use index operations
        # We need to use the command interface for some operations that aren't directly supported in GitPython
        repo = self.repo
        
        # Set environment variables for git operations
        with repo.git.custom_environment(
            GIT_DIR=str(self.snapshot_dir),
            GIT_WORK_TREE=str(self.project_dir)
        ):
            # Stage all files in project directory
            repo.git.add("-A")
            
            # Write tree object (does not create commit)
            tree_sha = repo.git.write_tree()

        return tree_sha

    def patch(self, from_hash: str, to_hash: str | None = None) -> list[str]:
        """
        Get list of changed files between a snapshot and current state (or another snapshot).

        Args:
            from_hash: The source tree SHA
            to_hash: Target tree SHA (None = compare to working tree)

        Returns:
            list[str]: List of changed file paths (relative to project_dir)
        """
        self._ensure_init()
        repo = self.repo

        try:
            with repo.git.custom_environment(
                GIT_DIR=str(self.snapshot_dir),
                GIT_WORK_TREE=str(self.project_dir)
            ):
                if to_hash:
                    diff_output = repo.git.diff("--name-only", from_hash, to_hash)
                else:
                    diff_output = repo.git.diff("--name-only", from_hash)

                return [f for f in diff_output.split("\n") if f]
        except git.exc.GitCommandError:
            return []

    def revert(self, hash: str, files: list[str]) -> None:
        """
        Restore specific files from a snapshot.

        Args:
            hash: Tree SHA to restore from
            files: List of file paths to restore
        """
        if not files:
            return

        self._ensure_init()
        repo = self.repo

        with repo.git.custom_environment(
            GIT_DIR=str(self.snapshot_dir),
            GIT_WORK_TREE=str(self.project_dir)
        ):
            # Read tree into index
            repo.git.read_tree(hash)

            # Checkout specific files from index to working tree
            repo.git.checkout_index("-f", "--", *files)

    def restore(self, hash: str) -> None:
        """
        Full restoration of filesystem to snapshot state.

        Args:
            hash: Tree SHA to restore to
        """
        self._ensure_init()
        repo = self.repo

        with repo.git.custom_environment(
            GIT_DIR=str(self.snapshot_dir),
            GIT_WORK_TREE=str(self.project_dir)
        ):
            # Read tree into index
            repo.git.read_tree(hash)

            # Checkout all files from index to working tree
            repo.git.checkout_index("-a", "-f")

    def diff_full(
        self, from_hash: str, to_hash: str | None = None
    ) -> list[FileDiff]:
        """
        Get detailed diffs including file contents and statistics.

        Args:
            from_hash: Source tree SHA
            to_hash: Target tree SHA (None = working tree)

        Returns:
            list[FileDiff]: Detailed diff information for each changed file
        """
        self._ensure_init()
        repo = self.repo

        # Get changed files with stats
        try:
            with repo.git.custom_environment(
                GIT_DIR=str(self.snapshot_dir),
                GIT_WORK_TREE=str(self.project_dir)
            ):
                if to_hash:
                    numstat = repo.git.diff("--numstat", from_hash, to_hash)
                else:
                    numstat = repo.git.diff("--numstat", from_hash)
        except git.exc.GitCommandError:
            return []

        diffs: list[FileDiff] = []

        for line in numstat.split("\n"):
            if not line:
                continue

            parts = line.split("\t")
            if len(parts) != 3:
                continue

            adds_str, dels_str, filepath = parts

            # Handle binary files (shown as "-")
            adds = 0 if adds_str == "-" else int(adds_str)
            dels = 0 if dels_str == "-" else int(dels_str)

            # Get before content
            try:
                with repo.git.custom_environment(
                    GIT_DIR=str(self.snapshot_dir),
                    GIT_WORK_TREE=str(self.project_dir)
                ):
                    before = repo.git.show(f"{from_hash}:{filepath}")
            except git.exc.GitCommandError:
                before = ""  # File didn't exist

            # Get after content
            if to_hash:
                try:
                    with repo.git.custom_environment(
                        GIT_DIR=str(self.snapshot_dir),
                        GIT_WORK_TREE=str(self.project_dir)
                    ):
                        after = repo.git.show(f"{to_hash}:{filepath}")
                except git.exc.GitCommandError:
                    after = ""  # File was deleted
            else:
                # Read from working tree
                filepath_abs = self.project_dir / filepath
                if filepath_abs.exists():
                    try:
                        after = filepath_abs.read_text()
                    except Exception:
                        after = ""  # Binary or unreadable
                else:
                    after = ""

            diffs.append(
                FileDiff(
                    file=filepath,
                    before=before,
                    after=after,
                    additions=adds,
                    deletions=dels,
                )
            )

        return diffs

    def get_file_at(self, hash: str, filepath: str) -> str:
        """
        Get contents of a specific file at a snapshot.

        Args:
            hash: Tree SHA
            filepath: Relative path to file

        Returns:
            str: File contents

        Raises:
            git.exc.GitCommandError: If file doesn't exist in snapshot
        """
        self._ensure_init()
        repo = self.repo
        
        with repo.git.custom_environment(
            GIT_DIR=str(self.snapshot_dir),
            GIT_WORK_TREE=str(self.project_dir)
        ):
            return repo.git.show(f"{hash}:{filepath}")

    def list_files(self, hash: str) -> list[str]:
        """
        List all files in a snapshot.

        Args:
            hash: Tree SHA

        Returns:
            list[str]: File paths in the snapshot
        """
        self._ensure_init()
        repo = self.repo
        
        with repo.git.custom_environment(
            GIT_DIR=str(self.snapshot_dir),
            GIT_WORK_TREE=str(self.project_dir)
        ):
            output = repo.git.ls_tree("-r", "--name-only", hash)
            return [f for f in output.split("\n") if f]

    def file_exists_at(self, hash: str, filepath: str) -> bool:
        """
        Check if a file exists in a snapshot.

        Args:
            hash: Tree SHA
            filepath: Relative path to file

        Returns:
            bool: True if file exists in snapshot
        """
        self._ensure_init()
        repo = self.repo
        
        try:
            with repo.git.custom_environment(
                GIT_DIR=str(self.snapshot_dir),
                GIT_WORK_TREE=str(self.project_dir)
            ):
                output = repo.git.ls_tree(hash, "--", filepath)
                return bool(output)
        except git.exc.GitCommandError:
            return False
