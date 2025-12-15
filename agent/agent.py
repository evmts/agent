"""
Pydantic AI Agent configuration with Claude as the LLM provider.
"""

from pydantic_ai import Agent

from .tools import (
    execute_python,
    execute_shell,
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
- Searching through codebases
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
) -> Agent:
    """
    Create and configure a Pydantic AI agent with Claude.

    Args:
        model_id: Anthropic model identifier
        api_key: Optional API key (defaults to ANTHROPIC_API_KEY env var)

    Returns:
        Configured Pydantic AI Agent
    """
    # Use anthropic: prefix for Pydantic AI model specification
    model_name = f"anthropic:{model_id}"

    # Create agent with tools
    agent = Agent(
        model_name,
        system_prompt=SYSTEM_INSTRUCTIONS,
    )

    # Register tools using tool_plain decorator (no context needed)
    @agent.tool_plain
    async def python(code: str, timeout: int = 30) -> str:
        """Execute Python code and return the output."""
        return await execute_python(code, timeout)

    @agent.tool_plain
    async def shell(command: str, cwd: str | None = None, timeout: int = 30) -> str:
        """Execute a shell command and return the output."""
        return await execute_shell(command, cwd, timeout)

    @agent.tool_plain
    async def read(path: str) -> str:
        """Read the contents of a file."""
        return await read_file(path)

    @agent.tool_plain
    async def write(path: str, content: str) -> str:
        """Write content to a file."""
        return await write_file(path, content)

    @agent.tool_plain
    async def search(
        pattern: str, path: str = ".", content_pattern: str | None = None
    ) -> str:
        """Search for files by glob pattern, optionally filtering by content."""
        return await search_files(pattern, path, content_pattern)

    @agent.tool_plain
    async def ls(path: str = ".", include_hidden: bool = False) -> str:
        """List contents of a directory."""
        return await list_directory(path, include_hidden)

    @agent.tool_plain
    async def fetch(url: str) -> str:
        """Fetch and extract text content from a URL."""
        return await web_fetch(url)

    @agent.tool_plain
    async def web(query: str) -> str:
        """Search the web for information."""
        return await web_search(query)

    return agent
