"""
Commands endpoint for listing available slash commands.

Provides the list of built-in commands for TUI command palette functionality.
"""

from fastapi import APIRouter, Query
from pydantic import BaseModel


router = APIRouter()


class Command(BaseModel):
    """A slash command definition."""

    name: str
    description: str


# =============================================================================
# Built-in Commands
# =============================================================================

BUILTIN_COMMANDS = [
    Command(name="help", description="Show help information"),
    Command(name="clear", description="Clear conversation"),
    Command(name="new", description="Start new session"),
    Command(name="sessions", description="List all sessions"),
    Command(name="compact", description="Summarize conversation to reduce context"),
    Command(name="model", description="Select AI model"),
    Command(name="agent", description="Select agent mode"),
    Command(name="theme", description="Change color theme"),
    Command(name="settings", description="Open settings"),
    Command(name="diff", description="Show file changes in session"),
    Command(name="copy", description="Copy last response"),
    Command(name="quit", description="Exit application"),
]


# =============================================================================
# Endpoints
# =============================================================================


@router.get("/command")
async def list_commands(directory: str | None = Query(None)) -> list[Command]:
    """
    List available slash commands.

    Args:
        directory: Optional directory path for loading custom commands

    Returns:
        List of available commands
    """
    commands = BUILTIN_COMMANDS.copy()

    # TODO: Could extend to load custom commands from directory/.agent/commands/
    # For now, just return built-ins

    return commands
