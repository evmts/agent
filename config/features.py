"""Feature flags system for gradual rollout and user control of features."""

from dataclasses import dataclass
from enum import Enum
from typing import Optional


class FeatureStage(Enum):
    """Feature development stages."""

    EXPERIMENTAL = "experimental"
    BETA = "beta"
    STABLE = "stable"


@dataclass
class FeatureFlag:
    """Definition of a feature flag."""

    name: str
    description: str
    stage: FeatureStage
    default: bool
    deprecated: bool = False
    deprecated_by: Optional[str] = None


# Feature flag registry
FEATURE_FLAGS = {
    # Stable features (on by default)
    "shell_tool": FeatureFlag(
        name="shell_tool",
        description="Enable shell command execution tool",
        stage=FeatureStage.STABLE,
        default=True,
    ),
    "view_image": FeatureFlag(
        name="view_image",
        description="Enable image viewing/attachment",
        stage=FeatureStage.STABLE,
        default=True,
    ),
    # Beta features
    "web_search": FeatureFlag(
        name="web_search",
        description="Enable web search capability",
        stage=FeatureStage.BETA,
        default=False,
    ),
    "patch_tool": FeatureFlag(
        name="patch_tool",
        description="Enable multi-file patch tool",
        stage=FeatureStage.BETA,
        default=True,
    ),
    # Experimental features
    "ghost_commit": FeatureFlag(
        name="ghost_commit",
        description="Create ghost commit after each turn",
        stage=FeatureStage.EXPERIMENTAL,
        default=False,
    ),
    "skills": FeatureFlag(
        name="skills",
        description="Enable skills discovery and injection",
        stage=FeatureStage.EXPERIMENTAL,
        default=False,
    ),
    "unified_exec": FeatureFlag(
        name="unified_exec",
        description="Enable PTY-backed interactive execution",
        stage=FeatureStage.EXPERIMENTAL,
        default=False,
    ),
    "parallel_tools": FeatureFlag(
        name="parallel_tools",
        description="Enable parallel tool call execution",
        stage=FeatureStage.EXPERIMENTAL,
        default=False,
    ),
    "plugins": FeatureFlag(
        name="plugins",
        description="Enable plugin system for agent customization",
        stage=FeatureStage.EXPERIMENTAL,
        default=False,
    ),
}


class FeatureManager:
    """Manages feature flag state and evaluation."""

    def __init__(self) -> None:
        """Initialize feature manager with no overrides."""
        self._overrides: dict[str, bool] = {}

    def load_from_config(self, config: dict) -> None:
        """Load feature overrides from config.

        Args:
            config: Configuration dict that may contain a 'features' section
        """
        features_config = config.get("features", {})
        for name, value in features_config.items():
            if name in FEATURE_FLAGS:
                self._overrides[name] = bool(value)

    def enable(self, name: str) -> None:
        """Enable a feature.

        Args:
            name: Feature name to enable
        """
        if name in FEATURE_FLAGS:
            self._overrides[name] = True

    def disable(self, name: str) -> None:
        """Disable a feature.

        Args:
            name: Feature name to disable
        """
        if name in FEATURE_FLAGS:
            self._overrides[name] = False

    def is_enabled(self, name: str) -> bool:
        """Check if a feature is enabled.

        Args:
            name: Feature name to check

        Returns:
            True if feature is enabled, False otherwise
        """
        if name in self._overrides:
            return self._overrides[name]

        flag = FEATURE_FLAGS.get(name)
        if flag:
            return flag.default

        return False

    def list_features(self) -> list[dict]:
        """List all features with current status.

        Returns:
            List of feature dictionaries with status information
        """
        features = []
        for name, flag in FEATURE_FLAGS.items():
            enabled = self.is_enabled(name)
            features.append({
                "name": name,
                "description": flag.description,
                "stage": flag.stage.value,
                "default": flag.default,
                "enabled": enabled,
                "overridden": name in self._overrides,
                "deprecated": flag.deprecated,
            })
        return features


# Global instance
feature_manager = FeatureManager()
