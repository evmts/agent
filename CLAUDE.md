# Claude Agent - Development Guidelines

AI agent platform with Python backend (FastAPI), Go SDK/TUI, and Git-based snapshot system.

## Quick Start

```bash
export ANTHROPIC_API_KEY="your-key"
python main.py  # or: zig build run
```

## Key Commands

| Command | Purpose |
|---------|---------|
| `python main.py` | Run server |
| `pytest` | Run all tests |
| `pytest tests/e2e/` | Run E2E tests |
| `zig build run` | Run via Zig |
| `zig build test` | Test via Zig |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | - | Required - Claude API key |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-20250514` | Model ID |
| `HOST` | `0.0.0.0` | Server host |
| `PORT` | `8000` | Server port |
| `WORKING_DIR` | cwd | Working directory |

## Global Style Guide

### No Magic Constants
```python
# Good - constants at module level
DEFAULT_PORT = 8000
port = int(os.environ.get("PORT", str(DEFAULT_PORT)))

# Bad - hardcoded literals
port = int(os.environ.get("PORT", "8000"))
```

### Python
- Type hints required on all functions
- Async for I/O operations
- Docstrings on public functions

### Go
- Standard gofmt formatting
- Godoc comments for exports
- Explicit error handling

## Skills Reference

See `.claude/skills/` for detailed guidance on specific topics:

| Skill | Topics |
|-------|--------|
| [configuration.md](.claude/skills/configuration.md) | Config system, env vars, JSONC |
| [python-backend.md](.claude/skills/python-backend.md) | FastAPI server, routes, SSE |
| [api-development.md](.claude/skills/api-development.md) | OpenCode API spec, endpoints |
| [agent-system.md](.claude/skills/agent-system.md) | Agent creation, registry, MCP |
| [tools-development.md](.claude/skills/tools-development.md) | Adding new tools, patterns |
| [lsp-integration.md](.claude/skills/lsp-integration.md) | LSP hover, diagnostics |
| [browser-tools.md](.claude/skills/browser-tools.md) | Browser automation |
| [snapshot-system.md](.claude/skills/snapshot-system.md) | Git snapshots, revert |
| [testing.md](.claude/skills/testing.md) | pytest, fixtures, E2E |
| [go-development.md](.claude/skills/go-development.md) | SDK client, TUI |
