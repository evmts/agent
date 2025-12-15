"""
Configuration management for the agent project.

Supports loading configuration from JSON/JSONC files with comment stripping,
merging global and project-level configs, and providing a cached config interface.
"""

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field


class PermissionsConfig(BaseModel):
    """Default permissions configuration."""

    edit_patterns: list[str] = Field(
        default_factory=lambda: ["**/*"],
        description="File patterns that can be edited",
    )
    bash_patterns: list[str] = Field(
        default_factory=lambda: ["*"],
        description="Bash command patterns that can be executed",
    )
    webfetch_enabled: bool = Field(
        default=True,
        description="Whether web fetch is enabled",
    )


class AgentConfig(BaseModel):
    """Custom agent configuration."""

    model_id: str = Field(
        default="claude-sonnet-4-20250514",
        description="Model identifier for the agent",
    )
    system_prompt: str | None = Field(
        default=None,
        description="Custom system prompt override",
    )
    tools: list[str] | None = Field(
        default=None,
        description="Specific tools to enable for this agent (if None, use all)",
    )
    temperature: float | None = Field(
        default=None,
        description="Model temperature override",
    )


class ToolsConfig(BaseModel):
    """Tool enable/disable flags."""

    python: bool = Field(default=True, description="Enable Python execution")
    shell: bool = Field(default=True, description="Enable shell execution")
    read: bool = Field(default=True, description="Enable file reading")
    write: bool = Field(default=True, description="Enable file writing")
    search: bool = Field(default=True, description="Enable file searching")
    ls: bool = Field(default=True, description="Enable directory listing")
    fetch: bool = Field(default=True, description="Enable web fetching")
    web: bool = Field(default=True, description="Enable web search")


class MCPServerConfig(BaseModel):
    """MCP (Model Context Protocol) server configuration."""

    command: str = Field(description="Command to start the MCP server")
    args: list[str] = Field(default_factory=list, description="Command arguments")
    env: dict[str, str] = Field(
        default_factory=dict, description="Environment variables"
    )


class ExperimentalConfig(BaseModel):
    """Experimental features configuration."""

    streaming: bool = Field(
        default=False, description="Enable streaming responses"
    )
    parallel_tools: bool = Field(
        default=False, description="Enable parallel tool execution"
    )
    caching: bool = Field(
        default=False, description="Enable response caching"
    )


class Config(BaseModel):
    """Main configuration model."""

    agents: dict[str, AgentConfig] = Field(
        default_factory=dict,
        description="Custom agent configurations by name",
    )
    tools: ToolsConfig = Field(
        default_factory=ToolsConfig,
        description="Tool enable/disable flags",
    )
    permissions: PermissionsConfig = Field(
        default_factory=PermissionsConfig,
        description="Default permissions",
    )
    theme: str = Field(
        default="default",
        description="Default theme name",
    )
    keybindings: dict[str, str] = Field(
        default_factory=dict,
        description="Custom keybindings",
    )
    mcp: dict[str, MCPServerConfig] = Field(
        default_factory=dict,
        description="MCP server configurations (placeholder for future)",
    )
    experimental: ExperimentalConfig = Field(
        default_factory=ExperimentalConfig,
        description="Experimental features flags",
    )


def strip_jsonc_comments(content: str) -> str:
    """
    Strip comments from JSONC content to convert to valid JSON.

    Handles:
    - Single-line comments: // comment
    - Multi-line comments: /* comment */

    Args:
        content: JSONC content string

    Returns:
        JSON string with comments removed
    """
    # Remove single-line comments
    content = re.sub(r"//.*?$", "", content, flags=re.MULTILINE)
    # Remove multi-line comments
    content = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)
    return content


def load_config_file(path: Path) -> dict[str, Any] | None:
    """
    Load a config file from the given path.

    Supports both .json and .jsonc files with comment stripping.

    Args:
        path: Path to the config file

    Returns:
        Parsed config dictionary or None if file doesn't exist
    """
    if not path.exists():
        return None

    try:
        content = path.read_text()
        # Strip comments if JSONC
        if path.suffix == ".jsonc":
            content = strip_jsonc_comments(content)
        return json.loads(content)
    except (json.JSONDecodeError, OSError) as e:
        print(f"Warning: Failed to load config from {path}: {e}")
        return None


def merge_configs(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """
    Deep merge two configuration dictionaries.

    Args:
        base: Base configuration
        override: Override configuration (takes precedence)

    Returns:
        Merged configuration dictionary
    """
    result = base.copy()

    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = merge_configs(result[key], value)
        else:
            result[key] = value

    return result


def load_config(project_root: Path | None = None) -> Config:
    """
    Load configuration from multiple sources with precedence.

    Looks for config files in the following order:
    1. Project-level: opencode.jsonc, opencode.json, .opencode/opencode.jsonc
    2. Global: ~/.opencode/opencode.jsonc

    Project config is merged with and takes precedence over global config.

    Args:
        project_root: Project root directory (defaults to current working directory)

    Returns:
        Loaded and merged Config model
    """
    if project_root is None:
        project_root = Path.cwd()

    # Try global config first (lower precedence)
    global_config_path = Path.home() / ".opencode" / "opencode.jsonc"
    config_data = load_config_file(global_config_path) or {}

    # Try project-level configs (higher precedence)
    project_config_paths = [
        project_root / "opencode.jsonc",
        project_root / "opencode.json",
        project_root / ".opencode" / "opencode.jsonc",
    ]

    for path in project_config_paths:
        project_config = load_config_file(path)
        if project_config:
            config_data = merge_configs(config_data, project_config)
            break

    # Create and validate Config model
    return Config(**config_data)


@lru_cache(maxsize=1)
def get_config(project_root: Path | None = None) -> Config:
    """
    Get cached configuration.

    This function caches the config to avoid repeated file I/O.
    To reload the config, clear the cache with get_config.cache_clear().

    Args:
        project_root: Project root directory (defaults to current working directory)

    Returns:
        Cached Config model
    """
    # Convert to string for hashability in lru_cache
    root = project_root or Path.cwd()
    return load_config(root)
