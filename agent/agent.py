"""
Pydantic AI Agent configuration using MCP servers for tools.

Uses external MCP servers for shell and filesystem operations,
minimizing custom tool code that needs to be maintained.
"""

import os
import sys
from contextlib import asynccontextmanager
from typing import AsyncIterator

from pydantic_ai import Agent, WebSearchTool
from pydantic_ai.mcp import MCPServerStdio
from pydantic_ai.models.anthropic import AnthropicModelSettings

# Lazy import - duckduckgo is optional
_duckduckgo_search_tool = None

def _get_duckduckgo_tool():
    global _duckduckgo_search_tool
    if _duckduckgo_search_tool is None:
        try:
            from pydantic_ai.common_tools.duckduckgo import duckduckgo_search_tool
            _duckduckgo_search_tool = duckduckgo_search_tool
        except ImportError:
            _duckduckgo_search_tool = False  # Mark as unavailable
    return _duckduckgo_search_tool if _duckduckgo_search_tool else None

from config import DEFAULT_MODEL, load_system_prompt_markdown
from .registry import get_agent_config

# Constants
SHELL_SERVER_TIMEOUT_SECONDS = 60
FILESYSTEM_SERVER_TIMEOUT_SECONDS = 30
THINKING_BUDGET_TOKENS = 10000  # Extended thinking budget for better reasoning


def get_anthropic_model_settings(enable_thinking: bool = True) -> AnthropicModelSettings:
    """Get Anthropic model settings with optional extended thinking.

    Args:
        enable_thinking: Whether to enable extended thinking (default True)

    Returns:
        AnthropicModelSettings configured for the agent
    """
    settings: AnthropicModelSettings = {}

    if enable_thinking:
        settings['anthropic_thinking'] = {
            'type': 'enabled',
            'budget_tokens': THINKING_BUDGET_TOKENS,
        }

    return settings


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


def _validate_todos(todos: list[dict]) -> list[dict]:
    """Validate and normalize todo items."""
    validated = []
    for todo in todos:
        validated.append({
            "content": todo.get("content", ""),
            "status": todo.get("status", "pending"),
            "activeForm": todo.get("activeForm", todo.get("content", "")),
        })
    return validated


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


def _build_system_prompt(
    agent_config_prompt: str | None,
    working_dir: str | None,
) -> str:
    """
    Build the complete system prompt with optional markdown prepending.

    Searches for CLAUDE.md or Agents.md in the working directory and parent
    directories. If found, prepends the content to the base system prompt.

    Args:
        agent_config_prompt: Agent-specific system prompt (or None for default)
        working_dir: Working directory for markdown file search

    Returns:
        Complete system prompt string
    """
    cwd = working_dir or os.getcwd()
    markdown_content = load_system_prompt_markdown(cwd)
    base_prompt = agent_config_prompt or SYSTEM_INSTRUCTIONS

    if markdown_content:
        return f"{markdown_content}\n\n{base_prompt}"
    return base_prompt


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
    # Check for bundled MCP shell server (from PyInstaller embedded build)
    mcp_shell_path = os.environ.get('MCP_SHELL_SERVER_PATH')
    if mcp_shell_path and os.path.exists(mcp_shell_path):
        # Use bundled executable
        shell_server = MCPServerStdio(
            mcp_shell_path,
            args=[],
            timeout=SHELL_SERVER_TIMEOUT_SECONDS,
        )
    else:
        # Use current Python interpreter
        shell_server = MCPServerStdio(
            sys.executable,
            args=['-m', 'mcp_server_shell'],
            timeout=SHELL_SERVER_TIMEOUT_SECONDS,
        )
    servers.append(shell_server)

    # Filesystem server (Node.js-based, more mature)
    # Provides: read_file, write_file, list_directory, search_files, etc.
    filesystem_server = MCPServerStdio(
        'npx',
        args=['-y', '@modelcontextprotocol/server-filesystem', cwd],
        timeout=FILESYSTEM_SERVER_TIMEOUT_SECONDS,
    )
    servers.append(filesystem_server)

    return servers


@asynccontextmanager
async def create_agent_with_mcp(
    model_id: str = DEFAULT_MODEL,
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
    ddg_tool = _get_duckduckgo_tool()
    tools = [] if use_anthropic else ([ddg_tool()] if ddg_tool else [])

    # Build system prompt with optional markdown content
    system_prompt = _build_system_prompt(agent_config.system_prompt, working_dir)

    # Create agent with MCP toolsets
    model_name = f"anthropic:{model_id}"
    agent_kwargs = {
        "system_prompt": system_prompt,
        "toolsets": mcp_servers,
    }
    if builtin_tools:
        agent_kwargs["builtin_tools"] = builtin_tools
    if tools:
        agent_kwargs["tools"] = tools

    agent = Agent(model_name, **agent_kwargs)

    # Register simple custom tools that don't need MCP
    @agent.tool_plain
    async def todowrite(todos: list[dict], session_id: str = "default") -> str:
        """Write/replace the todo list for task tracking.

        Args:
            todos: List of todo items with 'content', 'status', and 'activeForm' fields
            session_id: Session identifier for todo storage
        """
        validated = _validate_todos(todos)
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
    model_id: str = DEFAULT_MODEL,
    api_key: str | None = None,
    agent_name: str = "build",
    working_dir: str | None = None,
) -> Agent:
    """
    Create a simple agent WITHOUT MCP tools (for backwards compatibility).

    Note: This creates an agent without MCP tools. For full functionality,
    use create_agent_with_mcp() as an async context manager instead.

    Args:
        model_id: Anthropic model identifier
        api_key: Optional API key (defaults to ANTHROPIC_API_KEY env var)
        agent_name: Name of the agent configuration to use
        working_dir: Working directory for markdown file search

    Returns:
        Configured Pydantic AI Agent (without MCP tools)
    """
    agent_config = get_agent_config(agent_name)
    if agent_config is None:
        raise ValueError(f"Unknown agent: {agent_name}")

    # Determine search tool based on model
    use_anthropic = _is_anthropic_model(model_id)
    builtin_tools = [WebSearchTool()] if use_anthropic else []
    ddg_tool = _get_duckduckgo_tool()
    tools = [] if use_anthropic else ([ddg_tool()] if ddg_tool else [])

    # Build system prompt with optional markdown content
    system_prompt = _build_system_prompt(agent_config.system_prompt, working_dir)

    model_name = f"anthropic:{model_id}"
    agent = Agent(
        model_name,
        system_prompt=system_prompt,
        builtin_tools=builtin_tools if builtin_tools else None,
        tools=tools if tools else None,
    )

    # Register simple todo tools
    @agent.tool_plain
    async def todowrite(todos: list[dict], session_id: str = "default") -> str:
        """Write/replace the todo list for task tracking.

        Args:
            todos: List of todo items with 'content', 'status', and 'activeForm' fields
            session_id: Session identifier for todo storage
        """
        validated = _validate_todos(todos)
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

    return agent
