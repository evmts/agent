"""Main Config model."""

from pydantic import BaseModel, Field

from .agent_config import AgentConfig
from .experimental_config import ExperimentalConfig
from .mcp_server_config import MCPServerConfig
from .permissions_config import PermissionsConfig
from .tools_config import ToolsConfig


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
