"""ToolsConfig model."""

from pydantic import BaseModel, Field


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
