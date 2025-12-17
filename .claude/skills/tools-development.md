# Tools Development

This skill covers adding new tools to agents, tool registration patterns, best practices, and planned tool enhancements for the Claude Agent platform.

## Overview

Tools extend agent capabilities beyond the base MCP servers. Custom tools are registered directly on the agent using the `@agent.tool_plain` decorator, while complex operations use external MCP servers.

## Key Files

| File | Purpose |
|------|---------|
| `agent/agent.py` | Tool registration with decorators |
| `agent/tools/` | Tool implementation modules |
| `agent/registry.py` | Tool permissions per agent |

## Tool Registration Pattern

### Basic Tool

Tools are registered inside the agent creation context:

```python
from pydantic_ai import Agent

async with create_agent_with_mcp() as agent:
    @agent.tool_plain
    async def my_tool(param: str, optional_param: int = 10) -> str:
        """Tool description shown to the LLM.

        Detailed description of what the tool does and when to use it.

        Args:
            param: Description of required parameter
            optional_param: Description of optional parameter
        """
        # Implementation
        result = do_something(param, optional_param)
        return f"Result: {result}"
```

### Key Points

1. **Decorator**: Use `@agent.tool_plain` for simple async tools
2. **Async**: Tools must be `async def`
3. **Return string**: Return a string that describes the result
4. **Docstring**: The docstring becomes the tool's description for the LLM
5. **Args section**: Document parameters in the docstring
6. **Type hints**: Required for all parameters

## Built-in Tool Examples

### Todo Tools

Simple in-memory storage for task tracking:

```python
# Module-level storage
_todo_storage: dict[str, list[dict]] = {}

@agent.tool_plain
async def todowrite(todos: list[dict], session_id: str = "default") -> str:
    """Write/replace the todo list for task tracking.

    Args:
        todos: List of todo items with 'content', 'status', 'activeForm' fields
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
        status_icon = {"pending": "⏳", "in_progress": "🔄", "completed": "✅"}.get(
            todo.get("status", "pending"), "⏳"
        )
        lines.append(f"{i}. {status_icon} {todo.get('content', '')}")

    return "\n".join(lines)
```

### LSP Tools (Delegating Pattern)

Thin wrapper that delegates to implementation module:

```python
from .tools.lsp import hover as lsp_hover_impl

@agent.tool_plain
async def hover(file_path: str, line: int, character: int) -> str:
    """Get type information and documentation for a symbol at a position.

    Use this to understand function signatures, type annotations, and
    documentation for code symbols.

    Args:
        file_path: Absolute path to the source file
        line: 0-based line number
        character: 0-based character offset within the line
    """
    result = await lsp_hover_impl(file_path, line, character)
    if result.get("success"):
        return result.get("contents", "No hover information available")
    return f"Error: {result.get('error', 'Unknown error')}"
```

### Browser Tools (Error Handling Pattern)

External service communication with proper error handling:

```python
import httpx
from .browser_client import get_browser_client

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
        return "Browser not connected. Ensure the Plue app is running."
    except httpx.TimeoutException:
        return "Browser operation timed out."
```

## Best Practices

### 1. Keep Tools Thin

Delegate complex logic to implementation modules:

```python
# Good - thin wrapper
@agent.tool_plain
async def hover(file_path: str, line: int, character: int) -> str:
    result = await lsp_hover_impl(file_path, line, character)
    return format_result(result)

# Bad - logic in tool
@agent.tool_plain
async def hover(file_path: str, line: int, character: int) -> str:
    # 50 lines of LSP protocol handling...
```

### 2. Return Descriptive Strings

Results should be human-readable and actionable:

```python
# Good
return f"Clicked element {ref}"
return "No hover information available at this position"
return f"Error: File not found: {file_path}"

# Bad
return "OK"
return {"success": True}
return ""
```

### 3. Handle Errors Gracefully

Always catch and report errors:

```python
try:
    result = await external_operation()
    if result.get("success"):
        return format_success(result)
    return f"Error: {result.get('error', 'Unknown error')}"
except ConnectionError:
    return "Service not connected. Please ensure it's running."
except TimeoutError:
    return "Operation timed out. Try again or check the service."
except Exception as e:
    return f"Unexpected error: {str(e)}"
```

### 4. Use Module-Level Constants

```python
# Constants at top of module
REQUEST_TIMEOUT_SECONDS = 30.0
MAX_OUTPUT_LENGTH = 30000

# Use in code
async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT_SECONDS) as client:
    ...
```

### 5. Document Tool Usage

Include when and how to use the tool:

