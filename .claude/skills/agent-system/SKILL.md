---
name: agent-system
description: Plue AI agent architecture, tools, and configuration. Use when working on the agent system, adding tools, or understanding how the Claude-powered agent works.
---

# Plue Agent System

The agent system provides autonomous Claude-powered assistance integrated into the Plue platform.

## Architecture

```
server/src/ai/
├── agent.zig          # Agent runner (Claude API)
├── client.zig         # Anthropic API client
├── types.zig          # Shared types
└── tools/             # Agent tools
    ├── grep.zig       # Content search
    ├── read_file.zig  # File reading
    ├── write_file.zig # File writing
    ├── multiedit.zig  # Multi-file editing
    ├── web_fetch.zig  # HTTP fetching
    ├── github.zig     # GitHub API
    └── pty_tools.zig  # Shell execution
```

## Available Tools

| Tool | Purpose |
|------|---------|
| `grep` | Search file contents with regex |
| `readFile` | Read file with line numbers |
| `writeFile` | Write/create files (requires read first) |
| `multiedit` | Multiple find-replace operations |
| `webFetch` | Fetch and process web content |
| `bash` | Execute shell commands via PTY |

## Key Features

- **Read-before-write safety**: Files must be read before writing
- **Path traversal protection**: Sandboxed to working directory
- **SSE streaming**: Real-time token output via Server-Sent Events
- **Abort support**: Graceful cancellation via POST endpoint

## Configuration

- Model: Claude Sonnet 4
- Max iterations: Configurable per request
- Output: Streaming via SSE (Server-Sent Events)
- Endpoints: GET /api/sessions/:id/stream, POST /api/sessions/:id/abort
