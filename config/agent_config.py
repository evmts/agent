"""AgentConfig model for configuration."""

from pydantic import BaseModel, Field

from .defaults import DEFAULT_MODEL


class AgentConfig(BaseModel):
    """Custom agent configuration."""

    model_id: str = Field(
        default=DEFAULT_MODEL,
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
