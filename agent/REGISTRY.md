# Agent Registry System

The Agent Registry system provides a flexible way to configure multiple agents with different capabilities, permissions, and behaviors. This is similar to OpenCode's agent system, allowing you to choose the right agent for the task at hand.

## Overview

The registry system defines four built-in agents with different tool access and behaviors:

1. **build** - Default agent with all tools enabled for general development
2. **general** - Multi-step parallel task execution specialist (subagent mode)
3. **plan** - Read-only planning agent with restricted shell commands
4. **explore** - Fast codebase exploration specialist

## Architecture

### Components

- **`registry.py`** - Core registry system with agent configurations
- **`agent.py`** - Updated to use registry for agent creation
- **`__init__.py`** - Exports registry components

### Key Classes

#### `AgentConfig`

A dataclass that defines an agent's configuration:

```python
@dataclass
class AgentConfig:
    name: str
    description: str
    mode: AgentMode  # PRIMARY or SUBAGENT
    system_prompt: str
    temperature: float = 0.7
    top_p: float = 0.9
    tools_enabled: dict[str, bool] = field(default_factory=dict)
    allowed_shell_patterns: list[str] | None = None
```

#### `AgentMode`

An enum defining the agent's operation mode:

```python
class AgentMode(str, Enum):
    PRIMARY = "primary"      # Full-featured agent
    SUBAGENT = "subagent"    # Used for parallel execution
```

#### `AgentRegistry`

Manages agent configurations with methods to register, retrieve, and list agents.

## Built-in Agents

### 1. Build Agent (default)

**Purpose:** Full-featured agent for general development tasks.

**Configuration:**
- All tools enabled: `python`, `shell`, `read`, `write`, `search`, `ls`, `fetch`, `web`
- No shell command restrictions
- Temperature: 0.7
- Mode: PRIMARY

**Use cases:**
- Full development workflow
- Implementing new features
- Running tests and builds
- General coding assistance

**Example:**
```python
from agent import create_agent

agent = create_agent(agent_name="build")
# or simply (build is default):
agent = create_agent()
```

### 2. General Agent

**Purpose:** Optimized for multi-step parallel task execution.

**Configuration:**
- All tools enabled: `python`, `shell`, `read`, `write`, `search`, `ls`, `fetch`, `web`
- No shell command restrictions
- Temperature: 0.7
- Mode: SUBAGENT

**Use cases:**
- Parallel task execution
- Multi-step operations
- Concurrent file processing
- Subagent coordination

**Example:**
```python
agent = create_agent(agent_name="general")
```

### 3. Plan Agent

**Purpose:** Read-only planning and analysis with restricted shell access.

**Configuration:**
- Tools enabled: `shell` (restricted), `read`, `search`, `ls`, `fetch`, `web`
- Tools disabled: `python`, `write`
- Temperature: 0.6 (more focused)
- Mode: PRIMARY

**Shell restrictions:** Only safe, read-only commands allowed:
- `ls`, `grep`, `find`, `cat`, `head`, `tail`, `wc`
- `git status`, `git log`, `git diff`, `git show`, `git branch`
- `file`, `stat`, `du`, `df`, `pwd`, `echo`, `which`, `tree`

**Use cases:**
- Code review and analysis
- Architecture planning
- Read-only exploration
- Strategy development

**Example:**
```python
agent = create_agent(agent_name="plan")

# The agent will block dangerous commands:
# shell("rm -rf /") -> Error message
# shell("git status") -> Success
```

### 4. Explore Agent

**Purpose:** Fast codebase exploration and navigation.

**Configuration:**
- Tools enabled: `shell` (restricted), `read`, `search`, `ls`
- Tools disabled: `python`, `write`, `fetch`, `web`
- Temperature: 0.5 (very focused)
- Mode: PRIMARY

**Shell restrictions:** Search and git tools only:
- `ls`, `grep`, `find`, `tree`
- `git` (all subcommands)
- `rg` (ripgrep), `ag` (silver searcher), `ack`, `fd`

**Use cases:**
- Fast codebase navigation
- Pattern discovery
- Quick code searches
- Understanding project structure

**Example:**
```python
agent = create_agent(agent_name="explore")
```

## Usage

### Basic Usage

```python
from agent import create_agent, list_agent_names, get_agent_config

# List available agents
print(list_agent_names())
# ['build', 'general', 'plan', 'explore']

# Create an agent
agent = create_agent(agent_name="plan")

# Get configuration
config = get_agent_config("plan")
print(config.description)
print(config.tools_enabled)
```

### Checking Agent Capabilities

