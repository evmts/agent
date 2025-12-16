"""
Server-side state management.

This module provides agent management for the server layer.
Core storage is managed in core/state.py.
"""

from typing import Any


# =============================================================================
# Agent Management
# =============================================================================

_agent: Any = None


def set_agent(new_agent: Any) -> None:
    """Set the agent instance. Called by agent configuration module."""
    global _agent
    _agent = new_agent


def get_agent() -> Any:
    """Get the current agent instance."""
    return _agent
