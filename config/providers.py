"""Model provider configuration and registry."""

from dataclasses import dataclass, field
from typing import Optional
import os


@dataclass
class ModelProvider:
    """Represents a model provider configuration.

    Attributes:
        id: Unique identifier for the provider
        name: Human-readable name
        base_url: Base URL for API requests
        env_key: Environment variable name for API key (None for local providers)
        default_model: Default model ID for this provider
        http_headers: Additional HTTP headers to include in requests
    """
    id: str
    name: str
    base_url: str
    env_key: Optional[str] = None
    default_model: str = ""
    http_headers: dict[str, str] = field(default_factory=dict)

    def get_api_key(self) -> Optional[str]:
        """Get API key from environment variable.

        Returns:
            API key string if env_key is set and variable exists, None otherwise
        """
        if self.env_key:
            return os.environ.get(self.env_key)
        return None

    def is_local(self) -> bool:
        """Check if provider is local (no API key needed).

        Returns:
            True if provider doesn't require an API key
        """
        return self.env_key is None

    def get_client_kwargs(self) -> dict:
        """Get kwargs for HTTP client initialization.

        Returns:
            Dictionary with base_url, headers, and authentication configuration
        """
        kwargs = {
            "base_url": self.base_url,
            "headers": self.http_headers.copy(),
        }

        api_key = self.get_api_key()
        if api_key:
            # Anthropic uses x-api-key header, others use Authorization Bearer
            if "anthropic" in self.id.lower():
                kwargs["headers"]["x-api-key"] = api_key
                kwargs["headers"]["anthropic-version"] = "2023-06-01"
            else:
                kwargs["headers"]["Authorization"] = f"Bearer {api_key}"

        return kwargs


class ProviderRegistry:
    """Registry for managing model providers.

    Handles default and custom provider configurations, loading from
    config files, and retrieving active providers.
    """

    def __init__(self) -> None:
        """Initialize the provider registry with default providers."""
        self._providers: dict[str, ModelProvider] = {}
        self._load_defaults()

    def _load_defaults(self) -> None:
        """Load default providers from config.defaults."""
        from config.defaults import DEFAULT_MODEL_PROVIDERS

        for provider_id, config in DEFAULT_MODEL_PROVIDERS.items():
            self._providers[provider_id] = ModelProvider(id=provider_id, **config)

    def load_from_config(self, config: dict) -> None:
        """Load custom providers from configuration dictionary.

        Args:
            config: Configuration dictionary with optional 'model_providers' section
        """
        providers_config = config.get("model_providers", {})
        for provider_id, provider_config in providers_config.items():
            self._providers[provider_id] = ModelProvider(id=provider_id, **provider_config)

    def get(self, provider_id: str) -> Optional[ModelProvider]:
        """Get provider by ID.

        Args:
            provider_id: Provider identifier

        Returns:
            ModelProvider instance or None if not found
        """
        return self._providers.get(provider_id)

    def list_providers(self) -> list[ModelProvider]:
        """List all available providers.

        Returns:
            List of all registered ModelProvider instances
        """
        return list(self._providers.values())

    def get_active_provider(self, config: dict) -> ModelProvider:
        """Get the active provider based on configuration.

        Args:
            config: Configuration dictionary with optional 'model_provider' key

        Returns:
            Active ModelProvider instance

        Raises:
            ValueError: If specified provider is not found
        """
        provider_id = config.get("model_provider", "anthropic")
        provider = self.get(provider_id)
        if not provider:
            raise ValueError(f"Unknown provider: {provider_id}")
        return provider


# Global registry instance
provider_registry = ProviderRegistry()
