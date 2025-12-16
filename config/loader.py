"""Configuration loading utilities."""

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

from .main_config import Config


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


def get_working_directory() -> str:
    """
    Get the working directory from environment or default to cwd.

    Returns:
        The working directory path as a string
    """
    import os
    return os.environ.get("WORKING_DIR", os.getcwd())


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