```python
@agent.tool_plain
async def browser_snapshot(include_hidden: bool = False, max_depth: int = 50) -> str:
    """Take accessibility snapshot of browser page. Returns text tree with element refs.

    The snapshot shows the page structure with clickable/interactive elements
    labeled with refs like 'e1', 'e2', etc. Use these refs with other browser tools.

    Args:
        include_hidden: Include hidden elements in snapshot
        max_depth: Maximum depth of element tree to traverse
    """
```

## Planned Tool Enhancements

### Read-Before-Write Enforcement

Safety mechanism requiring files to be read before edit/write:

```python
# Track file read timestamps
class FileTimeTracker:
    def mark_read(self, filepath: str) -> None:
        """Record file read with current mtime."""

    def assert_not_modified(self, filepath: str) -> None:
        """Verify file hasn't changed since last read."""
        # Raises error if:
        # - File not previously read
        # - File modified since last read

# Error messages:
# "File {path} has not been read. Use Read tool first."
# "File {path} modified since last read. Please read again."
```

### Output Truncation

Prevent context overflow from large outputs:

```python
# Constants
MAX_BASH_OUTPUT_LENGTH = 30000
MAX_LINE_LENGTH = 2000

# Truncate long outputs
if len(output) > MAX_BASH_OUTPUT_LENGTH:
    output = output[:MAX_BASH_OUTPUT_LENGTH] + "\n... (output truncated)"

# Metadata
metadata = {
    "truncated": True,
    "original_length": 150000,
    "max_length": MAX_BASH_OUTPUT_LENGTH
}
```

### Search Context Lines

Add context around search matches:

```python
@agent.tool_plain
async def search(
    pattern: str,
    path: str = ".",
    context_lines: int = 2,  # New parameter
) -> str:
    """Search for pattern with surrounding context."""
```

### Search Pagination

Handle large result sets:

```python
@agent.tool_plain
async def search(
    pattern: str,
    path: str = ".",
    offset: int = 0,      # Skip first N matches
    limit: int = 100,     # Return at most N matches
) -> str:
    """Search with pagination support."""
```

## Adding a New Tool

### Step-by-Step

1. **Decide on scope**: Tool in agent.py or separate module?
2. **Create implementation** (if complex): `agent/tools/my_feature.py`
3. **Register tool** inside `create_agent_with_mcp()`:
   ```python
   @agent.tool_plain
   async def my_tool(...) -> str:
       """..."""
   ```
4. **Add to registry** if tool needs permission control:
   ```python
   # In registry.py BUILTIN_AGENTS
   tools_enabled={
       "my_tool": True,
       ...
   }
   ```
5. **Write tests**: `tests/test_agent/test_tools/test_my_tool.py`
6. **Document** in this skill file

### Example: Adding a File Hash Tool

```python
# agent/agent.py - inside create_agent_with_mcp()

import hashlib

@agent.tool_plain
async def file_hash(file_path: str, algorithm: str = "sha256") -> str:
    """Calculate cryptographic hash of a file.

    Useful for verifying file integrity or comparing files.
    Supports: md5, sha1, sha256, sha512

    Args:
        file_path: Absolute path to the file
        algorithm: Hash algorithm (default: sha256)
    """
    import aiofiles

    algorithms = {"md5", "sha1", "sha256", "sha512"}
    if algorithm not in algorithms:
        return f"Error: Unknown algorithm. Use one of: {', '.join(algorithms)}"

    try:
        hasher = hashlib.new(algorithm)
        async with aiofiles.open(file_path, "rb") as f:
            while chunk := await f.read(8192):
                hasher.update(chunk)
        return f"{algorithm}:{hasher.hexdigest()}"
    except FileNotFoundError:
        return f"Error: File not found: {file_path}"
    except PermissionError:
        return f"Error: Permission denied: {file_path}"
```

## MCP vs Custom Tools

### Use MCP Servers For:
- Shell command execution
- File system operations (read, write, list)
- Operations that benefit from external process isolation
- Third-party integrations with existing MCP servers

### Use Custom Tools For:
- Simple operations without external dependencies
- Session-scoped state (todos, tracking)
- Integrations with internal services (LSP, browser)
- Operations requiring Python libraries directly

## Testing Tools

```python
# tests/test_agent/test_tools/test_my_tool.py
import pytest
from agent.tools.my_feature import my_function

@pytest.mark.asyncio
async def test_my_tool_success():
    result = await my_function("input")
    assert "expected" in result

@pytest.mark.asyncio
async def test_my_tool_error_handling():
    result = await my_function("bad_input")
    assert result.startswith("Error:")
```

## Related Skills

- [agent-system.md](./agent-system.md) - Agent configuration and registry
- [lsp-integration.md](./lsp-integration.md) - LSP tool implementation details
- [browser-tools.md](./browser-tools.md) - Browser automation tools
- [testing.md](./testing.md) - Tool testing patterns
