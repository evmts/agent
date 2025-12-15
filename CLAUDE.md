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

### TypeScript/Bun (Optional Demo)
- Bun runtime (NOT Node.js)

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

### Go

```bash
# Build TUI
cd claude-tui && make build

# Run TUI
./claude-tui -backend http://localhost:8000

# Run SDK tests
cd sdk/agent && go test ./...
```

### Bun/TypeScript

Use Bun instead of Node.js:
- `bun <file>` instead of `node <file>`
- `bun test` instead of `jest`
- `bun install` instead of `npm install`
- `bunx <pkg>` instead of `npx <pkg>`

## Key Files

| File | Purpose |
|------|---------|
| `server.py` | Main FastAPI server (876 lines) |
| `agent/agent.py` | Agent creation & tool registration |
| `agent/wrapper.py` | Streaming adapter for server |
| `agent/tools/*.py` | Tool implementations |
| `snapshot/snapshot.py` | Git-based snapshot system |
| `sdk/agent/client.go` | Go SDK HTTP client |
| `sdk/agent/types.go` | OpenCode type definitions |
| `claude-tui/internal/app/` | TUI application logic |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Required - Claude API key | - |
| `ANTHROPIC_MODEL` | Model ID | `claude-sonnet-4-20250514` |
| `PORT` | Server port | `8000` |
| `CORS_ORIGINS` | Allowed origins | `*` |

## Code Patterns

### Adding a New Tool

1. Create function in `agent/tools/`:
```python
async def my_tool(param: str) -> str:
    """Tool description."""
    # Implementation
    return result
```

2. Export in `agent/tools/__init__.py`

3. Register in `agent/agent.py`:
```python
@agent.tool_plain
async def my_tool(param: str) -> str:
    """Tool description."""
    return await my_tool_impl(param)
```

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

- **Shell execution**: Commands are validated for dangerous patterns
- **File operations**: Path traversal prevention via `_validate_path()`
- **CORS**: Configurable via `CORS_ORIGINS` env var
- **Timeouts**: All subprocess operations have timeouts

## Testing Guidelines

- Write async tests with `@pytest.mark.asyncio`
- Test both success and error paths
- Mock external services (API calls, file system)

## Common Tasks

### Running the Full Stack

```bash
# Terminal 1: Start server
export ANTHROPIC_API_KEY="your-key"
python main.py

# Terminal 2: Start TUI
cd claude-tui && ./claude-tui
```

### Debugging

- Server logs to stdout
- TUI debug: Check `internal/app/update.go` for message handling
- SDK: Use `-v` flag with go test for verbose output

## Style Guide

### Python
- Type hints required
- Async functions for I/O
- Docstrings for public functions

### Go
- Standard gofmt formatting
- Godoc comments for exports
- Error handling explicit

## Bun-Specific APIs

When writing TypeScript:
- `Bun.serve()` for HTTP server (not Express)
- `Bun.file()` for file operations
- `bun:sqlite` for SQLite
- WebSocket is built-in
