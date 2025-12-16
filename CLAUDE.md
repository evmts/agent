# Claude Agent - Development Guidelines

This file provides context for AI assistants working on this codebase.

## Project Overview

Claude Agent is an AI agent platform with:
- **Python backend** (FastAPI) - OpenCode-compatible REST API
- **Go TUI client** (Bubbletea) - Terminal interface
- **Go SDK** - Client library for the API
- **Snapshot system** - Git-based file state tracking

## Technology Stack

### Python (Backend)
- FastAPI for REST API
- Pydantic AI for agent framework
- SSE-Starlette for streaming
- asyncio for async operations

### Go (TUI & SDK)
- Bubbletea for terminal UI
- Standard library for HTTP client

## Development Commands

### Python

```bash
# Run server
python main.py

# Run tests
pytest

# Run specific tests
pytest tests/test_agent/test_tools/
```

### Go (using Zig build system)

```bash
# Build unified binary (PyInstaller + Go)
zig build

# Run unified TUI (includes embedded server)
zig build run

# Run with external backend (for development)
zig build run-dev

# Build Go TUI only (no PyInstaller)
zig build build-go

# Build Python server only
zig build pyinstaller

# Run tests
zig build test

# Format code
zig build fmt

# Run linter
zig build lint

# Clean build artifacts
zig build clean

# Update dependencies
zig build deps
```

## Key Files

| File | Purpose |
|------|---------|
| `main.py` | Server entry point with MCP lifecycle |
| `server/app.py` | FastAPI app setup & CORS config |
| `server/routes/` | API route handlers (sessions, messages, events) |
| `agent/agent.py` | Agent creation with MCP tools |
| `agent/wrapper.py` | Streaming adapter for server |
| `agent/registry.py` | Agent configurations & tool permissions |
| `config/` | Configuration loading & defaults |
| `core/` | Core models, sessions, events, state |
| `snapshot/snapshot.py` | Git-based snapshot system |
| `sdk/agent/client.go` | Go SDK HTTP client |
| `sdk/agent/types.go` | OpenCode type definitions |
| `tui/internal/app/` | TUI application logic |
| `build.zig` | Zig build system (root) |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Required - Claude API key | - |
| `ANTHROPIC_MODEL` | Model ID | `claude-sonnet-4-20250514` |
| `HOST` | Server host | `0.0.0.0` |
| `PORT` | Server port | `8000` |
| `CORS_ORIGINS` | Allowed origins | `*` |
| `USE_MCP` | Enable MCP tool servers | `true` |
| `WORKING_DIR` | Working directory for filesystem ops | Current directory |

## Code Patterns

### Adding a New Tool

Tools are registered directly in `agent/agent.py` using the `@agent.tool_plain` decorator:

```python
# Inside create_agent_with_mcp() or create_agent():
@agent.tool_plain
async def my_tool(param: str) -> str:
    """Tool description.

    Args:
        param: Description of the parameter
    """
    # Implementation
    return result
```

For shell/filesystem operations, use MCP servers (configured in `create_mcp_servers()`).
For custom tools that don't need MCP, add them with the decorator pattern above.

### API Endpoints

Follow OpenCode spec pattern:
- Session CRUD: `/session`, `/session/{id}`
- Messages: `/session/{id}/message`
- Actions: `/session/{id}/abort`, `/session/{id}/fork`, etc.

### SSE Events

Event types:
- `session.created`, `session.updated`, `session.deleted`
- `message.updated`
- `part.updated`

## Security Considerations

- **Shell execution**: MCP shell server with configurable timeouts
- **File operations**: MCP filesystem server scoped to working directory
- **Agent permissions**: Tool permissions per agent via `agent/registry.py`
- **CORS**: Configurable via `CORS_ORIGINS` env var
- **Timeouts**: MCP servers have configurable timeouts (60s shell, 30s filesystem)

## Testing Guidelines

- Write async tests with `@pytest.mark.asyncio`
- Test both success and error paths
- Mock external services (API calls, file system)

## Common Tasks

### Running the Full Stack

```bash
# Option 1: Unified binary (server embedded in TUI)
export ANTHROPIC_API_KEY="your-key"
zig build run

# Option 2: Separate processes (for development)
# Terminal 1: Start server
export ANTHROPIC_API_KEY="your-key"
python main.py

# Terminal 2: Start TUI with external backend
zig build run-dev
```

### Debugging

- Server logs to stdout
- TUI debug: Check `tui/internal/app/update.go` and `update_keys.go` for message handling
- TUI commands: See `commands_*.go` files for session, message, dialog, and system commands
- SDK: Use `-v` flag with go test for verbose output

## Style Guide

### No Magic Constants
- Never use magic constants (hardcoded literal values) directly in code
- Always define constants with descriptive names in `SCREAMING_CASE`
- Place constants at module level, near the top of the file
- Example:
```python
# Good
DEFAULT_PORT = 8000
DEFAULT_HOST = "0.0.0.0"
port = int(os.environ.get("PORT", str(DEFAULT_PORT)))

# Bad
port = int(os.environ.get("PORT", "8000"))
```

### Python
- Type hints required
- Async functions for I/O
- Docstrings for public functions

### Go
- Standard gofmt formatting
- Godoc comments for exports
- Error handling explicit
