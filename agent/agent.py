"""
Pydantic AI Agent configuration using MCP servers for tools.

Uses external MCP servers for shell and filesystem operations,
minimizing custom tool code that needs to be maintained.
"""

import os
import sys
from contextlib import asynccontextmanager
from typing import AsyncIterator

import httpx
from pydantic_ai import Agent, WebSearchTool
from pydantic_ai.mcp import MCPServerStdio
from pydantic_ai.models.anthropic import AnthropicModelSettings

from .browser_client import get_browser_client
from .tools.lsp import diagnostics as lsp_diagnostics_impl
from .tools.lsp import hover as lsp_hover_impl
from .tools.lsp import touch_file as lsp_touch_file_impl
from .tools.multiedit import multiedit as multiedit_impl
from .tools.web_fetch import fetch_url

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
THINKING_BUDGET_TOKENS = 60000  # Extended thinking budget (higher than Claude Code's default 32k)
MAX_OUTPUT_TOKENS = 64000  # Must be greater than thinking budget

# Tool output truncation constants
MAX_BASH_OUTPUT_LENGTH = 30000
MAX_LINE_LENGTH = 2000
DEFAULT_READ_LIMIT = 2000


def _truncate_long_lines(content: str, max_line_length: int = MAX_LINE_LENGTH) -> tuple[str, bool, int]:
    """Truncate long lines in content to prevent context overflow.

    Args:
        content: The text content to process
        max_line_length: Maximum allowed length per line

    Returns:
        Tuple of (truncated_content, was_truncated, original_length)
    """
    lines = content.splitlines(keepends=True)
    truncated_lines = []
    was_truncated = False
    original_length = len(content)

    for line in lines:
        # Check line length without the newline character
        line_without_newline = line.rstrip('\r\n')
        if len(line_without_newline) > max_line_length:
            # Truncate the line and add indicator
            truncated_lines.append(line_without_newline[:max_line_length] + "...\n")
            was_truncated = True
        else:
            truncated_lines.append(line)

    return ''.join(truncated_lines), was_truncated, original_length


def get_anthropic_model_settings(enable_thinking: bool = True) -> AnthropicModelSettings:
    """Get Anthropic model settings with optional extended thinking.

    Args:
        enable_thinking: Whether to enable extended thinking (default True)

    Returns:
        AnthropicModelSettings configured for the agent
    """
    settings: AnthropicModelSettings = {
        'max_tokens': MAX_OUTPUT_TOKENS,  # Required to be > thinking budget
    }

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
- Executing shell commands (via shell tool) - output truncated at 30,000 characters
- Reading and writing files (via filesystem tools) - lines truncated at 2,000 characters
- Managing todo lists for task tracking
- Searching the web for up-to-date information

When helping users, prefer to:
1. Read relevant files first to understand context
2. Make targeted changes rather than rewriting entire files
3. Explain what you're doing and why
4. Verify changes work correctly

