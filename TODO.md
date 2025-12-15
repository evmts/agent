# TODO - Feature Comparison with OpenCode

This document compares our implementation with OpenCode's TUI and agent/server features.

## Legend
- [x] Implemented
- [~] Partially Implemented
- [ ] Not Implemented

---

## Server/API Features

### Session Management
- [x] Create session
- [x] List sessions
- [x] Get session by ID
- [x] Delete session
- [x] Update session (title, archive)
- [x] Fork session at message
- [x] Abort active session
- [x] Revert session to previous state
- [x] Unrevert session
- [x] Get session diff
- [ ] Share session (create shareable links)
- [ ] Unshare session
- [ ] Session tags/labels
- [ ] Session compaction/summarization

### Message Operations
- [x] Send message with SSE streaming
- [x] List messages in session
- [x] Get specific message
- [ ] Revert specific message parts
- [ ] Async prompt submission (fire and forget)
- [ ] Shell command execution within session context

### Event Streaming
- [x] Global SSE event stream
- [x] Session-level events (message.updated, part.updated)
- [x] Session lifecycle events (created, updated, deleted)
- [ ] Instance-level event streams

### Provider Management
- [ ] List available AI providers
- [ ] Get provider authentication methods
- [ ] OAuth authorize/callback for providers
- [ ] Set provider credentials
- [ ] List configured providers with defaults
- [ ] Multiple provider support (currently Anthropic only)

### Tool Management
- [~] Tool execution (basic tools work)
- [ ] List all available tools with schemas
- [ ] Get tool IDs
- [ ] Custom tool support from plugins
- [ ] Tool filtering by provider

### MCP (Model Context Protocol)
- [ ] Get MCP server status
- [ ] Add/remove MCP servers
- [ ] Connect/disconnect MCP servers
- [ ] OAuth authentication for MCP servers
- [ ] Dynamic MCP server loading

### PTY (Pseudo-Terminal)
- [ ] Create PTY sessions
- [ ] List/get/update/delete PTY
- [ ] WebSocket connection for real-time interaction
- [ ] Interactive shell execution

### LSP Integration
- [ ] Get LSP server status
- [ ] Workspace symbol lookup
- [ ] Code diagnostics retrieval
- [ ] Hover information

### Formatting
- [ ] Get formatter status
- [ ] Multiple formatter support (Prettier, Biome, gofmt, etc.)

### Configuration
- [~] Environment variable configuration
- [ ] Config file support (opencode.jsonc)
- [ ] Get/update configuration via API
- [ ] Plugin-provided configurations

### Permissions System
- [~] Basic permission handling (ask on dangerous operations)
- [ ] Request-response based permissions
- [ ] Tool-level granularity
- [ ] Pattern-based bash command filtering
- [ ] Permission caching and tracking

---

## Agent Features

### Built-in Agents
- [~] Default agent (similar to "build" agent)
- [ ] General agent (multi-step parallel tasks)
- [ ] Plan agent (read-only, safe commands only)
- [ ] Explore agent (codebase exploration specialist)

### Agent Configuration
- [x] System prompt customization
- [~] Model selection (via env var)
- [ ] Custom agents defined in config file
- [ ] Agent-specific tool permissions
- [ ] Per-agent bash command patterns
- [ ] Temperature and top-p settings per agent
- [ ] Agent color coding
- [ ] Mode specification (primary/subagent)
- [ ] Max steps configuration
- [ ] Agent generation from description

### Agent Modes
- [ ] Primary mode (main user interaction)
- [ ] Subagent mode (helper agents)
- [ ] All mode (any context)

---

## Tools

### File Operations
- [x] Read file with line numbers
- [x] Write file
- [x] Search files (glob pattern)
- [x] List directory
- [ ] Edit tool (partial file editing)
- [ ] Patch tool (apply unified diffs)
- [ ] Batch tool (batch multiple operations)
- [ ] Multi-edit tool

### Code Search & Analysis
- [~] Grep (basic regex search)
- [ ] CodeSearch (Exa integration)
- [ ] LSP Hover tool
- [ ] LSP Diagnostics tool

### Shell & System
- [x] Bash/shell execution
- [x] Python code execution
- [~] Web fetch (basic implementation)
- [ ] Web search (placeholder - needs API integration)
- [ ] Task tool (create and manage async tasks)

### Project Management
- [ ] TodoWrite tool (for agent use)
- [ ] TodoRead tool
- [ ] Session todo tracking

### Advanced Tools
- [ ] Compact tool (session history compression)

---

## TUI Features

### Core UI Components
- [x] Chat message display
- [x] User input field
- [x] Basic message scrolling
- [ ] Dialogs system (alert, confirm, prompt, select)
- [ ] Help dialog
- [ ] Model selection dialog
- [ ] Agent selection dialog
- [ ] MCP server dialog
- [ ] Status dialog
- [ ] Theme list dialog
- [ ] Session list dialog
- [ ] Session rename dialog
- [ ] Tag dialog
- [ ] Sidebar with session navigation
- [ ] Header/footer components

### Views & Routing
- [x] Session/chat view
- [ ] Home/landing view
- [ ] Dynamic route switching

### Keyboard & Input
- [x] Basic keybindings (ctrl+c, enter, etc.)
- [ ] Leader key support with timeout
- [ ] Configurable keybindings
- [ ] Vim-like leader key combinations
- [ ] Multi-key sequence support
- [ ] Command history with searchable navigation
- [ ] Autocomplete for prompts

