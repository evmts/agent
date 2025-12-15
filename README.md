# Claude Agent

An AI agent platform that integrates Claude LLM with file system operations, code execution, and web capabilities. Features an OpenCode-compatible REST API server and a terminal UI client.

## Features

- **Python Backend Server** - FastAPI-based OpenCode-compatible REST API with SSE streaming
- **Terminal UI Client** - Interactive Go/Bubbletea TUI for chatting with the agent
- **Agent Tools** - Python/shell execution, file operations, web fetching
- **Snapshot System** - Git-based file state tracking for reverting changes
- **Go SDK** - Type-safe client library for the agent API

## Architecture

```
Claude TUI (Go)
    │
    ▼ (HTTP/SSE)
Go SDK Client
    │
    ▼ (HTTP/SSE)
FastAPI Server (Python)
    │
    ▼
Pydantic AI Agent (Claude)
    │
    ▼
Registered Tools
├── Python/Shell Executor
├── File Operations (R/W/Search)
├── Web Operations (Fetch/Search)
└── Returns Results
```

## Quick Start

### Prerequisites

- Python 3.11+
- Go 1.22+
- [Bun](https://bun.sh) (optional, for TypeScript demo)
- Anthropic API key

### Installation

```bash
# Clone the repository
git clone https://github.com/williamcory/agent.git
cd agent

# Install Python dependencies
pip install -e .
# Or with uv:
uv pip install -e .

# Install Bun dependencies (optional)
bun install
```

### Running the Server

```bash
# Set your API key
export ANTHROPIC_API_KEY="your-api-key"

# Optional: Set custom model
export ANTHROPIC_MODEL="claude-sonnet-4-20250514"

# Start the server
python main.py
```

The server runs at `http://localhost:8000` by default.

### Running the TUI Client

```bash
cd claude-tui

# Build the TUI
make build

# Run it
./claude-tui

# Or with custom backend URL:
./claude-tui -backend http://localhost:8000
```

### Using the Go SDK

```go
package main

import (
    "context"
    "github.com/williamcory/agent/sdk/agent"
)

func main() {
    client := agent.NewClient("http://localhost:8000")

    // Create a session
    session, _ := client.CreateSession(ctx, &agent.CreateSessionRequest{
        Title: agent.String("My Session"),
    })

    // Send a message with streaming
    eventCh, errCh, _ := client.SendMessage(ctx, session.ID, &agent.PromptRequest{
        Parts: []interface{}{
            agent.TextPartInput{Type: "text", Text: "Hello!"},
        },
    })

    for event := range eventCh {
        // Handle streaming events
    }
}
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Claude API key (required) | - |
| `ANTHROPIC_MODEL` | Model ID to use | `claude-sonnet-4-20250514` |
| `HOST` | Server host | `0.0.0.0` |
| `PORT` | Server port | `8000` |
| `CORS_ORIGINS` | Allowed CORS origins (comma-separated) | `*` |
| `BACKEND_URL` | TUI backend URL | `http://localhost:8000` |

## Project Structure

```
agent/
├── main.py                 # Server entry point
├── server.py               # FastAPI OpenCode API server
├── agent/                  # Python agent module
│   ├── agent.py           # Agent creation & tool registration
│   ├── wrapper.py         # Streaming adapter
│   └── tools/             # Tool implementations
│       ├── code_execution.py
│       ├── file_operations.py
│       └── web.py
├── snapshot/              # Git-based snapshot system
│   └── snapshot.py
├── claude-tui/            # Go TUI client
│   ├── main.go
│   └── internal/
├── sdk/agent/             # Go SDK
│   ├── client.go
│   └── types.go
└── tests/                 # Test suite
```

## Agent Tools

The agent has access to the following tools:

| Tool | Description |
|------|-------------|
| `python(code, timeout)` | Execute Python code in a sandboxed subprocess |
| `shell(command, cwd, timeout)` | Execute shell commands with security validation |
| `read(path)` | Read file contents with line numbers |
| `write(path, content)` | Write/create files |
| `search(pattern, path, content_pattern)` | Search files by glob pattern and content |
| `ls(path, include_hidden)` | List directory contents |
| `fetch(url)` | Fetch and extract text from URLs |
| `web(query)` | Web search (placeholder - needs API integration) |

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Health check |
| `GET` | `/global/event` | Global SSE event stream |
| `GET` | `/session` | List all sessions |
| `POST` | `/session` | Create new session |
| `GET` | `/session/{id}` | Get session details |
| `PATCH` | `/session/{id}` | Update session |
| `DELETE` | `/session/{id}` | Delete session |
| `POST` | `/session/{id}/message` | Send message (SSE streaming) |
| `POST` | `/session/{id}/abort` | Abort active session |
| `POST` | `/session/{id}/fork` | Fork session at message |
| `POST` | `/session/{id}/revert` | Revert to previous state |
| `GET` | `/session/{id}/diff` | Get file diffs |

## Testing

```bash
# Python tests
pytest

# Go SDK tests
cd sdk/agent && go test ./...

# TUI tests
cd claude-tui && go test ./...
```

## Security

- Shell commands are validated for dangerous patterns before execution
- File operations are restricted to prevent path traversal attacks
- CORS origins are configurable for production deployments
- Code execution runs in subprocess sandboxes with timeouts

## License

MIT License - see [LICENSE.md](LICENSE.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
