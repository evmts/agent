"""
Pydantic AI Agent configuration with Claude as the LLM provider.
"""

from pathlib import Path

from pydantic_ai import Agent

from config import get_config

from .registry import get_agent_config, AgentConfig
from .tools import (
    edit_file,
    execute_python,
    execute_shell,
    grep_files,
    list_directory,
    read_file,
    search_files,
    web_fetch,
    web_search,
    write_file,
)

SYSTEM_INSTRUCTIONS = """You are a helpful coding assistant with access to tools for:
- Executing Python and shell code
- Reading and writing files
- Editing files with targeted string replacements
- Searching through codebases (file name patterns and content patterns)
- Grep for searching file contents with regex patterns
- Searching the web and fetching pages

When helping users, prefer to:
1. Read relevant files first to understand context
2. Make targeted changes rather than rewriting entire files
3. Explain what you're doing and why
4. Verify changes work correctly

Be concise but thorough. If you need to execute code to verify something works, do so.
"""


def create_agent(
    model_id: str = "claude-sonnet-4-20250514",
    api_key: str | None = None,
    agent_name: str = "build",
) -> Agent:
    """
    Create and configure a Pydantic AI agent with Claude.

    Args:
        model_id: Anthropic model identifier
        api_key: Optional API key (defaults to ANTHROPIC_API_KEY env var)
        agent_name: Name of the agent configuration to use (default: "build")

    Returns:
        Configured Pydantic AI Agent
    """
    # Get agent configuration from registry
    agent_config = get_agent_config(agent_name)
    if agent_config is None:
        raise ValueError(f"Unknown agent: {agent_name}. Use list_agent_names() to see available agents.")

    # Use anthropic: prefix for Pydantic AI model specification
    model_name = f"anthropic:{model_id}"

    # Create agent with tools using agent-specific configuration
    agent = Agent(
        model_name,
        system_prompt=agent_config.system_prompt,
    )

    # Helper to check if tool is enabled
    def is_enabled(tool_name: str) -> bool:
        return agent_config.is_tool_enabled(tool_name)

    # Register tools conditionally based on agent configuration
    if is_enabled("python"):
        @agent.tool_plain
        async def python(code: str, timeout: int = 30) -> str:
            """Execute Python code and return the output."""
            return await execute_python(code, timeout)

    if is_enabled("shell"):
        @agent.tool_plain
        async def shell(command: str, cwd: str | None = None, timeout: int = 30) -> str:
            """Execute a shell command and return the output."""
            # Check if command is allowed for this agent
            if not agent_config.is_shell_command_allowed(command):
                return (
                    f"Error: Shell command not allowed for '{agent_name}' agent.\n"
                    f"Command: {command}\n\n"
                    f"This agent only allows specific shell commands for safety.\n"
                    f"Allowed patterns: {agent_config.allowed_shell_patterns}"
                )
            return await execute_shell(command, cwd, timeout)

    if is_enabled("read"):
        @agent.tool_plain
        async def read(path: str) -> str:
            """Read the contents of a file."""
            return await read_file(path)

    if is_enabled("write"):
        @agent.tool_plain
        async def write(path: str, content: str) -> str:
            """Write content to a file."""
            return await write_file(path, content)

        @agent.tool_plain
        async def edit(path: str, old_string: str, new_string: str, replace_all: bool = False) -> str:
            """Edit a file by replacing old_string with new_string."""
            return await edit_file(path, old_string, new_string, replace_all)

    if is_enabled("search"):
        @agent.tool_plain
        async def search(
            pattern: str, path: str = ".", content_pattern: str | None = None
        ) -> str:
            """Search for files by glob pattern, optionally filtering by content."""
            return await search_files(pattern, path, content_pattern)

        @agent.tool_plain
        async def grep(
            pattern: str,
            path: str = ".",
            file_pattern: str | None = None,
            ignore_case: bool = False,
            context_lines: int = 0,
        ) -> str:
            """Search file contents using regex pattern."""
            return await grep_files(pattern, path, file_pattern, ignore_case, context_lines)

    if is_enabled("ls"):
        @agent.tool_plain
        async def ls(path: str = ".", include_hidden: bool = False) -> str:
            """List contents of a directory."""
            return await list_directory(path, include_hidden)

    if is_enabled("fetch"):
        @agent.tool_plain
        async def fetch(url: str) -> str:
            """Fetch and extract text content from a URL."""
            return await web_fetch(url)

    if is_enabled("web"):
        @agent.tool_plain
        async def web(query: str) -> str:
            """Search the web for information."""
            return await web_search(query)

    return agent
