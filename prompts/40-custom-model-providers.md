# Custom Model Providers

<metadata>
  <priority>medium</priority>
  <category>configuration</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>config/, agent/</affects>
</metadata>

## Objective

Implement support for custom model providers, allowing users to configure alternative API endpoints including local models (LM Studio, Ollama), Azure OpenAI, and other compatible services.

<context>
Codex supports custom model providers via configuration. This enables:
- Using local models with LM Studio or Ollama
- Connecting to Azure OpenAI deployments
- Using alternative API-compatible services
- Custom headers and authentication

This is essential for enterprise deployments, privacy-conscious users, and developers wanting to use open-source models.
</context>

## Requirements

<functional-requirements>
1. Model provider configuration in config file
2. Built-in providers:
   - `anthropic` (default)
   - `ollama` - Local Ollama server
   - `lmstudio` - LM Studio local server
   - `openai` - OpenAI API
   - `azure` - Azure OpenAI
3. Custom provider fields:
   - name, base_url
   - env_key (API key env var)
   - http_headers
   - Default model
4. Provider selection via config or CLI flag
5. Environment variable support for secrets
</functional-requirements>

<technical-requirements>
1. Add model_providers section to config schema
2. Implement provider registry
3. Support multiple API formats (chat completions)
4. Handle provider-specific authentication
5. Add --provider CLI flag
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `config/defaults.py` - Default provider configurations
- `config/providers.py` (CREATE) - Provider management
- `agent/agent.py` - Provider-aware client initialization
- `tui/main.go` - Add --provider flag
</files-to-modify>

<config-format>
```python
# config/defaults.py

DEFAULT_MODEL_PROVIDERS = {
    "anthropic": {
        "name": "Anthropic",
        "base_url": "https://api.anthropic.com/v1",
        "env_key": "ANTHROPIC_API_KEY",
        "default_model": "claude-sonnet-4-20250514",
    },
    "openai": {
        "name": "OpenAI",
        "base_url": "https://api.openai.com/v1",
        "env_key": "OPENAI_API_KEY",
        "default_model": "gpt-4o",
    },
    "ollama": {
        "name": "Ollama (Local)",
        "base_url": "http://localhost:11434/v1",
        "env_key": None,  # No API key needed
        "default_model": "llama3.2",
    },
    "lmstudio": {
        "name": "LM Studio (Local)",
        "base_url": "http://localhost:1234/v1",
        "env_key": None,
        "default_model": "local-model",
    },
}
```
</config-format>

<provider-config-file>
```toml
# ~/.agent/config.toml

# Select active provider
model_provider = "anthropic"

# Override default model
model = "claude-opus-4-5-20251101"

# Custom provider configuration
[model_providers.azure]
name = "Azure OpenAI"
base_url = "https://my-deployment.openai.azure.com"
env_key = "AZURE_OPENAI_API_KEY"
default_model = "gpt-4o"
http_headers = { "api-version" = "2024-02-01" }

[model_providers.custom]
name = "My Custom Provider"
base_url = "https://api.my-provider.com/v1"
env_key = "CUSTOM_API_KEY"
default_model = "custom-model"
http_headers = { "X-Custom-Header" = "value" }
```
</provider-config-file>

<provider-class>
```python
# config/providers.py

from dataclasses import dataclass, field
from typing import Optional
import os
import httpx

@dataclass
class ModelProvider:
    id: str
    name: str
    base_url: str
    env_key: Optional[str] = None
    default_model: str = ""
    http_headers: dict[str, str] = field(default_factory=dict)

    def get_api_key(self) -> Optional[str]:
        """Get API key from environment."""
        if self.env_key:
            return os.environ.get(self.env_key)
        return None

    def is_local(self) -> bool:
        """Check if provider is local (no API key needed)."""
        return self.env_key is None

    def get_client_kwargs(self) -> dict:
        """Get kwargs for HTTP client initialization."""
        kwargs = {
            "base_url": self.base_url,
            "headers": self.http_headers.copy(),
        }

        api_key = self.get_api_key()
        if api_key:
            if "anthropic" in self.id:
                kwargs["headers"]["x-api-key"] = api_key
            else:
                kwargs["headers"]["Authorization"] = f"Bearer {api_key}"

        return kwargs


class ProviderRegistry:
    def __init__(self):
        self._providers: dict[str, ModelProvider] = {}
        self._load_defaults()

    def _load_defaults(self):
        """Load default providers."""
        from config.defaults import DEFAULT_MODEL_PROVIDERS

        for id, config in DEFAULT_MODEL_PROVIDERS.items():
            self._providers[id] = ModelProvider(id=id, **config)

    def load_from_config(self, config: dict):
        """Load custom providers from config."""
        providers_config = config.get("model_providers", {})
        for id, provider_config in providers_config.items():
            self._providers[id] = ModelProvider(id=id, **provider_config)

    def get(self, id: str) -> Optional[ModelProvider]:
        """Get provider by ID."""
        return self._providers.get(id)

    def list_providers(self) -> list[ModelProvider]:
        """List all available providers."""
        return list(self._providers.values())

    def get_active_provider(self, config: dict) -> ModelProvider:
        """Get the active provider based on config."""
        provider_id = config.get("model_provider", "anthropic")
        provider = self.get(provider_id)
        if not provider:
            raise ValueError(f"Unknown provider: {provider_id}")
        return provider


# Global registry
provider_registry = ProviderRegistry()
```
</provider-class>

<agent-integration>
```python
# agent/agent.py

from config.providers import provider_registry

def create_agent_with_provider(
    provider_id: Optional[str] = None,
    model: Optional[str] = None,
    **kwargs
) -> Agent:
    """Create agent with specified provider."""
    config = load_config()

    # Get provider
    provider = provider_registry.get_active_provider(config)
    if provider_id:
        provider = provider_registry.get(provider_id)
        if not provider:
            raise ValueError(f"Unknown provider: {provider_id}")

    # Validate API key for non-local providers
    if not provider.is_local() and not provider.get_api_key():
        raise ValueError(
            f"API key not set. Set {provider.env_key} environment variable."
        )

    # Determine model
    model = model or config.get("model") or provider.default_model

    # Create client with provider settings
    client_kwargs = provider.get_client_kwargs()

    # Create and return agent
    return create_agent(
        model=model,
        base_url=provider.base_url,
        api_key=provider.get_api_key(),
        headers=client_kwargs.get("headers", {}),
        **kwargs
    )
```
</agent-integration>

<cli-flag>
```go
// In TUI main.go

var providerFlag string

func init() {
    rootCmd.PersistentFlags().StringVarP(
        &providerFlag, "provider", "p", "",
        "Model provider to use (anthropic, openai, ollama, lmstudio, or custom)",
    )
}

// In session creation
func createSession() {
    req := SessionCreateRequest{
        Provider: providerFlag,
        Model:    modelFlag,
        // ...
    }
}
```
</cli-flag>

## Acceptance Criteria

<criteria>
- [ ] Default providers configured (anthropic, openai, ollama, lmstudio)
- [ ] Custom providers via config file
- [ ] Provider selection via config.toml
- [ ] --provider CLI flag
- [ ] API key from environment variable
- [ ] Custom headers supported
- [ ] Local providers work without API key
- [ ] Base URL configurable
- [ ] Provider-specific authentication
- [ ] Error handling for missing API keys
- [ ] List available providers
</criteria>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Test with Anthropic (default)
3. Test with local Ollama (if available)
4. Test custom provider configuration
5. Run `pytest` to ensure all passes
6. Rename this file from `40-custom-model-providers.md` to `40-custom-model-providers.complete.md`
</completion>
