"""
File operation tools for reading, writing, and searching files.
"""
import re
from pathlib import Path


async def read_file(path: str, encoding: str = "utf-8") -> str:
    """
    Read contents of a file.

    Args:
        path: Absolute or relative path to file
        encoding: File encoding (default utf-8)

    Returns:
        File contents with line numbers or error message
    """
    try:
        file_path = Path(path).resolve()
        if not file_path.exists():
            return f"Error: File not found: {path}"
        if not file_path.is_file():
            return f"Error: Not a file: {path}"

        content = file_path.read_text(encoding=encoding)

        # Add line numbers for better reference
        lines = content.split("\n")
        numbered = [f"{i + 1:4d} | {line}" for i, line in enumerate(lines)]
        return "\n".join(numbered)

    except Exception as e:
        return f"Error reading file: {str(e)}"


async def write_file(path: str, content: str, encoding: str = "utf-8") -> str:
    """
    Write content to a file.

    Args:
        path: Absolute or relative path to file
        content: Content to write
        encoding: File encoding (default utf-8)

    Returns:
        Success message or error
    """
    try:
        file_path = Path(path).resolve()

        # Create parent directories if needed
        file_path.parent.mkdir(parents=True, exist_ok=True)

        file_path.write_text(content, encoding=encoding)
        return f"Successfully wrote {len(content)} characters to {path}"

    except Exception as e:
        return f"Error writing file: {str(e)}"


async def search_files(
    pattern: str,
    path: str = ".",
    content_pattern: str | None = None,
    max_results: int = 50,
) -> str:
    """
    Search for files by name pattern and optionally content.

    Args:
        pattern: Glob pattern for filenames (e.g., "**/*.py")
        path: Base directory to search from
        content_pattern: Optional regex to search file contents
        max_results: Maximum number of results to return

    Returns:
        List of matching files
    """
    try:
        base_path = Path(path).resolve()
        matches = []

        for file_path in base_path.glob(pattern):
            if not file_path.is_file():
                continue

            if content_pattern:
                try:
                    content = file_path.read_text(errors="ignore")
                    if not re.search(content_pattern, content):
                        continue
                except Exception:
                    continue

            matches.append(str(file_path.relative_to(base_path)))

            if len(matches) >= max_results:
                break

        if not matches:
            return "No files found matching the pattern"

        return f"Found {len(matches)} files:\n" + "\n".join(matches)

    except Exception as e:
        return f"Error searching files: {str(e)}"


async def list_directory(path: str = ".", include_hidden: bool = False) -> str:
    """
    List contents of a directory.

    Args:
        path: Directory path to list
        include_hidden: Whether to include hidden files (starting with .)

    Returns:
        Directory listing with file types and sizes
    """
    try:
        dir_path = Path(path).resolve()
        if not dir_path.exists():
            return f"Error: Directory not found: {path}"
        if not dir_path.is_dir():
            return f"Error: Not a directory: {path}"

        entries = []
        for item in sorted(dir_path.iterdir()):
            if not include_hidden and item.name.startswith("."):
                continue

            if item.is_dir():
                entries.append(f"[DIR]  {item.name}/")
            else:
                size = item.stat().st_size
                size_str = _format_size(size)
                entries.append(f"[FILE] {item.name} ({size_str})")

        if not entries:
            return "Directory is empty"

        return f"Contents of {path}:\n" + "\n".join(entries)

    except Exception as e:
        return f"Error listing directory: {str(e)}"


def _format_size(size: int) -> str:
    """Format file size in human-readable form."""
    for unit in ["B", "KB", "MB", "GB"]:
        if size < 1024:
            return f"{size:.1f}{unit}"
        size /= 1024
    return f"{size:.1f}TB"