```python
from agent import get_agent_config

config = get_agent_config("plan")

# Check if a tool is enabled
if config.is_tool_enabled("write"):
    print("Agent can write files")
else:
    print("Agent is read-only")

# Check if a shell command is allowed
if config.is_shell_command_allowed("rm -rf /"):
    print("Command allowed")
else:
    print("Command blocked")
```

### Custom Agents

You can register custom agents programmatically:

```python
from agent import register_agent, AgentConfig, AgentMode

# Create custom agent configuration
custom_config = AgentConfig(
    name="custom",
    description="My custom agent",
    mode=AgentMode.PRIMARY,
    system_prompt="Custom system prompt...",
    temperature=0.8,
    tools_enabled={
        "read": True,
        "write": True,
        "python": False,
        "shell": False,
    }
)

# Register it
register_agent(custom_config)

# Use it
agent = create_agent(agent_name="custom")
```

### Configuration File Integration

The registry system integrates with the project's configuration system. You can define custom agents in `opencode.jsonc`:

```jsonc
{
  "agents": {
    "docs": {
      "model_id": "claude-sonnet-4-20250514",
      "system_prompt": "You are a documentation specialist...",
      "tools": ["read", "write", "search", "ls"],
      "temperature": 0.6
    }
  }
}
```

The registry will automatically load these custom agents on initialization.

## API Reference

### Functions

#### `create_agent(model_id: str, api_key: str | None, agent_name: str) -> Agent`

Create an agent with a specific configuration.

**Parameters:**
- `model_id`: Anthropic model identifier (default: "claude-sonnet-4-20250514")
- `api_key`: Optional API key (default: ANTHROPIC_API_KEY env var)
- `agent_name`: Name of agent configuration (default: "build")

**Returns:** Configured Pydantic AI Agent

**Raises:** `ValueError` if agent_name doesn't exist

#### `list_agent_names() -> list[str]`

Get a list of all available agent names.

#### `list_agents() -> list[AgentConfig]`

Get all agent configurations.

#### `get_agent_config(name: str) -> AgentConfig | None`

Get a specific agent configuration by name.

#### `register_agent(config: AgentConfig) -> None`

Register a custom agent configuration.

#### `agent_exists(name: str) -> bool`

Check if an agent with the given name exists.

## Shell Command Validation

The registry system includes pattern-based shell command validation for restricted agents. This is configured via the `allowed_shell_patterns` field in `AgentConfig`.

### How it works

1. Each pattern is a regex that matches allowed commands
2. Commands are matched from the start (`^` anchor implied)
3. If `allowed_shell_patterns` is `None`, all commands are allowed
4. If `allowed_shell_patterns` is a list, only matching commands are allowed

### Example

```python
config = AgentConfig(
    name="restricted",
    # ...
    allowed_shell_patterns=[
        r"^ls\s+.*",      # Allow: ls -la, ls /path
        r"^ls$",          # Allow: ls (no args)
        r"^git\s+status", # Allow: git status
    ]
)

# Validation
config.is_shell_command_allowed("ls -la")      # True
config.is_shell_command_allowed("git status")  # True
config.is_shell_command_allowed("rm -rf /")    # False
```

### Security Note

Shell command validation provides a basic safety layer but is NOT a complete security solution. Always run agents in isolated environments when executing untrusted commands.

## Design Patterns

### Choosing the Right Agent

- Use **build** for: General development, full tool access needed
- Use **general** for: Parallel operations, subagent coordination
- Use **plan** for: Analysis without modification, code review
- Use **explore** for: Quick navigation, finding code patterns

### Agent Specialization

Agents can be specialized by:

1. **Tool access**: Enable only necessary tools
2. **Shell restrictions**: Limit commands to safe patterns
3. **Temperature**: Lower for focused tasks, higher for creative tasks
4. **System prompt**: Guide behavior and capabilities
5. **Mode**: PRIMARY for standalone, SUBAGENT for coordination

## Examples

See `examples/agent_registry_demo.py` for a complete demonstration of the registry system.

## Testing

```bash
# Run the demo
python examples/agent_registry_demo.py

# Test in Python
python -c "from agent import list_agent_names; print(list_agent_names())"
```

## Future Enhancements

Potential improvements to the registry system:

1. Agent inheritance and composition
2. Runtime permission checking
3. Tool usage monitoring and logging
4. Agent performance metrics
5. Dynamic agent creation from natural language descriptions
6. Agent capability negotiation
7. Integration with MCP (Model Context Protocol) servers

## Related Files

- `/Users/williamcory/agent/agent/registry.py` - Registry implementation
- `/Users/williamcory/agent/agent/agent.py` - Agent creation with registry
- `/Users/williamcory/agent/agent/__init__.py` - Public API exports
- `/Users/williamcory/agent/examples/agent_registry_demo.py` - Demo script
- `/Users/williamcory/agent/config/config.py` - Configuration system integration
