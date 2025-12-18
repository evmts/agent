"""
Server-side state management.

This module provides agent management for the server layer.
Core storage is managed in core/state.py.
"""

from typing import Any

from core.permissions import PermissionChecker


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


# =============================================================================
# Permission Management
# =============================================================================

_permission_checker: PermissionChecker | None = None


def set_permission_checker(checker: PermissionChecker) -> None:
    """Set the permission checker instance."""
    global _permission_checker
    _permission_checker = checker


def get_permission_checker() -> PermissionChecker | None:
    """Get the current permission checker instance."""
    return _permission_checker