Important output limits:
- Shell command output is automatically truncated at 30,000 characters to prevent context overflow
- File read operations truncate individual lines at 2,000 characters
- If output is truncated, metadata will indicate the original length

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

    # Browser automation tools (connect to Swift app's browser API)
    @agent.tool_plain
    async def browser_snapshot(
        include_hidden: bool = False,
        max_depth: int = 50,
    ) -> str:
        """Take accessibility snapshot of browser page. Returns text tree with element refs.

        The snapshot shows the page structure with clickable/interactive elements
        labeled with refs like 'e1', 'e2', etc. Use these refs with other browser tools.

        Args:
            include_hidden: Include hidden elements in snapshot
            max_depth: Maximum depth of element tree to traverse
        """
        try:
            client = get_browser_client()
            result = await client.snapshot(include_hidden, max_depth)
            if result.get("success"):
                return result.get("text_tree", "Empty snapshot")
            return f"Error: {result.get('error', 'Unknown error')}"
        except httpx.ConnectError:
            return "Browser not connected. Ensure the Plue app is running with a browser tab open."
        except httpx.TimeoutException:
            return "Browser operation timed out."

    @agent.tool_plain
    async def browser_click(ref: str) -> str:
        """Click an element by its ref (e.g., 'e1', 'e23').

        Use browser_snapshot first to see available elements and their refs.

        Args:
            ref: Element reference from snapshot (e.g., 'e1')
        """
        try:
            client = get_browser_client()
            result = await client.click(ref)
            if result.get("success"):
                return f"Clicked element {ref}"
            return f"Error: {result.get('error', 'Unknown error')}"
        except httpx.ConnectError:
            return "Browser not connected. Ensure the Plue app is running with a browser tab open."
        except httpx.TimeoutException:
            return "Browser operation timed out."

    @agent.tool_plain
    async def browser_type(ref: str, text: str, clear: bool = False) -> str:
        """Type text into an input element.

        Args:
            ref: Element reference from snapshot (e.g., 'e5')
            text: Text to type into the element
            clear: Whether to clear existing content first
        """
        try:
            client = get_browser_client()
            result = await client.type_text(ref, text, clear)
            if result.get("success"):
                return f"Typed into element {ref}"
            return f"Error: {result.get('error', 'Unknown error')}"
        except httpx.ConnectError:
            return "Browser not connected. Ensure the Plue app is running with a browser tab open."
        except httpx.TimeoutException:
            return "Browser operation timed out."

    @agent.tool_plain
    async def browser_scroll(direction: str = "down", amount: int = 300) -> str:
        """Scroll the browser page.

        Args:
            direction: Scroll direction - 'up', 'down', 'left', or 'right'
            amount: Scroll amount in pixels
        """
        try:
            client = get_browser_client()
            result = await client.scroll(direction, amount)
            if result.get("success"):
                return f"Scrolled {direction} by {amount}px"
            return f"Error: {result.get('error', 'Unknown error')}"
        except httpx.ConnectError:
            return "Browser not connected. Ensure the Plue app is running with a browser tab open."
        except httpx.TimeoutException:
            return "Browser operation timed out."

    @agent.tool_plain
    async def browser_extract(ref: str) -> str:
        """Extract text content from an element.

        Args:
            ref: Element reference from snapshot (e.g., 'e10')
        """
        try:
            client = get_browser_client()
            result = await client.extract_text(ref)
            if result.get("success"):
                return result.get("text", "")
            return f"Error: {result.get('error', 'Unknown error')}"
        except httpx.ConnectError:
            return "Browser not connected. Ensure the Plue app is running with a browser tab open."
        except httpx.TimeoutException:
            return "Browser operation timed out."

    @agent.tool_plain
    async def browser_screenshot() -> str:
        """Take a screenshot of the browser page.

        Returns base64-encoded PNG image data.
        """
        try:
            client = get_browser_client()
            result = await client.screenshot()
            if result.get("success"):
                return result.get("image_base64", "")
            return f"Error: {result.get('error', 'Unknown error')}"
        except httpx.ConnectError:
            return "Browser not connected. Ensure the Plue app is running with a browser tab open."
        except httpx.TimeoutException:
            return "Browser operation timed out."

    @agent.tool_plain
    async def browser_navigate(url: str) -> str:
        """Navigate the browser to a URL.

        Args:
            url: URL to navigate to (e.g., 'https://example.com')
        """
        try:
            client = get_browser_client()
            result = await client.navigate(url)
            if result.get("success"):
                return f"Navigated to {url}"
            return f"Error: {result.get('error', 'Unknown error')}"
        except httpx.ConnectError:
            return "Browser not connected. Ensure the Plue app is running with a browser tab open."
        except httpx.TimeoutException:
            return "Browser operation timed out."

    # LSP hover tool for type information
    @agent.tool_plain
    async def hover(file_path: str, line: int, character: int) -> str:
        """Get type information and documentation for a symbol at a position.

        Use this to understand function signatures, type annotations, and
        documentation for code symbols. Useful for debugging type errors
        and understanding code semantics.

        Args:
            file_path: Absolute path to the source file
            line: 0-based line number
            character: 0-based character offset within the line
        """
        result = await lsp_hover_impl(file_path, line, character)
        if result.get("success"):
            return result.get("contents", "No hover information available")
        return f"Error: {result.get('error', 'Unknown error')}"

    # LSP diagnostics tool for errors and warnings
    @agent.tool_plain
    async def get_diagnostics(file_path: str, timeout: float = 5.0) -> str:
        """Get diagnostics (errors, warnings, hints) for a file.

        Use this to check for type errors, syntax errors, and other issues
        in code before attempting fixes. Returns formatted diagnostic info
        with severity, line/column, and message.

        Args:
            file_path: Absolute path to the source file
            timeout: Maximum time to wait for diagnostics (default 5s)
        """
        result = await lsp_diagnostics_impl(file_path, timeout=timeout)
        if result.get("success"):
            return result.get("formatted_output", "No diagnostics found")
        return f"Error: {result.get('error', 'Unknown error')}"

    # LSP touch file tool to pre-check files before editing
    @agent.tool_plain
    async def check_file_errors(file_path: str, timeout: float = 3.0) -> str:
        """Check a file for errors before editing.

        Opens the file in the language server and waits for diagnostics.
        Use this to understand the current error state before making changes.

        Args:
            file_path: Absolute path to the source file
            timeout: Maximum time to wait for diagnostics (default 3s)
        """
        result = await lsp_touch_file_impl(file_path, wait_for_diagnostics=True, timeout=timeout)
        if result.get("success"):
            summary = result.get("summary", "")
            diagnostics = result.get("diagnostics", [])
            if not diagnostics:
                return f"No errors found in {file_path}"
            return f"{summary}\n" + "\n".join(f"  {d}" for d in diagnostics)
        return f"Error: {result.get('error', 'Unknown error')}"

    # Custom file read tool with line truncation
    @agent.tool_plain
    async def read_file_safe(file_path: str, offset: int = 0, limit: int = DEFAULT_READ_LIMIT) -> str:
        """Read a file with automatic line truncation to prevent context overflow.

        This tool reads files and truncates lines longer than 2000 characters
        to prevent overwhelming the context window. Use the MCP read_text_file
        tool if you need the full untruncated content.

        Args:
            file_path: Absolute path to the file to read
            offset: Line number to start reading from (0-based, default 0)
            limit: Maximum number of lines to read (default 2000)

        Returns:
            File content with long lines truncated, or error message
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                # Read all lines
                all_lines = f.readlines()

                # Apply offset and limit
                lines_to_read = all_lines[offset:offset + limit] if limit > 0 else all_lines[offset:]

                # Join lines and check for truncation
                content = ''.join(lines_to_read)
                truncated_content, was_truncated, original_length = _truncate_long_lines(content)

                # Add metadata if truncated
                if was_truncated:
                    truncated_content += f"\n\n[Note: Some lines were truncated. Original content length: {original_length} chars, Max line length: {MAX_LINE_LENGTH} chars]"

                return truncated_content

        except FileNotFoundError:
            return f"Error: File not found: {file_path}"
        except PermissionError:
            return f"Error: Permission denied: {file_path}"
        except UnicodeDecodeError:
            return f"Error: File is not a text file or uses unsupported encoding: {file_path}"
        except Exception as e:
            return f"Error reading file: {str(e)}"

    # Custom web fetch tool with size limits
    @agent.tool_plain
    async def web_fetch(url: str, timeout: float = 30.0) -> str:
        """Fetch content from a URL with a 5MB size limit.

        This tool enforces a 5MB size limit to prevent memory exhaustion
        and protect against malicious servers streaming infinite data.

        Args:
            url: URL to fetch (must start with http:// or https://)
            timeout: Request timeout in seconds (default: 30)

        Returns:
            Response content as string
        """
        try:
            return await fetch_url(url, timeout=timeout)
        except ValueError as e:
            return f"Error: {str(e)}"
        except httpx.TimeoutException as e:
            return f"Error: {str(e)}"
        except Exception as e:
            return f"Error: Unexpected error fetching URL: {str(e)}"

    # MultiEdit tool for atomic multi-file edits
    @agent.tool_plain
    async def multiedit(file_path: str, edits: list[dict]) -> str:
        """Perform multiple find-and-replace operations on a single file atomically.

        All edits are validated before any are applied. Each edit operates on
        the result of the previous edit, allowing dependent changes.

        For single edits, use a 1-element edits array.

        Args:
            file_path: Absolute path to file to modify
            edits: Array of edit operations, each with:
                - old_string: Text to replace (empty creates file on first edit)
                - new_string: Replacement text
                - replace_all: (optional) Replace all occurrences (default: false)

        Returns:
            Success message with edit count, or error with details
        """
        cwd = working_dir or os.getcwd()
        result = await multiedit_impl(file_path, edits, working_dir=cwd)
        if result.get("success"):
            edit_count = result.get("edit_count", 0)
            rel_path = result.get("file_path", file_path)
            return f"Applied {edit_count} edit(s) to {rel_path}"
        return f"Error: {result.get('error', 'Unknown error')}"

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
    agent_kwargs = {
        "system_prompt": system_prompt,
    }
    if builtin_tools:
        agent_kwargs["builtin_tools"] = builtin_tools
    if tools:
        agent_kwargs["tools"] = tools

    agent = Agent(model_name, **agent_kwargs)

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
