# Agent Registry System - Implementation Summary

## Overview

Successfully implemented a multiple agents system for the `/Users/williamcory/agent` project, similar to OpenCode's agent architecture. The system provides four specialized agents with different capabilities, permissions, and behaviors.

## Changes Made

### 1. New File: `/Users/williamcory/agent/agent/registry.py`

Created the core registry system with:

- **`AgentMode` enum**: Defines PRIMARY and SUBAGENT operation modes
- **`AgentConfig` dataclass**: Agent configuration model with:
  - Basic properties: name, description, mode, system_prompt
  - Model settings: temperature, top_p
  - Tool permissions: tools_enabled dict
  - Shell restrictions: allowed_shell_patterns list
- **`AgentRegistry` class**: Registry for managing agent configurations
  - Loads built-in agents
  - Integrates with config system for custom agents
  - Provides registration, retrieval, and listing methods
- **Built-in agents**: build, general, plan, explore
- **Public API**: Helper functions for common operations

**Key Features:**
- Pattern-based shell command validation for restricted agents
- Integration with existing config system (`opencode.jsonc`)
- Support for custom agent registration
- Validation methods for tool and command permissions

### 2. Updated: `/Users/williamcory/agent/agent/agent.py`

Modified the agent creation system to:

- Import registry components (`get_agent_config`, `AgentConfig`)
- Add `agent_name` parameter to `create_agent()` function (default: "build")
- Apply agent-specific configurations:
  - Use agent's system_prompt instead of hardcoded one
  - Conditionally register tools based on `tools_enabled`
  - Validate shell commands against `allowed_shell_patterns`
  - Return error messages for blocked commands
- Raise `ValueError` for unknown agent names

**Tool Registration Logic:**
```python
# Tools are only registered if enabled in agent config
if is_enabled("python"):
    @agent.tool_plain
    async def python(...): ...

if is_enabled("shell"):
    @agent.tool_plain
    async def shell(command, ...):
        # Validate command against allowed patterns
        if not agent_config.is_shell_command_allowed(command):
            return error_message
        ...
```

### 3. Updated: `/Users/williamcory/agent/agent/__init__.py`

Extended exports to include registry components:

```python
__all__ = [
    "create_agent",
    "AgentWrapper",
    "StreamEvent",
    # New exports:
    "AgentConfig",
    "AgentMode",
    "get_agent_config",
    "list_agents",
    "list_agent_names",
    "register_agent",
    "agent_exists",
]
```

### 4. New File: `/Users/williamcory/agent/examples/agent_registry_demo.py`

Created a comprehensive demo script showcasing:
- Listing available agents
- Viewing detailed agent configurations
- Shell command validation examples
- Agent creation with different configs
- Use case recommendations

### 5. New File: `/Users/williamcory/agent/agent/REGISTRY.md`

Created complete documentation including:
- System architecture and components
- Detailed agent descriptions and use cases
- Usage examples and API reference
- Shell command validation explanation
- Design patterns and best practices
- Future enhancement suggestions

## Built-in Agents

### 1. Build Agent (Default)
- **Purpose**: Full-featured development agent
- **Tools**: All enabled (python, shell, read, write, search, ls, fetch, web)
- **Shell**: No restrictions
- **Temperature**: 0.7
- **Mode**: PRIMARY
- **Use cases**: General development, implementing features, running tests

### 2. General Agent
- **Purpose**: Parallel task execution specialist
- **Tools**: All enabled
- **Shell**: No restrictions
- **Temperature**: 0.7
- **Mode**: SUBAGENT
- **Use cases**: Multi-step operations, concurrent processing, subagent coordination

### 3. Plan Agent
- **Purpose**: Read-only planning and analysis
- **Tools**: shell (restricted), read, search, ls, fetch, web
- **Disabled**: python, write
- **Shell**: 21 safe patterns (ls, grep, git status/log/diff, etc.)
- **Temperature**: 0.6
- **Mode**: PRIMARY
- **Use cases**: Code review, architecture planning, strategy development

### 4. Explore Agent
- **Purpose**: Fast codebase exploration
- **Tools**: shell (restricted), read, search, ls
- **Disabled**: python, write, fetch, web
- **Shell**: 10 patterns (ls, grep, find, git, rg, ag, fd, etc.)
- **Temperature**: 0.5
- **Mode**: PRIMARY
- **Use cases**: Code navigation, pattern discovery, project structure analysis

## Technical Implementation

### Shell Command Validation

Implemented pattern-based validation using regex:

```python
def is_shell_command_allowed(self, command: str) -> bool:
    """Check if a shell command is allowed for this agent."""
    if self.allowed_shell_patterns is None:
        return True

    import re
    for pattern in self.allowed_shell_patterns:
        if re.match(pattern, command.strip()):
            return True
    return False
```

### Config Integration

The registry automatically loads custom agents from `opencode.jsonc`:

```jsonc
{
  "agents": {
    "custom_agent": {
      "model_id": "claude-sonnet-4-20250514",
      "system_prompt": "Custom prompt...",
      "tools": ["read", "write", "search"],
      "temperature": 0.6
    }
  }
}
```

### Agent Selection

Agents are selected by name when creating:

```python
# Use default build agent
agent = create_agent()

# Use specific agent
agent = create_agent(agent_name="plan")
agent = create_agent(agent_name="explore")
```

