"""
Configuration module for the agent project.

Exports the main configuration classes and functions for use throughout the application.
"""

from .agent_config import AgentConfig
from .defaults import DEFAULT_MODEL
from .experimental_config import ExperimentalConfig
from .loader import get_config, load_config, load_config_file, merge_configs, strip_jsonc_comments
from .main_config import Config
from .mcp_server_config import MCPServerConfig
from .permissions_config import PermissionsConfig
from .tools_config import ToolsConfig

__all__ = [
    # Constants
    "DEFAULT_MODEL",
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
    "load_config_file",
    "merge_configs",
    "strip_jsonc_comments",
]
