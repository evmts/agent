# Configuration System

This directory contains the configuration management system for the agent project.

## Overview

The config system provides a flexible way to customize agent behavior, tool availability, permissions, and other settings through JSON/JSONC configuration files.

## Files

- **config.py**: Core configuration models and loading logic
- **__init__.py**: Module exports

## Configuration File Locations

The system looks for configuration files in the following order (later files override earlier ones):

1. Global config: `~/.opencode/opencode.jsonc`
2. Project-level configs (in order of precedence):
   - `opencode.jsonc` (recommended, supports comments)
   - `opencode.json`
   - `.opencode/opencode.jsonc`

## Configuration Schema

### Top-Level Structure

```jsonc
{
  "agents": {},           // Custom agent configurations
  "tools": {},           // Global tool enable/disable flags
  "permissions": {},     // Default permissions
  "theme": "default",    // UI theme name
  "keybindings": {},     // Custom keybindings
  "mcp": {},            // MCP server configurations
  "experimental": {},    // Experimental features
  "model": "",           // Override default model for active provider
  "model_provider": "anthropic",  // Active model provider ID
  "model_providers": {}  // Custom model provider configurations
}
```

### Agents Configuration

Define custom agents with specific behaviors and tool access:

```jsonc
{
  "agents": {
    "docs": {
      "model_id": "claude-sonnet-4-20250514",
      "system_prompt": "You are a documentation specialist...",
      "tools": ["read", "search", "ls", "web"],  // Specific tools for this agent
      "temperature": 0.5
    }
  }
}
```

**Fields:**
- `model_id` (string): Anthropic model identifier
- `system_prompt` (string, optional): Custom system prompt
- `tools` (array, optional): List of enabled tools. If not specified, uses global tools config
- `temperature` (number, optional): Model temperature (default: 0.7)

**Available tools:**
- `python` - Execute Python code
- `shell` - Execute shell commands
- `read` - Read files
- `write` - Write and edit files
- `search` - Search for files by pattern
- `ls` - List directory contents
- `fetch` - Fetch web content
- `web` - Search the web

### Tools Configuration

Global tool enable/disable flags (applies when agent doesn't specify tools):

```jsonc
{
  "tools": {
    "python": true,
    "shell": true,
    "read": true,
    "write": true,
    "search": true,
    "ls": true,
    "fetch": true,
    "web": true
  }
}
```

### Permissions Configuration

Default permissions for file operations and web access:

```jsonc
{
  "permissions": {
    "edit_patterns": ["**/*"],           // File patterns that can be edited
    "bash_patterns": ["*"],              // Shell command patterns allowed
    "webfetch_enabled": true             // Enable web fetch tool
  }
}
```

### MCP Configuration

Configure MCP (Model Context Protocol) servers:

```jsonc
{
  "mcp": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
      "env": {
        "NODE_ENV": "production"
      }
    }
  }
}
```

### Model Provider Configuration

Configure custom model providers to use alternative APIs including local models:

```jsonc
{
  "model_provider": "anthropic",  // Active provider ID
  "model": "claude-opus-4-5-20251101",  // Override default model for active provider
  "model_providers": {
    "azure": {
      "name": "Azure OpenAI",
      "base_url": "https://my-deployment.openai.azure.com",
      "env_key": "AZURE_OPENAI_API_KEY",
      "default_model": "gpt-4o",
      "http_headers": {
        "api-version": "2024-02-01"
      }
    },
    "custom": {
      "name": "My Custom Provider",
      "base_url": "http://localhost:8080/v1",
      "env_key": "CUSTOM_API_KEY",
      "default_model": "custom-model"
    }
  }
}
```

**Built-in Providers:**
- `anthropic` (default) - Anthropic Claude API
- `openai` - OpenAI API
- `ollama` - Local Ollama server (http://localhost:11434/v1)
- `lmstudio` - LM Studio local server (http://localhost:1234/v1)

**Custom Provider Fields:**
- `name` (string): Human-readable provider name
- `base_url` (string): Base URL for API requests
- `env_key` (string, optional): Environment variable name for API key. Set to `null` for local providers that don't require authentication
- `default_model` (string): Default model ID for this provider
- `http_headers` (object, optional): Additional HTTP headers to include in requests

**Example: Using Ollama Locally**

```jsonc
{
  "model_provider": "ollama",
  "model": "llama3.2"
}
```

No API key needed for Ollama since it's a local provider.

### Experimental Features

Enable experimental features:

```jsonc
{
  "experimental": {
    "streaming": false,        // Enable streaming responses
    "parallel_tools": false,   // Enable parallel tool execution
    "caching": false          // Enable response caching
  }
}
```

## Usage

### Loading Configuration

```python
from config import load_config, get_config
from pathlib import Path

# Load config from specific project root
config = load_config(Path("/path/to/project"))

# Get cached config (recommended for repeated access)
config = get_config()

# Access configuration
print(config.theme)
print(config.tools.python)
print(config.agents["docs"].model_id)
```

### Creating Agents with Config

The agent creation system automatically loads and applies configurations:

```python
from agent.agent import create_agent

# Create agent using config
agent = create_agent(agent_name="docs")  # Uses config from opencode.jsonc

# Built-in agents are still available
agent = create_agent(agent_name="build")
```

### Listing Available Agents

```python
from agent.registry import list_agent_names, get_agent_config

# List all available agents (built-in + custom)
for name in list_agent_names():
    config = get_agent_config(name)
    print(f"{name}: {config.description}")
```

### Using Model Providers

```python
from config import get_config
from config.providers import provider_registry

# Load configuration
config = get_config()

# Get the active provider
provider = provider_registry.get_active_provider(config.model_dump())
print(f"Using provider: {provider.name}")
print(f"Base URL: {provider.base_url}")
print(f"Default model: {provider.default_model}")

# List all available providers
for provider in provider_registry.list_providers():
    print(f"{provider.id}: {provider.name} ({provider.base_url})")

# Get a specific provider
ollama = provider_registry.get("ollama")
if ollama:
    print(f"Ollama is local: {ollama.is_local()}")
    client_kwargs = ollama.get_client_kwargs()
    print(f"Client kwargs: {client_kwargs}")
```

## Built-in Agents

The system includes several built-in agents:

- **build**: Default full-featured agent for general development
- **general**: Parallel task execution specialist
- **plan**: Read-only planning and analysis agent
- **explore**: Fast codebase exploration specialist

Custom agents defined in config files are merged with these built-in agents.

## JSONC Support

The config system supports JSONC (JSON with Comments):

```jsonc
{
  // This is a single-line comment
  "agents": {
    /* This is a
       multi-line comment */
    "docs": {
      "model_id": "claude-sonnet-4-20250514"
    }
  }
}
```

Comments are automatically stripped during parsing.

## Example Configuration

See `opencode.jsonc` in the project root for a complete example configuration with all available options.

## Cache Management

The config system uses `functools.lru_cache` to cache loaded configurations. To reload the config:

```python
from config import get_config

# Clear cache to reload config
get_config.cache_clear()
config = get_config()
```

## Error Handling

The config system is designed to fail gracefully:

- Missing config files use default values
- Invalid JSON/JSONC shows warnings but doesn't crash
- Unknown fields are ignored (forward compatibility)
- Custom agents that fail to load are skipped with warnings
