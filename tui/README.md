# TUI

Terminal user interface for Plue, built with libvaxis. Provides a full-featured chat interface for interacting with AI agents.

## Architecture

```
┌──────────────────────────────────────────────────┐
│                   main.zig                       │  CLI entrypoint
│           Parse args, initialize components      │
└────────────────┬─────────────────────────────────┘
                 │
┌────────────────▼─────────────────────────────────┐
│                   app.zig                        │  Main app widget
│     Orchestrates UI, handles events & drawing    │
│  ┌─────────┬────────────┬─────────┬──────────┐  │
│  │ Header  │ Chat Area  │ Status  │ Composer │  │
│  └─────────┴────────────┴─────────┴──────────┘  │
└─┬───────────────┬───────────────┬────────────────┘
  │               │               │
  │ State         │ Client        │ Widgets
  ▼               ▼               ▼
┌──────────┐  ┌─────────┐  ┌──────────────┐
│ AppState │  │  Plue   │  │   Composer   │
│ Sessions │  │ Client  │  │ ChatHistory  │
│ Messages │  │ HTTP    │  │ ToolCard     │
│ Input    │  │ SSE     │  │ Approval     │
└──────────┘  └─────────┘  └──────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `main.zig` | CLI entrypoint, arg parsing, initialization |
| `app.zig` | Main application widget, event loop, layout |
| `build.zig` | Build configuration for standalone TUI |
| `types.zig` | Shared type definitions |

## Commands

```bash
zig build tui              # Build the TUI binary
./zig-out/bin/plue-tui     # Run the TUI
./zig-out/bin/plue-tui --api-url http://localhost:4000
```

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `client/` | HTTP and SSE client for Plue API |
| `commands/` | Slash command parsing and registry |
| `widgets/` | Reusable UI components (composer, chat, etc) |
| `state/` | Application state management |
| `utils/` | Text wrapping, file search, mentions |
| `render/` | Markdown, syntax highlighting, diff rendering |
| `tests/` | Unit tests for all components |
| `examples/` | Standalone examples and demos |

## Slash Commands

```
/new              Create new session
/sessions         List all sessions
/switch <id>      Switch to session
/model [name]     List or set model
/effort [level]   Set reasoning effort
/clear            Clear conversation
/help             Show help
/quit             Exit TUI
```

## Controls

```
Ctrl+C            Exit or abort streaming
Ctrl+L            Clear screen
Enter             Send message
Up/Down           Navigate history
Left/Right        Move cursor
Tab               Autocomplete
```

## Dependencies

- **libvaxis**: Terminal rendering library
- Zig standard library HTTP client
- JSON parsing for protocol
