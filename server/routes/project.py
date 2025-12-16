"""
Project information endpoint.
"""

import hashlib
import os
import subprocess

from fastapi import APIRouter, Query
from pydantic import BaseModel


# =============================================================================
# Constants
# =============================================================================

GIT_COMMAND_TIMEOUT_SECONDS = 5
PROJECT_ID_HASH_LENGTH = 16


# =============================================================================
# Models
# =============================================================================

class Project(BaseModel):
    """Project information response."""

    id: str
    worktree: str
    name: str


# =============================================================================
# Router
# =============================================================================

router = APIRouter()


@router.get("/project/current")
async def get_current_project(directory: str = Query(...)) -> Project:
    """
    Get current project information.

    Args:
        directory: The directory to get project information for

    Returns:
        Project information including ID, worktree path, and name
    """
    # Try to get git root, fallback to the provided directory
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=GIT_COMMAND_TIMEOUT_SECONDS,
        )
        worktree = result.stdout.strip() if result.returncode == 0 else directory
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        worktree = directory

    # Normalize to absolute path
    worktree = os.path.abspath(worktree)

    # Generate unique ID from worktree path
    project_id = hashlib.sha256(worktree.encode()).hexdigest()[:PROJECT_ID_HASH_LENGTH]

    # Extract project name from path
    name = os.path.basename(worktree)

    return Project(id=project_id, worktree=worktree, name=name)
