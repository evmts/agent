"""
Safe file operation tools with read-before-write enforcement.

These tools provide file operations with built-in safety checks,
replacing the MCP filesystem tools with safer alternatives.
"""

import os
from pathlib import Path
from typing import Any

from pydantic_ai import RunContext

from .filesystem import (
    get_current_session_id,
    mark_file_read,
    check_file_writable,
)


class SessionDeps:
    """Dependencies passed to agent tools containing session context."""

    def __init__(self, session_id: str):
        self.session_id = session_id


async def read_file_tool(ctx: RunContext[SessionDeps], path: str) -> str:
    """
    Read file contents with safety tracking.

    Reads a file and marks it as read for read-before-write enforcement.
    This replaces the MCP filesystem server's read_file tool.

    Args:
        ctx: Run context with session dependencies
        path: Absolute path to the file to read

    Returns:
        File contents as string

    Raises:
        FileNotFoundError: If file doesn't exist
        PermissionError: If file can't be read
    """
    # Resolve to absolute path
    file_path = os.path.abspath(path)

    # Read file
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        # Try binary mode if UTF-8 fails
        with open(file_path, 'rb') as f:
            content = f.read().decode('utf-8', errors='replace')

    # Mark as read for safety tracking
    from .filesystem import set_current_session_id
    set_current_session_id(ctx.deps.session_id)
    mark_file_read(file_path)

    return content


async def write_file_tool(
    ctx: RunContext[SessionDeps],
    path: str,
    content: str,
) -> str:
    """
    Write content to a file with read-before-write safety.

    For existing files, enforces that the file must have been read first
    and hasn't been modified since. New files can be created freely.

    This replaces the MCP filesystem server's write_file tool.

    Args:
        ctx: Run context with session dependencies
        path: Absolute path to the file to write
        content: Content to write to the file

    Returns:
        Success message

    Raises:
        ValueError: If read-before-write safety check fails
        PermissionError: If file can't be written
    """
    # Resolve to absolute path
    file_path = os.path.abspath(path)

    # Set session context for safety checks
    from .filesystem import set_current_session_id
    set_current_session_id(ctx.deps.session_id)

    # Enforce read-before-write for existing files
    check_file_writable(file_path)

    # Create parent directories if needed
    os.makedirs(os.path.dirname(file_path), exist_ok=True)

    # Write file
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

    # Mark as read after successful write (update tracking)
    mark_file_read(file_path)

    return f"Successfully wrote {len(content)} bytes to {path}"


async def list_directory_tool(ctx: RunContext[SessionDeps], path: str) -> str:
    """
    List directory contents.

    Args:
        ctx: Run context with session dependencies
        path: Path to directory

    Returns:
        Formatted listing of directory contents
    """
    dir_path = os.path.abspath(path)

    if not os.path.exists(dir_path):
        raise FileNotFoundError(f"Directory not found: {path}")

    if not os.path.isdir(dir_path):
        raise NotADirectoryError(f"Not a directory: {path}")

    entries = []
    for entry in sorted(os.listdir(dir_path)):
        entry_path = os.path.join(dir_path, entry)
        if os.path.isdir(entry_path):
            entries.append(f"{entry}/")
        else:
            size = os.path.getsize(entry_path)
            entries.append(f"{entry} ({size} bytes)")

    return "\n".join(entries) if entries else "(empty directory)"


async def create_directory_tool(ctx: RunContext[SessionDeps], path: str) -> str:
    """
    Create a directory (and parent directories if needed).

    Args:
        ctx: Run context with session dependencies
        path: Path to directory to create

    Returns:
        Success message
    """
    dir_path = os.path.abspath(path)
    os.makedirs(dir_path, exist_ok=True)
    return f"Created directory: {path}"


async def move_file_tool(
    ctx: RunContext[SessionDeps],
    source: str,
    destination: str,
) -> str:
    """
    Move or rename a file.

    Args:
        ctx: Run context with session dependencies
        source: Source file path
        destination: Destination file path

    Returns:
        Success message
    """
    import shutil

    src_path = os.path.abspath(source)
    dst_path = os.path.abspath(destination)

    # Set session context
    from .filesystem import set_current_session_id
    set_current_session_id(ctx.deps.session_id)

    # Enforce read-before-write for source file
    check_file_writable(src_path)

    # Move file
    shutil.move(src_path, dst_path)

    return f"Moved {source} to {destination}"


async def get_file_info_tool(ctx: RunContext[SessionDeps], path: str) -> str:
    """
    Get information about a file or directory.

    Args:
        ctx: Run context with session dependencies
        path: Path to file or directory

    Returns:
        Formatted file information
    """
    file_path = os.path.abspath(path)

    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Path not found: {path}")

    stat = os.stat(file_path)
    is_dir = os.path.isdir(file_path)

    from datetime import datetime
    mtime = datetime.fromtimestamp(stat.st_mtime)

    info = [
        f"Path: {path}",
        f"Type: {'Directory' if is_dir else 'File'}",
        f"Size: {stat.st_size} bytes",
        f"Modified: {mtime.isoformat()}",
        f"Permissions: {oct(stat.st_mode)[-3:]}",
    ]

    return "\n".join(info)
