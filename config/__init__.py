"""
Configuration module for the agent project.

Exports the main configuration classes and functions for use throughout the application.
"""

from .agent_config import AgentConfig
from .defaults import DEFAULT_MODEL
from .experimental_config import ExperimentalConfig
from .loader import get_config, get_working_directory, load_config, load_config_file, merge_configs, strip_jsonc_comments
from .main_config import Config
from .markdown_loader import (
    AGENTS_MD_FILENAME,
    CLAUDE_MD_FILENAME,
    find_markdown_file,
    load_system_prompt_markdown,
)
from .mcp_server_config import MCPServerConfig
from .permissions_config import PermissionsConfig
from .tools_config import ToolsConfig

__all__ = [
    # Constants
    "DEFAULT_MODEL",
    "CLAUDE_MD_FILENAME",
    "AGENTS_MD_FILENAME",
    # Config models
    "Config",
    "AgentConfig",
    "ToolsConfig",
    "PermissionsConfig",
    "MCPServerConfig",
    "ExperimentalConfig",
    # Loader functions
    "load_config",
    "get_config",
    "get_working_directory",
    "load_config_file",
    "merge_configs",
    "strip_jsonc_comments",
    # Markdown loader functions
    "load_system_prompt_markdown",
    "find_markdown_file",
]
