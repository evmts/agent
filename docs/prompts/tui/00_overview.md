# Zig TUI Implementation Plan

## Overview

This document outlines the complete plan to implement a Zig-based TUI with 100% feature parity to the Codex TUI. The TUI will use **libvaxis** for terminal rendering and integrate with the existing Zig AI agent system.

## Architecture

```
tui-zig/
├── src/
│   ├── main.zig              # Entry point, CLI arg parsing
│   ├── app.zig               # Main App state and vxfw integration
│   ├── client/
│   │   ├── sse.zig           # SSE client for streaming responses
│   │   ├── http.zig          # HTTP client wrapper
│   │   └── protocol.zig      # Message types and serialization
│   ├── state/
│   │   ├── session.zig       # Session state management
│   │   ├── conversation.zig  # Conversation/thread state
│   │   └── config.zig        # User configuration
│   ├── widgets/
│   │   ├── chat_history.zig  # Scrollable message history
│   │   ├── composer.zig      # Multi-line input widget
│   │   ├── status_bar.zig    # Status and token display
│   │   ├── header.zig        # Session header widget
│   │   ├── tool_call.zig     # Tool execution display
│   │   ├── approval.zig      # Approval overlay
│   │   ├── list_select.zig   # Model/session picker
│   │   └── file_search.zig   # Fuzzy file finder
│   ├── render/
│   │   ├── markdown.zig      # Markdown to styled text
│   │   ├── syntax.zig        # Code syntax highlighting
│   │   ├── diff.zig          # Unified diff rendering
│   │   └── ansi.zig          # ANSI escape sequence handling
│   └── utils/
│       ├── unicode.zig       # Unicode width calculations
│       ├── wrap.zig          # Text wrapping
│       └── time.zig          # Duration formatting
└── build.zig                 # Build configuration
```

## Dependencies

- **libvaxis** (local): Terminal UI framework (already cloned)
- **std.http**: HTTP client for API calls
- **std.json**: JSON parsing

## Implementation Phases

### Phase 1: Foundation (Prompts 01-05)
- Build system integration
- Core app structure with vxfw
- SSE client for streaming
- State management primitives
- Basic layout system

### Phase 2: Core UI (Prompts 06-08)
- Chat history widget with scrolling
- Input composer with editing
- Status bar and header

### Phase 3: Rich Rendering (Prompts 09-11)
- Markdown renderer
- Syntax highlighting
- Diff visualization

### Phase 4: Interactive Features (Prompts 12-16)
- Tool call visualization
- Approval overlays
- Session management
- Slash commands
- File mentions

### Phase 5: Polish (Prompt 17)
- Testing
- Edge cases
- Performance optimization

## Feature Parity Checklist

### Display & Rendering
- [ ] Multi-pane layout (chat + input)
- [ ] Scrollable chat history
- [ ] Markdown rendering (headers, bold, italic, code, lists)
- [ ] Code blocks with syntax highlighting
- [ ] Unified diff display with colors
- [ ] ANSI escape sequence handling
- [ ] Live streaming text updates
- [ ] Spinner animations
- [ ] Token usage display

### Input & Interaction
- [ ] Multi-line text input
- [ ] Message history navigation
- [ ] Slash command parsing
- [ ] File mentions (@file)
- [ ] Tab completion
- [ ] Keyboard shortcuts

### Session Management
- [ ] Create new sessions
- [ ] List and switch sessions
- [ ] Session metadata display
- [ ] Undo/rollback

### Tool Integration
- [ ] Tool call visualization
- [ ] Execution status indicators
- [ ] Duration tracking
- [ ] Error display

### Advanced
- [ ] Approval overlays
- [ ] Model selection UI
- [ ] File search popup
- [ ] Mouse support
- [ ] Clipboard integration

## Reference Materials

- **libvaxis**: `/Users/williamcory/plue/libvaxis/` - Zig TUI library
- **codex**: `/Users/williamcory/plue/codex/` - Reference implementation
- **existing agent**: `/Users/williamcory/plue/server/src/ai/` - Zig AI agent
- **old TUI**: `/Users/williamcory/plue/tui/` - TypeScript TUI (to be replaced)

## Next Steps

Start with `01_project_setup.md` to set up the build system and basic project structure.
