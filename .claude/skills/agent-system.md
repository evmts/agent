# Agent System

This skill covers agent creation, the agent registry system, MCP server integration, and agent configuration for the Claude Agent platform.

## Overview

The Claude Agent platform uses Pydantic AI to create agents that integrate with MCP (Model Context Protocol) servers for shell and filesystem operations. The agent registry provides pre-configured agents with different tool permissions and behaviors.

## Key Files

| File | Purpose |
|------|---------|
| `agent/agent.py` | Agent creation with MCP integration |
| `agent/registry.py` | Agent configurations and permissions |
| `agent/wrapper.py` | Streaming adapter for server |
| `agent/__init__.py` | Module exports |

## Constants

```python
# agent/agent.py
SHELL_SERVER_TIMEOUT_SECONDS = 60
FILESYSTEM_SERVER_TIMEOUT_SECONDS = 30
THINKING_BUDGET_TOKENS = 60000  # Extended thinking budget
MAX_OUTPUT_TOKENS = 64000       # Must be > thinking budget
```

## Agent Creation

### With MCP (Recommended)

The primary way to create agents uses MCP servers for tool operations:

```python
from agent import create_mcp_wrapper, create_agent_with_mcp

# As async context manager
async with create_agent_with_mcp(
    model_id="claude-opus-4-5-20251101",
    agent_name="build",
    working_dir="/path/to/project"
) as agent:
    result = await agent.run("List files in current directory")
```

### Without MCP (Simple)

For testing or simple use cases:

```python
from agent import create_agent

agent = create_agent(
    model_id="claude-opus-4-5-20251101",
    agent_name="build"
)
# Note: No MCP tools available
```

### MCP Wrapper (Server Integration)

For the server, use the wrapper which handles streaming:

```python
from agent import create_mcp_wrapper

async with create_mcp_wrapper(
    model_id="claude-opus-4-5-20251101",
    working_dir="/path/to/project"
) as wrapper:
    # Use wrapper for streaming
```

## MCP Server Configuration

The platform uses two MCP servers:

### Shell Server

Python-based shell execution:

```python
# Uses current Python interpreter
shell_server = MCPServerStdio(
    sys.executable,
    args=['-m', 'mcp_server_shell'],
    timeout=60,  # SHELL_SERVER_TIMEOUT_SECONDS
)
```

### Filesystem Server

Node.js-based file operations:

```python
filesystem_server = MCPServerStdio(
    'npx',
    args=['-y', '@modelcontextprotocol/server-filesystem', working_dir],
    timeout=30,  # FILESYSTEM_SERVER_TIMEOUT_SECONDS
)
```

## Agent Registry

### Built-in Agents

The registry provides 4 pre-configured agents:

| Agent | Mode | Description |
|-------|------|-------------|
| `build` | PRIMARY | Full-featured for general development |
| `general` | SUBAGENT | Optimized for parallel task execution |
| `plan` | PRIMARY | Read-only for analysis and planning |
| `explore` | PRIMARY | Fast codebase exploration |

### Agent Configuration

```python
from dataclasses import dataclass, field
from enum import Enum

class AgentMode(str, Enum):
    PRIMARY = "primary"    # Full-featured agent
    SUBAGENT = "subagent"  # For parallel execution

@dataclass
class AgentConfig:
    name: str
    description: str
    mode: AgentMode
    system_prompt: str
    temperature: float = 0.7
    top_p: float = 0.9
    tools_enabled: dict[str, bool] = field(default_factory=dict)
    allowed_shell_patterns: list[str] | None = None  # None = all allowed
```

### Tool Permissions by Agent

| Tool | build | general | plan | explore |
|------|-------|---------|------|---------|
| python | ✓ | ✓ | ✗ | ✗ |
| shell | ✓ | ✓ | ✓ (limited) | ✓ (limited) |
| read | ✓ | ✓ | ✓ | ✓ |
| write | ✓ | ✓ | ✗ | ✗ |
| search | ✓ | ✓ | ✓ | ✓ |
| ls | ✓ | ✓ | ✓ | ✓ |
| fetch | ✓ | ✓ | ✓ | ✗ |
| web | ✓ | ✓ | ✓ | ✗ |
| lsp | ✓ | ✓ | ✓ | ✓ |

### Shell Command Restrictions

For `plan` and `explore` agents, shell commands are restricted by regex patterns:

```python
# Plan agent allowed patterns
allowed_shell_patterns=[
    r"^ls\s+.*",
    r"^grep\s+.*",
    r"^find\s+.*",
    r"^git\s+status.*",
    r"^git\s+log.*",
    r"^git\s+diff.*",
    r"^cat\s+.*",
    r"^head\s+.*",
    r"^tail\s+.*",
    # ... more read-only commands
]
```

### Checking Permissions

```python
from agent.registry import get_agent_config

config = get_agent_config("plan")

# Check if tool is enabled
if config.is_tool_enabled("write"):
    # Can write files
    pass

# Check if shell command is allowed
if config.is_shell_command_allowed("git status"):
    # Command is permitted
    pass
```

