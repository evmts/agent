# Plue TUI

A brutalist terminal user interface for the Plue AI Agent, built with [@clack/prompts](https://www.clack.cc/).

## Features

- Interactive chat with streaming responses
- Session management (create, list, switch)
- Slash commands for quick actions
- Tool call visualization
- Real-time SSE streaming

## Installation

```bash
cd tui
bun install
```

## Usage

```bash
# Start the TUI (requires API server running)
bun run dev

# Or with custom API URL
bun run dev --api-url http://localhost:4000
```

## Commands

| Command | Description |
|---------|-------------|
| `/new` | Create a new session |
| `/sessions` | List all sessions |
| `/switch <id>` | Switch to a session |
| `/clear` | Clear the screen |
| `/diff` | Show session diff |
| `/abort` | Abort current task |
| `/help` | Show help |
| `/quit` | Exit the TUI |

## Keyboard Shortcuts

- `Ctrl+C` - Cancel/Quit
- `Enter` - Send message
- Arrow keys - Navigate options

## Requirements

- Bun runtime
- Plue API server running at http://localhost:4000 (or custom URL)

## Development

```bash
# Run in development
bun run dev

# Build
bun run build

# Type check
bunx tsc --noEmit
```