### Mouse Support
- [ ] Copy on select
- [ ] Mouse input for text selection
- [ ] Click navigation

### Themes
- [ ] Built-in themes (25+ color schemes)
- [ ] System theme detection (dark/light)
- [ ] Custom themes from config directory
- [ ] Syntax highlighting for code
- [ ] Markdown rendering with formatting
- [ ] Diff visualization colors

### Message Display
- [x] User/assistant message rendering
- [x] Streaming text display
- [~] Tool execution display (basic)
- [ ] Thinking/reasoning display with toggle
- [ ] Timestamps toggle
- [ ] Username display toggle
- [ ] Tool details toggle
- [ ] Diff viewer with syntax highlighting
- [ ] Markdown rendering

### Navigation & Scrolling
- [x] Basic scrolling
- [ ] Page up/down message navigation
- [ ] Half-page scroll
- [ ] First/last message jump
- [ ] Configurable scroll speed
- [ ] macOS-style scroll acceleration
- [ ] Scrollbar toggle
- [ ] Quick jump to sessions needing input

### Notifications
- [ ] Toast notifications (info, success, warning, error)
- [ ] Duration control
- [ ] Auto-navigation to permission dialogs

### Status Display
- [ ] MCP server status with connection indicators
- [ ] Provider connection status
- [ ] Model selection display
- [ ] Agent selection display
- [ ] Session information (title, ID)
- [ ] Directory and version info
- [ ] Token/cost tracking display

---

## Configuration Features

### Config File Support
- [ ] opencode.jsonc / opencode.json in project root
- [ ] Global config (~/.opencode/opencode.jsonc)
- [ ] .opencode/ directory support
- [ ] Environment variable overrides
- [ ] Plugin-provided configurations

### Settings
- [ ] Username configuration
- [ ] Share settings (auto, manual, disabled)
- [ ] Permission policies for agents
- [ ] Tool enable/disable flags
- [ ] Experimental features toggle
- [ ] TUI configuration (scroll speed, scrollbar)
- [ ] Keybindings configuration
- [ ] Default theme selection
- [ ] MCP server configurations
- [ ] LSP server configurations
- [ ] Formatter selection

---

## Advanced Features

### Session Features
- [x] Basic snapshot system (git-based)
- [x] File state tracking
- [x] Revert to previous state
- [ ] Session compaction (compress long sessions)
- [ ] AI-powered message summarization
- [ ] Context window optimization
- [ ] Session branching (multi-threaded conversations)

### IDE Integration
- [ ] VS Code extension support
- [ ] Cursor extension support
- [ ] VSCodium support
- [ ] Windsurf support
- [ ] IDE detection

### Plugin System
- [ ] Load custom tools from plugin directory
- [ ] Tool definitions with Zod schemas
- [ ] Plugin execution context
- [ ] Plugin error handling
- [ ] Plugin dependency resolution

### Error Handling
- [~] Basic error handling
- [ ] Named error system with structured objects
- [ ] Graceful degradation for missing tools
- [ ] Error recovery and retry mechanisms
- [ ] Detailed error logging

---

## Priority Implementation Order

### High Priority (Core Functionality)
1. [ ] Multiple agents (General, Plan, Explore)
2. [ ] Config file support (opencode.jsonc)
3. [ ] Edit tool (partial file editing)
4. [ ] Theme system for TUI
5. [ ] Session list sidebar
6. [ ] Help dialog

### Medium Priority (Enhanced UX)
7. [ ] Keybinding customization
8. [ ] Toast notifications
9. [ ] Thinking/reasoning display toggle
10. [ ] Diff viewer in TUI
11. [ ] Multi-edit/patch tools
12. [ ] Web search implementation (Tavily/SerpAPI)

### Lower Priority (Advanced Features)
13. [ ] MCP integration
14. [ ] LSP integration
15. [ ] PTY support
16. [ ] Session sharing
17. [ ] Session compaction
18. [ ] Plugin system
19. [ ] Multiple AI provider support
20. [ ] IDE integrations

---

## Notes

### Key Architectural Differences

1. **Language Stack**: Our implementation uses Python (FastAPI) + Go (TUI), while OpenCode uses TypeScript/Bun throughout with React-based TUI (Ink).

2. **Agent System**: OpenCode has a sophisticated agent system with 4 built-in agents (general, build, plan, explore) with different permission levels. We have a single default agent.

3. **TUI Framework**: OpenCode uses Ink (React for CLI) while we use Bubbletea (Go). This affects how components are structured.

4. **Tool System**: OpenCode has a more extensive tool registry with Zod schema validation. Our tools are simpler Python async functions.

5. **Configuration**: OpenCode has comprehensive JSON config file support with deep merging. We primarily use environment variables.

### Implementation Recommendations

1. **Start with agents** - The multi-agent system is a key differentiator
2. **Add config file support** - Makes the system much more configurable
3. **Enhance TUI** - Themes and dialogs significantly improve UX
4. **Tool improvements** - Edit and patch tools are heavily used

### Files to Reference in OpenCode

- Agent system: `packages/opencode/src/agent/agent.ts`
- Tool definitions: `packages/opencode/src/tool/*.ts`
- Server routes: `packages/opencode/src/server/server.ts`
- TUI components: `packages/opencode/src/cli/cmd/tui/component/`
- Themes: `packages/opencode/src/cli/cmd/tui/context/theme/`
- Config: `packages/opencode/src/config/config.ts`