## Registry API

### Getting Agents

```python
from agent.registry import (
    get_agent_config,
    list_agents,
    list_agent_names,
    agent_exists,
)

# Get specific agent
config = get_agent_config("build")

# List all agents
all_agents = list_agents()
names = list_agent_names()

# Check existence
if agent_exists("custom"):
    # Agent available
    pass
```

### Registering Custom Agents

```python
from agent.registry import register_agent, AgentConfig, AgentMode

custom_agent = AgentConfig(
    name="reviewer",
    description="Code review specialist",
    mode=AgentMode.PRIMARY,
    system_prompt="You are a code review expert...",
    temperature=0.5,
    tools_enabled={
        "read": True,
        "search": True,
        "lsp": True,
        "shell": True,
    },
    allowed_shell_patterns=[
        r"^git\s+.*",
        r"^grep\s+.*",
    ],
)

register_agent(custom_agent)
```

### Custom Agents via Config

Agents can be defined in `opencode.jsonc`:

```jsonc
{
  "agents": {
    "reviewer": {
      "model_id": "claude-sonnet-4-20250514",
      "system_prompt": "You are a code reviewer focused on security.",
      "tools": ["read", "search", "lsp"],
      "temperature": 0.5
    }
  }
}
```

## System Prompt Building

The system prompt is built from multiple sources:

1. **CLAUDE.md/Agents.md** - Searched from working directory up to root
2. **Agent-specific prompt** - From agent configuration

```python
def _build_system_prompt(
    agent_config_prompt: str | None,
    working_dir: str | None,
) -> str:
    """Build complete system prompt with markdown prepending."""
    cwd = working_dir or os.getcwd()
    markdown_content = load_system_prompt_markdown(cwd)
    base_prompt = agent_config_prompt or SYSTEM_INSTRUCTIONS

    if markdown_content:
        return f"{markdown_content}\n\n{base_prompt}"
    return base_prompt
```

## Model Settings

### Extended Thinking

For Anthropic models, extended thinking is enabled:

```python
from pydantic_ai.models.anthropic import AnthropicModelSettings

def get_anthropic_model_settings(enable_thinking: bool = True) -> AnthropicModelSettings:
    settings: AnthropicModelSettings = {
        'max_tokens': 64000,  # MAX_OUTPUT_TOKENS
    }

    if enable_thinking:
        settings['anthropic_thinking'] = {
            'type': 'enabled',
            'budget_tokens': 60000,  # THINKING_BUDGET_TOKENS
        }

    return settings
```

### Model Detection

```python
def _is_anthropic_model(model_id: str) -> bool:
    """Check if model is Anthropic/Claude."""
    model_lower = model_id.lower()
    return "claude" in model_lower or "anthropic" in model_lower
```

For non-Anthropic models, DuckDuckGo search is used instead of Anthropic's WebSearchTool.

## Built-in Tools

These tools are registered directly on the agent (not via MCP):

| Tool | Purpose |
|------|---------|
| `todowrite` | Write/replace todo list |
| `todoread` | Read current todo list |
| `hover` | LSP hover information |
| `get_diagnostics` | LSP diagnostics |
| `check_file_errors` | Pre-edit file checking |
| `browser_*` | Browser automation (see [browser-tools.md](./browser-tools.md)) |

## Common Tasks

### Creating a New Agent Type

1. Define configuration in `agent/registry.py`:
   ```python
   BUILTIN_AGENTS["myagent"] = AgentConfig(
       name="myagent",
       description="Purpose of this agent",
       mode=AgentMode.PRIMARY,
       system_prompt="Agent instructions...",
       tools_enabled={...},
   )
   ```

2. Or via config file for user customization

### Changing Model Settings

```python
# In create_agent_with_mcp():
agent = Agent(
    model_name,
    system_prompt=system_prompt,
    toolsets=mcp_servers,
    model_settings=get_anthropic_model_settings(enable_thinking=True),
)
```

### Adding Custom MCP Servers

```python
def create_mcp_servers(working_dir: str | None = None) -> list[MCPServerStdio]:
    servers = []

    # Add custom MCP server
    custom_server = MCPServerStdio(
        'node',
        args=['./my-mcp-server.js'],
        timeout=30,
    )
    servers.append(custom_server)

    return servers
```

## Agent Lifecycle

```
1. create_agent_with_mcp() called
   ├── Load agent config from registry
   ├── Create MCP server instances
   ├── Build system prompt (CLAUDE.md + agent prompt)
   ├── Create Pydantic AI Agent with toolsets
   └── Register custom tools (@agent.tool_plain)

2. async with agent:
   ├── __aenter__: Initialize MCP connections
   ├── Agent available for use
   └── __aexit__: Cleanup MCP connections

3. Cleanup complete
```

## Related Skills

- [tools-development.md](./tools-development.md) - Adding new tools to agents
- [configuration.md](./configuration.md) - Custom agent config via files
- [lsp-integration.md](./lsp-integration.md) - LSP tools used by agents
