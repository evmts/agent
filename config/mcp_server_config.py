"""MCPServerConfig model."""

from pydantic import BaseModel, Field


class MCPServerConfig(BaseModel):
    """MCP (Model Context Protocol) server configuration."""

    command: str = Field(description="Command to start the MCP server")
    args: list[str] = Field(default_factory=list, description="Command arguments")
    env: dict[str, str] = Field(
        default_factory=dict, description="Environment variables"
    )
