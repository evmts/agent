"""PermissionsConfig model."""

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
