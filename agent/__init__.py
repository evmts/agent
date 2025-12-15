"""
Pydantic AI Agent module with MCP support.
Exports the configured agent and initialization functions.
"""
from .agent import create_agent, create_agent_with_mcp
from .registry import (
    AgentConfig,
    AgentMode,
    get_agent_config,
    list_agents,
    list_agent_names,
    register_agent,
    agent_exists,
)
from .wrapper import AgentWrapper, StreamEvent, create_mcp_wrapper, create_simple_wrapper

__all__ = [
    # Agent creation
    "create_agent",
    "create_agent_with_mcp",
    # Wrappers
    "AgentWrapper",
    "StreamEvent",
    "create_mcp_wrapper",
    "create_simple_wrapper",
    # Registry
    "AgentConfig",
    "AgentMode",
    "get_agent_config",
    "list_agents",
    "list_agent_names",
    "register_agent",
    "agent_exists",
]
