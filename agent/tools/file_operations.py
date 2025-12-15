"""
File operation tools for reading, writing, and searching files.
"""
import os
import re
from pathlib import Path


def _validate_path(path: str, base_dir: Path | None = None, skip_validation: bool = False) -> Path | None:
    """
    Validate and sanitize a file path to prevent directory traversal attacks.

    Args:
        path: The path to validate
        base_dir: The base directory to restrict access to (defaults to cwd)
        skip_validation: If True, skip path traversal validation (for testing)

    Returns:
        Resolved Path object if valid, None if path traversal detected
    """
    # Allow skipping validation via env var or parameter (for tests)
    if skip_validation or os.environ.get("DISABLE_PATH_VALIDATION") == "1":
        try:
            return Path(path).resolve()
        except (ValueError, RuntimeError):
            return None

    if base_dir is None:
        base_dir = Path.cwd()

    # Resolve both paths to absolute paths
    base_dir = base_dir.resolve()
    try:
        resolved_path = Path(path).resolve()
    except (ValueError, RuntimeError):
        return None

    # Check if the resolved path is within the base directory
    try:
        resolved_path.relative_to(base_dir)
        return resolved_path
    except ValueError:
        # Path is outside the base directory
        return None


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
        file_path = _validate_path(path)
        if file_path is None:
            return f"Error: Access denied - path traversal detected: {path}"

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
        file_path = _validate_path(path)
        if file_path is None:
            return f"Error: Access denied - path traversal detected: {path}"

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
        base_path = _validate_path(path)
        if base_path is None:
            return f"Error: Access denied - path traversal detected: {path}"

        if not base_path.exists():
            return f"Error: Directory not found: {path}"
        if not base_path.is_dir():
            return f"Error: Not a directory: {path}"

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
        dir_path = _validate_path(path)
        if dir_path is None:
            return f"Error: Access denied - path traversal detected: {path}"

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


async def grep_files(
    pattern: str,
    path: str = ".",
    file_pattern: str | None = None,
    ignore_case: bool = False,
    context_lines: int = 0,
    max_results: int = 50,
    include_line_numbers: bool = True,
) -> str:
    """
    Search file contents using regex pattern.

    Args:
        pattern: Regex pattern to search for in file contents
        path: Base directory to search from
        file_pattern: Optional glob pattern for filtering files (e.g., "*.py")
        ignore_case: If True, perform case-insensitive search
        context_lines: Number of lines to show before and after each match
        max_results: Maximum number of matches to return
        include_line_numbers: Whether to include line numbers in output

    Returns:
        Formatted search results similar to ripgrep output
    """
    try:
        base_path = _validate_path(path)
        if base_path is None:
            return f"Error: Access denied - path traversal detected: {path}"

        if not base_path.exists():
            return f"Error: Directory not found: {path}"

        # Compile regex pattern
        regex_flags = re.IGNORECASE if ignore_case else 0
        try:
            regex = re.compile(pattern, regex_flags)
        except re.error as e:
            return f"Error: Invalid regex pattern: {e}"

        # Determine which files to search
        if base_path.is_file():
            files_to_search = [base_path]
        else:
            # Use glob pattern if provided, otherwise search all files
            glob_pattern = file_pattern if file_pattern else "**/*"
            files_to_search = [f for f in base_path.glob(glob_pattern) if f.is_file()]

        results = []
        match_count = 0
        file_count = 0

        for file_path in files_to_search:
            if match_count >= max_results:
                break

            # Skip binary files
            try:
                content = file_path.read_text(errors="strict")
            except (UnicodeDecodeError, PermissionError):
                # Skip binary files or files we can't read
                continue
            except Exception:
                continue

            lines = content.split("\n")
            matches_in_file = []
            matched_lines = set()

            # Find all matches in this file
            for line_num, line in enumerate(lines, start=1):
                if regex.search(line):
                    matched_lines.add(line_num)
                    match_count += 1

            if matched_lines:
                file_count += 1
                # Display relative path
                try:
                    display_path = file_path.relative_to(Path.cwd())
                except ValueError:
                    display_path = file_path

                matches_in_file.append(f"\n{display_path}")

                # Sort matched lines and add context
                sorted_matches = sorted(matched_lines)
                i = 0
                while i < len(sorted_matches):
                    current_line = sorted_matches[i]

                    # Determine context range
                    start = max(1, current_line - context_lines)
                    end = min(len(lines), current_line + context_lines)

                    # Expand range if adjacent matches overlap
                    while i + 1 < len(sorted_matches) and sorted_matches[i + 1] <= end + 1:
                        i += 1
                        end = min(len(lines), sorted_matches[i] + context_lines)

                    # Output the range
                    for ln in range(start, end + 1):
                        line_content = lines[ln - 1]
                        is_match = ln in matched_lines

                        if include_line_numbers:
                            if is_match:
                                matches_in_file.append(f"{ln}:{line_content}")
                            else:
                                matches_in_file.append(f"{ln}-{line_content}")
                        else:
                            prefix = ":" if is_match else "-"
                            matches_in_file.append(f"{prefix}{line_content}")

                    # Add separator if there are more matches
                    if i + 1 < len(sorted_matches):
                        matches_in_file.append("--")

                    i += 1

                results.append("\n".join(matches_in_file))

            if match_count >= max_results:
                break

        if not results:
            return f"No matches found for pattern: {pattern}"

        summary = f"Found {match_count} matches in {file_count} files"
        if match_count >= max_results:
            summary += f" (limited to {max_results} results)"

        return summary + "\n" + "\n".join(results)

    except Exception as e:
        return f"Error searching files: {str(e)}"
