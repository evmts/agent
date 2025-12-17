# Configuration System

This skill covers the configuration architecture, environment variables, and config loading for the Claude Agent platform.

## Overview

Claude Agent uses a hierarchical configuration system built on Pydantic models with JSONC (JSON with Comments) support. Configuration can come from environment variables, global settings, and project-level overrides.

## Key Files

| File | Purpose |
|------|---------|
| `config/defaults.py` | Default constants (model ID, LSP config) |
| `config/main_config.py` | Root Config model |
| `config/loader.py` | Config loading, JSONC support, caching |
| `config/agent_config.py` | Custom agent configuration |
| `config/tools_config.py` | Tool enable/disable flags |
| `config/permissions_config.py` | File/bash pattern permissions |
| `config/mcp_server_config.py` | MCP server definitions |
| `config/experimental_config.py` | Feature flags |
| `config/markdown_loader.py` | CLAUDE.md system prompt loading |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Claude API key (required) | - |
| `ANTHROPIC_MODEL` | Model ID to use | `claude-opus-4-5-20251101` |
| `HOST` | Server bind host | `0.0.0.0` |
| `PORT` | Server bind port | `8000` |
| `CORS_ORIGINS` | Allowed CORS origins (comma-separated) | `*` |
| `USE_MCP` | Enable MCP tool servers | `true` |
| `WORKING_DIR` | Working directory for operations | Current directory |
| `BROWSER_API_PORT` | Browser automation port | `48484` |

## Config File Precedence

Configuration is loaded from multiple sources with project config taking precedence:

1. **Global config** (lowest precedence):
   - `~/.opencode/opencode.jsonc`

2. **Project config** (highest precedence, first found wins):
   - `./opencode.jsonc`
   - `./opencode.json`
   - `./.opencode/opencode.jsonc`

## Config Models

### Root Config (`config/main_config.py`)

```python
from pydantic import BaseModel, Field

class Config(BaseModel):
    """Main configuration model."""

    agents: dict[str, AgentConfig] = Field(default_factory=dict)
    tools: ToolsConfig = Field(default_factory=ToolsConfig)
    permissions: PermissionsConfig = Field(default_factory=PermissionsConfig)
    theme: str = Field(default="default")
    keybindings: dict[str, str] = Field(default_factory=dict)
    mcp: dict[str, MCPServerConfig] = Field(default_factory=dict)
    experimental: ExperimentalConfig = Field(default_factory=ExperimentalConfig)
```

### AgentConfig (`config/agent_config.py`)

Define custom agents with specific settings:

```python
class AgentConfig(BaseModel):
    """Custom agent configuration."""

    model_id: str = Field(default=DEFAULT_MODEL)
    system_prompt: str | None = Field(default=None)
    tools: list[str] | None = Field(default=None)
    temperature: float | None = Field(default=None)
```

### ToolsConfig (`config/tools_config.py`)

Enable/disable tool categories:

```python
class ToolsConfig(BaseModel):
    """Tool enable/disable flags."""

    python: bool = True   # Python execution
    shell: bool = True    # Shell execution
    read: bool = True     # File reading
    write: bool = True    # File writing
    search: bool = True   # File searching
    ls: bool = True       # Directory listing
    fetch: bool = True    # Web fetching
    web: bool = True      # Web search
```

### PermissionsConfig (`config/permissions_config.py`)

Control file and command access:

```python
class PermissionsConfig(BaseModel):
    """Default permissions configuration."""

    edit_patterns: list[str] = ["**/*"]  # Glob patterns for editable files
    bash_patterns: list[str] = ["*"]     # Allowed bash patterns
    webfetch_enabled: bool = True
```

### MCPServerConfig (`config/mcp_server_config.py`)

Define MCP servers:

```python
class MCPServerConfig(BaseModel):
    """MCP server configuration."""

    command: str              # Command to start server
    args: list[str] = []      # Command arguments
    env: dict[str, str] = {}  # Environment variables
```

### ExperimentalConfig (`config/experimental_config.py`)

Feature flags for testing:

```python
class ExperimentalConfig(BaseModel):
    """Experimental features."""

    streaming: bool = False       # Streaming responses
    parallel_tools: bool = False  # Parallel tool execution
    caching: bool = False         # Response caching
```

## Config Loading

