---
name: agent-system
description: Plue AI agent architecture, tools, and configuration. Use when working on the agent system, adding tools, or understanding how the Claude-powered agent works.
---

# Plue Agent System

The agent system provides autonomous Claude-powered assistance integrated into the Plue platform.

## Architecture

```
ai/
├── agent.ts           # Agent runner (Vercel AI SDK + Claude)
├── registry.ts        # Agent configuration
└── tools/             # 9 agent tools
```

## Agent Modes

| Mode      | Purpose                              |
|-----------|--------------------------------------|
| `general` | General-purpose assistance           |
| `explore` | Codebase exploration and discovery   |
| `plan`    | Planning and architecture decisions  |

## Available Tools

The agent has access to 9 tools:
- `grep` - Search file contents
- `readFile` - Read file contents
- `writeFile` - Write/create files
- `multiedit` - Edit multiple files
- `webFetch` - Fetch web content
- `unifiedExec` - Execute shell commands
- Plus additional file operation tools

## Configuration

- Max steps per run: 10 (configurable)
- Model: Claude Sonnet 4
- Output: Streaming via SSE

## State Management

- **Runtime**: Maps for active sessions/tasks (in-memory)
- **Persistence**: PostgreSQL for sessions, messages, snapshots
- **Communication**: EventBus pub/sub system

## Key Files

- `core/state.ts` - Dual-layer state (runtime + DB)
- `core/events.ts` - EventBus pub/sub
- `core/sessions.ts` - Session CRUD
- `core/models/` - Data models (message, session, part)
