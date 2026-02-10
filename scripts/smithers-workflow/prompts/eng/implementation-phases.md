# Implementation Phases

## 17. Phases

### Phase 0: Scaffold (1 session)
- New repo Ghostty structure
- Dirs: `src/` (Zig), `pkg/` (vendored C), `include/`, `macos/` (Swift), `web/` (SolidJS)
- `build.zig`: compile libsmithers stub → `include/libsmithers.h` → xcframework → Swift app → launch
- `macos/Smithers.xcodeproj` real Xcode (no Package.swift, no xcodegen)
- Init submodules `submodules/codex/`, `submodules/jj/` (EVMTS forks)
- Copy `GhosttyKit.xcframework` → `macos/`
- Vendor SQLite `pkg/sqlite/` + Zig build wrapper
- `include/libsmithers.h`: opaque types, action enum, callbacks
- `src/lib.zig`: CAPI block `smithers_app_new`, `smithers_app_free`, `smithers_app_action`
- `src/memory.zig`: arena helpers, lifetime patterns
- `src/storage.zig`: storage trait + SQLite impl
- `macos/Sources/Ghostty/SmithersCore.swift`: Unmanaged/callback pattern
- `macos/Sources/Ghostty/MockSmithersCore.swift`: mock for parallel UI dev
- Verify `zig build` passes (and `zig build dev` once wired) for empty app + libsmithers linked
- Verify `zig build test` and Swift tests (`xcodebuild test`, or `swift test` if SwiftPM exists) run (placeholder tests)

### Phase 1: Design system + window shell (2-3 sessions)
- `DesignSystem/`: tokens, AppTheme, shared components (IconButton, PrimaryButton, PillButton, Badge, Panel, SidebarListRow)
- `App/`: AppModel, WindowCoordinator, scenes (chat window + workspace panel)
- Chat window always present, workspace opens/closes/hides
- Frame persistence
- Bundled binaries load (codex-app-server, jj)
- Preferences model (UserDefaults, no UI)
- Verify: launch → themed chat, open/close workspace

### Phase 2: Chat window (3-4 sessions)
- `Models/`: ChatMessage, ChatSession, ChatModel
- `Views/Chat/`: sidebar (mode bar, sessions), detail (messages, composer, welcome)
- `Services/`: CodexService (in-process), JSONRPCTransport (non-Codex), SuggestionService
- Wire: send → CodexService → stream → ChatModel → render
- Chat history persistence
- Bubbles: user, assistant, command, diff preview, status, starter
- AI welcome suggestions (workspace-aware / generic)
- Image paste/drop + fullscreen viewer
- Hover action bar
- Verify: full chat e2e (with/without workspace)

### Phase 3: Workspace — file tree + editor (3-4 sessions)
- `Models/`: FileItem, TabItem, EditorViewState, FileTreeModel, TabModel, EditorStateModel
- `Editor/`: CodeEditorView, MultiCursorTextView, TreeSitterHighlighter, overlays (cursors, ghost, scrollbar, indent, brackets)
- `Views/IDE/`: FileTreeSidebar, IDETabBar, BreadcrumbBar, IDEContentArea, IDEStatusBar
- `Services/SearchService`
- Wire: open folder → tree → select → editor + highlight → save
- Tabs: open, close, reorder, context
- Command palette (Cmd+P), search (Cmd+Shift+F), shortcuts (Cmd+/)
- Verify: IDE e2e — open, browse, edit, save

### Phase 4: Cross-window (1-2 sessions)
- `showInEditor()`: chat "Open" → workspace opens file@line
- AI changes → diff in chat + optional auto-open workspace
- `SmithersCtlInterpreter` wired
- IPC server (Unix socket)
- SmithersCLI target
- Verify: AI change → diff → click → workspace scrolls

### Phase 5: Terminal (1-2 sessions)
- `Terminal/`: GhosttyApp, GhosttyTerminalView, GhosttyInput, GhosttyFrameScheduler
- Terminal tabs in workspace
- Terminal from chat (smithers-ctl)
- Verify: open tab, run, shell works

### Phase 6: Neovim (2-3 sessions)
- `Neovim/`: NvimController, NvimRPC
- NvimExtUIOverlay (cmdline, popup, messages, floats)
- Bidirectional buffer sync, theme derivation, crash recovery
- Verify: toggle, edit, save, switch, theme syncs

### Phase 7: JJ + agents (2-3 sessions)
- `Services/`: JJService, JJSnapshotStore, CommitStyleDetector, AgentOrchestrator
- `Models/`: JJ, Agent, multi-workspace
- JJ panel sidebar (working copy, log, bookmarks, ops, snapshots)
- Agent dashboard sidebar
- Auto-snapshot post-AI, revert from chat
- Verify: VCS status, snapshots, spawn agents

### Phase 8: Skills + settings + polish (2-3 sessions)
- Skills: scanner, registry, installer, views
- SettingsView all categories
- Toast, progress bar, close guards (tab/window/app)
- Tmux handler, update (Sparkle), diff viewer (tabs + sheets), light theme
- Verify: v1 feature parity

### Phase 9: Zig core (parallel 1-8)
Parallel with Swift. **TDD** — `zig build test` coverage before Swift hooks up.

**Priority** (portable → UI-coupled):
1. `src/memory.zig` — arena helpers, lifetimes, owned-return
2. `src/storage.zig` — trait + SQLite (`pkg/sqlite/`). Critical — Codex fork depends on it.
3. `src/codex_client.zig` — in-process Codex Zig API. Mock-tested.
4. `src/orchestrator.zig` — chat delegation, MCP dispatch
5. `src/mcp_server.zig` — Codex ↔ IDE bridge
6. `src/agent.zig` — sub-agent lifecycle, arena-per-agent
7. `src/jj.zig` — CLI wrapper, JSON parse. Mock output tests.
8. `src/chat_state.zig` — session state, routing
9. `src/http_server.zig` — HTTP/WS for web app
10. `src/scheduler.zig` — cron-like bg agent runner
11. `src/search.zig` — ripgrep wrapper
12. `src/file_watcher.zig` — FSEvents (macOS)
13. `src/suggestion.zig` — AI suggestion gen
14. `src/snapshot.zig` — JJ snapshot mgmt
15. `src/ipc.zig` — smithers-ctl protocol

**TDD:** Zig → tests → C header → Swift bridge → verify vs mock. Swift uses `MockSmithersCore` until real ready.

### Phase 10: Test + a11y + perf (2-3 sessions)
- Mock/replay infra (MockJSONRPCTransport for external providers, Codex stubs/fixtures)
- Unit tests all models/services
- XCUITests both windows (replay)
- A11y identifiers, labels, tooltips (enterprise req)
- Logging (os_log), perf (os_signpost)
- Instruments: view invalidations, leaks, slow highlighting
- Optimize: chat streaming (append-only, no full re-parse), file tree (virtualize large)
- Verify: tests pass, VoiceOver, no v1 regressions
