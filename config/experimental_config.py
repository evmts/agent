"""ExperimentalConfig model."""

from pydantic import BaseModel, Field


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