## Usage Examples

### Basic Usage

```python
from agent import create_agent, list_agent_names

# List available agents
print(list_agent_names())
# Output: ['build', 'general', 'plan', 'explore', 'docs', 'test']

# Create plan agent (read-only)
agent = create_agent(agent_name="plan")

# Create explore agent (fast search)
agent = create_agent(agent_name="explore")
```

### Checking Capabilities

```python
from agent import get_agent_config

config = get_agent_config("plan")

# Check tool access
config.is_tool_enabled("write")  # False (read-only)
config.is_tool_enabled("read")   # True

# Check shell command
config.is_shell_command_allowed("git status")  # True
config.is_shell_command_allowed("rm -rf /")    # False
```

### Custom Agents

```python
from agent import register_agent, AgentConfig, AgentMode

custom = AgentConfig(
    name="custom",
    description="My specialized agent",
    mode=AgentMode.PRIMARY,
    system_prompt="You are a specialist in...",
    tools_enabled={"read": True, "search": True},
    allowed_shell_patterns=[r"^ls.*", r"^git\s+log.*"]
)

register_agent(custom)
agent = create_agent(agent_name="custom")
```

## Testing

### Verification

All components tested successfully:

```bash
# Test imports and registry
python -c "from agent import list_agent_names; print(list_agent_names())"
# Output: ['build', 'general', 'plan', 'explore', 'docs', 'test']

# Test configuration
python -c "from agent import get_agent_config; \
  config = get_agent_config('plan'); \
  print('Plan agent tools:', [k for k,v in config.tools_enabled.items() if v])"

# Run demo
python examples/agent_registry_demo.py
```

### Demo Output

The demo script successfully demonstrated:
- ✓ Listing all 6 agents (4 built-in + 2 custom)
- ✓ Showing detailed configurations
- ✓ Shell command validation (allowed/blocked)
- ✓ Creating agents with different configs
- ✓ Use case recommendations

## File Structure

```
/Users/williamcory/agent/
├── agent/
│   ├── __init__.py              # Updated with registry exports
│   ├── agent.py                 # Updated to use registry
│   ├── registry.py              # NEW: Core registry implementation
│   ├── REGISTRY.md              # NEW: Complete documentation
│   └── tools/
│       ├── code_execution.py
│       ├── file_operations.py
│       └── ...
├── examples/
│   └── agent_registry_demo.py   # NEW: Demo script
├── config/
│   └── config.py                # Existing config system
└── AGENT_REGISTRY_SUMMARY.md    # This file
```

## Dependencies

No new dependencies required. The implementation uses:
- Python 3.12 type hints (with `from __future__ import annotations`)
- Standard library: `dataclasses`, `enum`, `pathlib`, `re`
- Existing dependencies: `pydantic_ai`, config system

## Design Patterns

### Agent Specialization

Agents are specialized through:
1. **Tool access control**: Enable only necessary tools
2. **Shell command restrictions**: Pattern-based allowlists
3. **Temperature tuning**: Lower for focused, higher for creative
4. **System prompts**: Tailored to agent purpose
5. **Mode selection**: PRIMARY vs SUBAGENT

### Security Model

- Blocklist approach for dangerous commands (in code_execution.py)
- Allowlist approach for restricted agents (in registry.py)
- Multiple validation layers
- Clear error messages when commands are blocked

### Extensibility

The system is designed for extensibility:
- Custom agents via config files
- Programmatic agent registration
- Agent inheritance (future enhancement)
- Integration with external systems

## Benefits

1. **Flexibility**: Choose the right agent for each task
2. **Safety**: Restricted agents prevent accidental modifications
3. **Performance**: Specialized agents are more focused
4. **Clarity**: Clear separation of capabilities
5. **Extensibility**: Easy to add custom agents
6. **Integration**: Works with existing config system

## Future Enhancements

Potential improvements identified:

1. **Agent inheritance**: Base agents with override capabilities
2. **Runtime monitoring**: Track tool usage and performance
3. **Dynamic agents**: Create agents from natural language
4. **Capability negotiation**: Agents request permissions as needed
5. **MCP integration**: Connect to external tool providers
6. **Agent collaboration**: Multiple agents working together
7. **Permission escalation**: Request elevated access when needed

## Migration Guide

### For existing code

No breaking changes. The default behavior remains unchanged:

```python
# Old code (still works)
agent = create_agent()

# New code (explicit agent selection)
agent = create_agent(agent_name="build")  # Same as default
agent = create_agent(agent_name="plan")   # New option
```

### For new projects

Recommended approach:

1. Start with `build` agent for general development
2. Use `plan` agent for read-only analysis
3. Use `explore` agent for quick navigation
4. Use `general` agent for parallel operations
5. Create custom agents for specialized workflows

## Conclusion

Successfully implemented a comprehensive multiple agents registry system that:

✅ Provides 4 specialized built-in agents
✅ Integrates with existing config system
✅ Includes pattern-based shell command validation
✅ Supports custom agent registration
✅ Maintains backward compatibility
✅ Includes comprehensive documentation
✅ Includes working demo script
✅ All tests passing

The implementation follows the OpenCode architecture while being tailored to this project's specific needs and existing patterns.
