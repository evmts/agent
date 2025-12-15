"""
Pydantic AI Agent configuration using MCP servers for tools.

Uses external MCP servers for shell and filesystem operations,
minimizing custom tool code that needs to be maintained.
"""

import os
from contextlib import asynccontextmanager
from typing import AsyncIterator

from pydantic_ai import Agent, WebSearchTool
from pydantic_ai.mcp import MCPServerStdio
from pydantic_ai.common_tools.duckduckgo import duckduckgo_search_tool

from .registry import get_agent_config


def _is_anthropic_model(model_id: str) -> bool:
    """Check if the model is an Anthropic/Claude model."""
    model_lower = model_id.lower()
    return "claude" in model_lower or "anthropic" in model_lower


# Simple in-memory todo storage (session-specific, doesn't need MCP)
_todo_storage: dict[str, list[dict]] = {}


def _get_todos(session_id: str) -> list[dict]:
    return _todo_storage.get(session_id, [])


def _set_todos(session_id: str, todos: list[dict]) -> None:
    _todo_storage[session_id] = todos


SYSTEM_INSTRUCTIONS = """You are a helpful coding assistant with access to tools for:
- Executing shell commands (via shell tool)
- Reading and writing files (via filesystem tools)
- Managing todo lists for task tracking
- Searching the web for up-to-date information

When helping users, prefer to:
1. Read relevant files first to understand context
2. Make targeted changes rather than rewriting entire files
3. Explain what you're doing and why
4. Verify changes work correctly

Be concise but thorough. If you need to execute code to verify something works, do so.
"""


def create_mcp_servers(working_dir: str | None = None) -> list[MCPServerStdio]:
    """
    Create MCP server instances for tools.

    Args:
        working_dir: Working directory for filesystem operations

    Returns:
        List of MCP server configurations
    """
    cwd = working_dir or os.getcwd()

    servers = []

    # Shell server (Python-based)
    # Provides: shell command execution
    shell_server = MCPServerStdio(
        'python',
        args=['-m', 'mcp_server_shell'],
        timeout=60,
    )
    servers.append(shell_server)

    # Filesystem server (Node.js-based, more mature)
    # Provides: read_file, write_file, list_directory, search_files, etc.
    filesystem_server = MCPServerStdio(
        'npx',
        args=['-y', '@modelcontextprotocol/server-filesystem', cwd],
        timeout=30,
    )
    servers.append(filesystem_server)

    return servers


@asynccontextmanager
async def create_agent_with_mcp(
    model_id: str = "claude-sonnet-4-20250514",
    agent_name: str = "build",
    working_dir: str | None = None,
) -> AsyncIterator[Agent]:
    """
    Create and configure a Pydantic AI agent with MCP tools.

    This is an async context manager that properly manages MCP server lifecycles.

    Args:
        model_id: Anthropic model identifier
        agent_name: Name of the agent configuration to use
        working_dir: Working directory for filesystem operations

    Yields:
        Configured Pydantic AI Agent with MCP tools

    Example:
        async with create_agent_with_mcp() as agent:
            result = await agent.run("List files in current directory")
    """
    agent_config = get_agent_config(agent_name)
    if agent_config is None:
        raise ValueError(f"Unknown agent: {agent_name}")

    # Create MCP servers
    mcp_servers = create_mcp_servers(working_dir)

    # Determine search tool based on model
    use_anthropic = _is_anthropic_model(model_id)
    builtin_tools = [WebSearchTool()] if use_anthropic else []
    tools = [] if use_anthropic else [duckduckgo_search_tool()]

    # Create agent with MCP toolsets
    model_name = f"anthropic:{model_id}"
    agent = Agent(
        model_name,
        system_prompt=agent_config.system_prompt or SYSTEM_INSTRUCTIONS,
        toolsets=mcp_servers,
        builtin_tools=builtin_tools if builtin_tools else None,
        tools=tools if tools else None,
    )

    # Register simple custom tools that don't need MCP
    @agent.tool_plain
    async def todowrite(todos: list[dict], session_id: str = "default") -> str:
        """Write/replace the todo list for task tracking.

        Args:
            todos: List of todo items with 'content', 'status', and 'activeForm' fields
            session_id: Session identifier for todo storage
        """
        validated = []
        for todo in todos:
            validated.append({
                "content": todo.get("content", ""),
                "status": todo.get("status", "pending"),
                "activeForm": todo.get("activeForm", todo.get("content", "")),
            })
        _set_todos(session_id, validated)
        return f"Todo list updated with {len(validated)} items"

    @agent.tool_plain
    async def todoread(session_id: str = "default") -> str:
        """Read the current todo list.

        Args:
            session_id: Session identifier for todo storage
        """
        todos = _get_todos(session_id)
        if not todos:
            return "No todos found"

        lines = []
        for i, todo in enumerate(todos, 1):
            status_icon = {
                "pending": "⏳",
                "in_progress": "🔄",
                "completed": "✅",
            }.get(todo.get("status", "pending"), "⏳")
            lines.append(f"{i}. {status_icon} {todo.get('content', '')}")

        return "\n".join(lines)

    # Use async context manager to properly manage MCP server lifecycles
    async with agent:
        yield agent


def create_agent(
    model_id: str = "claude-sonnet-4-20250514",
    api_key: str | None = None,
    agent_name: str = "build",
) -> Agent:
    """
    Create a simple agent WITHOUT MCP tools (for backwards compatibility).

    Note: This creates an agent without MCP tools. For full functionality,
    use create_agent_with_mcp() as an async context manager instead.

    Args:
        model_id: Anthropic model identifier
        api_key: Optional API key (defaults to ANTHROPIC_API_KEY env var)
        agent_name: Name of the agent configuration to use

    Returns:
        Configured Pydantic AI Agent (without MCP tools)
    """
    agent_config = get_agent_config(agent_name)
    if agent_config is None:
        raise ValueError(f"Unknown agent: {agent_name}")

    # Determine search tool based on model
    use_anthropic = _is_anthropic_model(model_id)
    builtin_tools = [WebSearchTool()] if use_anthropic else []
    tools = [] if use_anthropic else [duckduckgo_search_tool()]

    model_name = f"anthropic:{model_id}"
    agent = Agent(
        model_name,
        system_prompt=agent_config.system_prompt or SYSTEM_INSTRUCTIONS,
        builtin_tools=builtin_tools if builtin_tools else None,
        tools=tools if tools else None,
    )

    # Register simple todo tools
    @agent.tool_plain
    async def todowrite(todos: list[dict], session_id: str = "default") -> str:
        """Write/replace the todo list."""
        _set_todos(session_id, todos)
        return f"Todo list updated with {len(todos)} items"

    @agent.tool_plain
    async def todoread(session_id: str = "default") -> str:
        """Read the current todo list."""
        todos = _get_todos(session_id)
        if not todos:
            return "No todos found"
        return "\n".join(f"- {t.get('content', '')}" for t in todos)

    return agent
