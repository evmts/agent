"""
Plugin management API endpoints.

Provides REST endpoints for listing, viewing, saving, and deleting plugins.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from config.features import feature_manager

router = APIRouter(prefix="/plugin", tags=["plugins"])
logger = logging.getLogger(__name__)


# =============================================================================
# Request/Response Models
# =============================================================================


class PluginInfo(BaseModel):
    """Basic plugin information."""

    name: str
    hooks: list[str]
    metadata: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None


class PluginDetail(BaseModel):
    """Detailed plugin information including content."""

    name: str
    path: str
    hooks: list[str]
    metadata: dict[str, Any] = Field(default_factory=dict)
    content: str


class SavePluginRequest(BaseModel):
    """Request to save a new plugin."""

    name: str = Field(..., description="Plugin name (used as filename)")
    content: str = Field(..., description="Plugin Python source code")


class SavePluginResponse(BaseModel):
    """Response from saving a plugin."""

    name: str
    path: str


class DeletePluginResponse(BaseModel):
    """Response from deleting a plugin."""

    deleted: str


class PluginListResponse(BaseModel):
    """Response containing list of plugins."""

    plugins: list[PluginInfo]
    feature_enabled: bool


# =============================================================================
# Helper Functions
# =============================================================================


def _check_feature_enabled() -> None:
    """Check if plugins feature is enabled.

    Raises:
        HTTPException: If plugins feature is disabled
    """
    if not feature_manager.is_enabled("plugins"):
        raise HTTPException(
            status_code=503,
            detail="Plugins feature is not enabled. Enable it in settings.",
        )


# =============================================================================
# Endpoints
# =============================================================================


@router.get("/list", response_model=PluginListResponse)
async def list_plugins_endpoint() -> PluginListResponse:
    """List all available plugins.

    Returns plugin information including hooks and metadata.
    Works even when plugins feature is disabled (to show available plugins).
    """
    from plugins.storage import list_plugins as list_plugin_files
    from plugins.loader import load_plugin_from_file

    plugins = []
    for path in list_plugin_files():
        try:
            loaded = load_plugin_from_file(path)
            plugins.append(
                PluginInfo(
                    name=loaded.name,
                    hooks=list(loaded.hooks.keys()),
                    metadata=loaded.metadata,
                )
            )
        except Exception as e:
            logger.warning("Failed to load plugin %s: %s", path.stem, e)
            plugins.append(
                PluginInfo(
                    name=path.stem,
                    hooks=[],
                    error=str(e),
                )
            )

    return PluginListResponse(
        plugins=plugins,
        feature_enabled=feature_manager.is_enabled("plugins"),
    )


@router.get("/{name}", response_model=PluginDetail)
async def get_plugin_endpoint(name: str) -> PluginDetail:
    """Get detailed information about a specific plugin.

    Args:
        name: Plugin name (without .py extension)

    Returns:
        Detailed plugin information including source code

    Raises:
        HTTPException: If plugin not found
    """
    from plugins.storage import get_plugin_path, get_plugin_content
    from plugins.loader import load_plugin_from_file

    path = get_plugin_path(name)
    if not path:
        raise HTTPException(status_code=404, detail=f"Plugin not found: {name}")

    content = get_plugin_content(name)
    if content is None:
        raise HTTPException(status_code=404, detail=f"Plugin not found: {name}")

    try:
        loaded = load_plugin_from_file(path)
        return PluginDetail(
            name=loaded.name,
            path=str(path),
            hooks=list(loaded.hooks.keys()),
            metadata=loaded.metadata,
            content=content,
        )
    except Exception as e:
        # Return basic info even if plugin has errors
        return PluginDetail(
            name=name,
            path=str(path),
            hooks=[],
            metadata={"error": str(e)},
            content=content,
        )


@router.post("/save", response_model=SavePluginResponse)
async def save_plugin_endpoint(request: SavePluginRequest) -> SavePluginResponse:
    """Save a new plugin or update an existing one.

    Args:
        request: Plugin name and source code

    Returns:
        Name and path of saved plugin

    Raises:
        HTTPException: If plugins feature is disabled or save fails
    """
    _check_feature_enabled()

    from plugins.storage import save_plugin

    try:
        path = save_plugin(request.name, request.content)
        logger.info("Saved plugin '%s' to %s", request.name, path)
        return SavePluginResponse(name=request.name, path=str(path))
    except Exception as e:
        logger.error("Failed to save plugin '%s': %s", request.name, e)
        raise HTTPException(status_code=500, detail=f"Failed to save plugin: {e}")


@router.delete("/{name}", response_model=DeletePluginResponse)
async def delete_plugin_endpoint(name: str) -> DeletePluginResponse:
    """Delete a plugin.

    Args:
        name: Plugin name (without .py extension)

    Returns:
        Name of deleted plugin

    Raises:
        HTTPException: If plugins feature is disabled or plugin not found
    """
    _check_feature_enabled()

    from plugins.storage import delete_plugin

    if delete_plugin(name):
        logger.info("Deleted plugin '%s'", name)
        return DeletePluginResponse(deleted=name)

    raise HTTPException(status_code=404, detail=f"Plugin not found: {name}")


@router.post("/{name}/reload")
async def reload_plugin_endpoint(name: str) -> PluginInfo:
    """Force reload a plugin from disk.

    Clears the cached version and loads fresh.

    Args:
        name: Plugin name (without .py extension)

    Returns:
        Updated plugin information

    Raises:
        HTTPException: If plugins feature is disabled or plugin not found
    """
    _check_feature_enabled()

    from plugins.registry import plugin_registry
    from plugins.storage import plugin_exists

    if not plugin_exists(name):
        raise HTTPException(status_code=404, detail=f"Plugin not found: {name}")

    try:
        plugin = plugin_registry.reload(name)
        logger.info("Reloaded plugin '%s'", name)
        return PluginInfo(
            name=plugin.name,
            hooks=list(plugin.hooks.keys()),
            metadata=plugin.metadata,
        )
    except Exception as e:
        logger.error("Failed to reload plugin '%s': %s", name, e)
        raise HTTPException(status_code=500, detail=f"Failed to reload plugin: {e}")


@router.post("/validate")
async def validate_plugin_endpoint(request: SavePluginRequest) -> PluginInfo:
    """Validate plugin code without saving.

    Attempts to compile and load the plugin to check for errors.

    Args:
        request: Plugin name and source code

    Returns:
        Plugin information if valid

    Raises:
        HTTPException: If plugin code is invalid
    """
    import tempfile
    from pathlib import Path

    from plugins.loader import load_plugin_from_file

    # Write to temp file and try to load
    with tempfile.TemporaryDirectory() as tmpdir:
        path = Path(tmpdir) / f"{request.name}.py"
        path.write_text(request.content)

        try:
            loaded = load_plugin_from_file(path)
            return PluginInfo(
                name=loaded.name,
                hooks=list(loaded.hooks.keys()),
                metadata=loaded.metadata,
            )
        except Exception as e:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid plugin code: {e}",
            )