### Basic Usage

```python
from config import get_config, load_config

# Get cached config (recommended)
config = get_config()

# Force reload from files
from config.loader import get_config
get_config.cache_clear()
config = get_config()

# Load with custom project root
config = load_config(project_root=Path("/path/to/project"))
```

### JSONC Support

The loader automatically strips comments from `.jsonc` files:

```python
from config.loader import strip_jsonc_comments

# Handles both // and /* */ comments
json_str = strip_jsonc_comments(jsonc_content)
```

### Config Merging

Configs are deep-merged with project overriding global:

```python
from config.loader import merge_configs

base = {"tools": {"python": True, "shell": True}}
override = {"tools": {"shell": False}}
result = merge_configs(base, override)
# {"tools": {"python": True, "shell": False}}
```

## Default Constants

Key constants in `config/defaults.py`:

```python
# Model
DEFAULT_MODEL = "claude-opus-4-5-20251101"

# LSP Configuration
LSP_INIT_TIMEOUT_SECONDS = 5.0
LSP_REQUEST_TIMEOUT_SECONDS = 2.0
LSP_MAX_CLIENTS = 10

# LSP server definitions per language
LSP_SERVERS = {
    "python": {
        "extensions": [".py", ".pyi"],
        "command": ["pylsp"],
        "root_markers": ["pyproject.toml", "setup.py", ".git"],
    },
    "typescript": {
        "extensions": [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"],
        "command": ["typescript-language-server", "--stdio"],
        "root_markers": ["package.json", "tsconfig.json", ".git"],
    },
    "go": {
        "extensions": [".go"],
        "command": ["gopls"],
        "root_markers": ["go.mod", "go.work", ".git"],
    },
    "rust": {
        "extensions": [".rs"],
        "command": ["rust-analyzer"],
        "root_markers": ["Cargo.toml", ".git"],
    },
}
```

## CLAUDE.md System Prompt Loading

The system automatically searches for CLAUDE.md to prepend to agent system prompts:

```python
from config.markdown_loader import load_system_prompt_markdown

# Searches working_dir up to filesystem root
# CLAUDE.md takes priority over Agents.md
markdown_content = load_system_prompt_markdown("/path/to/project")
```

Search order per directory:
1. `CLAUDE.md` (priority)
2. `Agents.md` (fallback)

Results are cached per working directory (`lru_cache`).

## Example Config File

`opencode.jsonc`:

```jsonc
{
  // Custom agents
  "agents": {
    "reviewer": {
      "model_id": "claude-sonnet-4-20250514",
      "system_prompt": "You are a code reviewer. Focus on security and best practices.",
      "tools": ["read", "search"]
    }
  },

  // Tool settings
  "tools": {
    "python": true,
    "shell": true,
    "web": false  // Disable web search
  },

  // Permissions
  "permissions": {
    "edit_patterns": ["src/**/*", "tests/**/*"],
    "bash_patterns": ["git *", "npm *", "pytest *"]
  },

  // MCP servers
  "mcp": {
    "custom-server": {
      "command": "node",
      "args": ["./mcp-server.js"],
      "env": {"DEBUG": "true"}
    }
  },

  // Experimental features
  "experimental": {
    "streaming": true
  }
}
```

## Common Tasks

### Adding a New Config Field

1. Create or update the appropriate config model in `config/`
2. Add Pydantic Field with default and description
3. Import and use in `Config` if it's a sub-model
4. Document in this skill

### Accessing Config in Code

```python
from config import get_config

config = get_config()

# Access nested values
if config.tools.python:
    # Python execution enabled
    pass

# Check permissions
allowed_patterns = config.permissions.edit_patterns

# Get custom agent
if "reviewer" in config.agents:
    reviewer_config = config.agents["reviewer"]
```

### Environment Variable Pattern

Follow the style guide for env vars:

```python
import os
from config.defaults import DEFAULT_MODEL

# Good - use constant for default
model = os.environ.get("ANTHROPIC_MODEL", DEFAULT_MODEL)

# Bad - hardcoded default
model = os.environ.get("ANTHROPIC_MODEL", "claude-opus-4-5-20251101")
```

## Related Skills

- [agent-system.md](./agent-system.md) - Uses AgentConfig for custom agents
- [testing.md](./testing.md) - Config testing patterns
