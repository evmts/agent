"""Markdown file loading utilities for system prompt customization.

Provides functionality to search for and load CLAUDE.md or Agents.md files
starting from a working directory and traversing up to the filesystem root.
"""

from functools import lru_cache
from pathlib import Path

# Constants - file names to search for (in priority order)
CLAUDE_MD_FILENAME = "CLAUDE.md"
AGENTS_MD_FILENAME = "Agents.md"

# Cache size for loaded markdown content
MARKDOWN_CACHE_SIZE = 32


def find_markdown_file(starting_dir: Path) -> Path | None:
    """
    Search for CLAUDE.md or Agents.md starting from the given directory
    and traversing up to the filesystem root.

    CLAUDE.md takes priority over Agents.md if both exist in the same directory.

    Args:
        starting_dir: Directory to start searching from

    Returns:
        Path to the found file, or None if neither file exists
    """
    current = starting_dir.resolve()

    while True:
        # Check for CLAUDE.md first (higher priority)
        claude_path = current / CLAUDE_MD_FILENAME
        if claude_path.is_file():
            return claude_path

        # Check for Agents.md second
        agents_path = current / AGENTS_MD_FILENAME
        if agents_path.is_file():
            return agents_path

        # Move to parent directory
        parent = current.parent
        if parent == current:
            # Reached filesystem root
            break
        current = parent

    return None


def load_markdown_file(path: Path) -> str:
    """
    Load content from a markdown file.

    Args:
        path: Path to the markdown file

    Returns:
        File content as string, or empty string on error
    """
    try:
        return path.read_text(encoding="utf-8")
    except OSError as e:
        print(f"Warning: Failed to load markdown file from {path}: {e}")
        return ""


@lru_cache(maxsize=MARKDOWN_CACHE_SIZE)
def load_system_prompt_markdown(working_dir: str) -> str:
    """
    Load CLAUDE.md or Agents.md content for system prompt prepending.

    Searches starting from working_dir up to filesystem root.
    CLAUDE.md takes priority over Agents.md.

    Results are cached per working directory.

    Args:
        working_dir: Working directory to start search from

    Returns:
        Markdown content as string, or empty string if no file found
    """
    starting_path = Path(working_dir)

    if not starting_path.is_dir():
        print(f"Warning: Working directory does not exist: {working_dir}")
        return ""

    found_path = find_markdown_file(starting_path)

    if found_path is None:
        return ""

    print(f"Loading system prompt from: {found_path}")
    return load_markdown_file(found_path)
