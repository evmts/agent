"""
Configuration endpoint for TUI settings.
"""

import os
from pathlib import Path

from fastapi import APIRouter, Query
from pydantic import BaseModel, Field

from config.defaults import DEFAULT_MODEL
from config.loader import get_config

# =============================================================================
# Constants
# =============================================================================

DEFAULT_THEME = "default"
DEFAULT_LEADER_KEY = "ctrl+x"
DEFAULT_SCROLL_SPEED = 3


# =============================================================================
# Models
# =============================================================================


class Keybinds(BaseModel):
    """Keybind configuration."""

    leader: str = Field(
        default=DEFAULT_LEADER_KEY,
        description="Leader key for TUI commands",
    )


class TuiConfig(BaseModel):
    """TUI-specific configuration."""

    scrollSpeed: int = Field(
        default=DEFAULT_SCROLL_SPEED,
        description="Scroll speed for TUI",
    )


class ConfigResponse(BaseModel):
    """Configuration response model."""

    theme: str = Field(
        default=DEFAULT_THEME,
        description="Theme name",
    )
    model: str = Field(
        description="Default model identifier in provider/model format",
    )
    keybinds: Keybinds = Field(
        default_factory=Keybinds,
        description="Keybind configuration",
    )
    tui: TuiConfig = Field(
        default_factory=TuiConfig,
        description="TUI-specific settings",
    )


# =============================================================================
# Router
# =============================================================================

router = APIRouter()


@router.get("/config")
async def get_config_endpoint(directory: str | None = Query(None)) -> ConfigResponse:
    """
    Get TUI configuration including theme, keybinds, and UI settings.

    Args:
        directory: Optional project directory for loading project-specific config

    Returns:
        Configuration with theme, model, keybinds, and TUI settings
    """
    # Load config from file if directory is specified
    project_root = Path(directory) if directory else None
    config = get_config(project_root)

    # Get model from environment or use default
    model_id = os.environ.get("ANTHROPIC_MODEL", DEFAULT_MODEL)
    # Format as provider/model
    default_model = f"anthropic/{model_id}"

    # Get theme from config or environment
    theme = os.environ.get("THEME", config.theme)

    # Get leader key from config keybindings or environment
    leader_key = os.environ.get(
        "LEADER_KEY",
        config.keybindings.get("leader", DEFAULT_LEADER_KEY)
    )

    # Get scroll speed from environment (no config file equivalent yet)
    scroll_speed = int(os.environ.get("SCROLL_SPEED", str(DEFAULT_SCROLL_SPEED)))

    return ConfigResponse(
        theme=theme,
        model=default_model,
        keybinds=Keybinds(leader=leader_key),
        tui=TuiConfig(scrollSpeed=scroll_speed)
    )
