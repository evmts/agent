"""
Drop-in integration for file safety enforcement.

This module provides a simple way to enable read-before-write safety
for the agent without major refactoring.
"""

import os
from typing import Callable, Any

from .filesystem import set_current_session_id, mark_file_read, mark_file_written, check_file_writable


def create_safe_read_wrapper(original_read: Callable) -> Callable:
    """
    Wrap a read_file function to track reads for safety.

    Args:
        original_read: The original read_file implementation

    Returns:
        Wrapped function that tracks file reads
    """
    async def safe_read(*args, **kwargs):
        # Call original
        result = await original_read(*args, **kwargs)

        # Extract path from args
        if args:
            path = args[0]
        elif 'path' in kwargs:
            path = kwargs['path']
        else:
            return result

        # Mark as read
        mark_file_read(path)
        return result

    # Preserve function metadata
    safe_read.__name__ = original_read.__name__
    safe_read.__doc__ = original_read.__doc__
    return safe_read


def create_safe_write_wrapper(original_write: Callable) -> Callable:
    """
    Wrap a write_file function to enforce read-before-write safety.

    Args:
        original_write: The original write_file implementation

    Returns:
        Wrapped function that enforces safety checks
    """
    async def safe_write(*args, **kwargs):
        # Extract path from args
        if args:
            path = args[0]
        elif 'path' in kwargs:
            path = kwargs['path']
        else:
            # Can't enforce without path
            return await original_write(*args, **kwargs)

        # Enforce read-before-write
        check_file_writable(path)

        # Call original
        result = await original_write(*args, **kwargs)

        # Update tracking after successful write
        mark_file_written(path)
        return result

    # Preserve function metadata
    safe_write.__name__ = original_write.__name__
    safe_write.__doc__ = original_write.__doc__
    return safe_write


def enable_file_safety_for_session(session_id: str) -> Callable:
    """
    Create a context manager to enable file safety for a session.

    Usage:
        with enable_file_safety_for_session("session-123"):
            # File operations are now tracked
            pass

    Args:
        session_id: Session identifier

    Returns:
        Context manager
    """
    class SessionContext:
        def __enter__(self):
            set_current_session_id(session_id)
            return self

        def __exit__(self, *args):
            set_current_session_id(None)

    return SessionContext()


async def enable_file_safety_for_agent(agent: Any, session_id: str) -> None:
    """
    Enable file safety tracking for an agent instance.

    This function monkey-patches the agent's file tools to add safety checks.
    Should be called before the agent starts processing requests.

    Args:
        agent: The Pydantic AI agent instance
        session_id: Session identifier for tracking

    Example:
        async with create_agent_with_mcp() as agent:
            enable_file_safety_for_agent(agent, "session-123")
            # Now use agent normally
    """
    # Set session context
    set_current_session_id(session_id)

    # Note: Monkey-patching MCP tools is complex due to their architecture
    # This is a placeholder for a more complete implementation
    # The recommended approach is to use Option 1 from README.md

    # TODO: Implement MCP tool wrapping or use custom tools instead
    pass


# Simple example of standalone safe file operations
async def safe_read_file(path: str) -> str:
    """
    Read a file and track it for safety.

    Args:
        path: Path to file

    Returns:
        File contents
    """
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    mark_file_read(path)
    return content


async def safe_write_file(path: str, content: str) -> str:
    """
    Write a file with safety enforcement.

    Args:
        path: Path to file
        content: Content to write

    Returns:
        Success message
    """
    check_file_writable(path)

    # Create parent directories if needed
    os.makedirs(os.path.dirname(os.path.abspath(path)) or '.', exist_ok=True)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

    mark_file_written(path)
    return f"Successfully wrote {len(content)} bytes to {path}"
