# Migration & Reference

## 16. Migration & Reference

### 16.0 v1 location

`../smithers/apps/desktop/` — ~92 Swift files, ~31K LOC:

- **Chat/AI** (`CodexService.swift`, `ChatView.swift`, `ChatHistoryStore.swift`) — v1 JSON-RPC stdio; v2 in-process Zig. JSONRPCTransport remains only for non-Codex providers. Study event patterns, rendering.
- **Agent orchestration** (`AgentOrchestrator.swift`) — parallel jj workspaces, merge queue
- **JJ** (`JJService.swift`, `JJPanelView.swift`, `JJSnapshotStore.swift`) — VCS panel, snapshots
- **Terminal/Ghostty** (`GhosttyApp.swift`, `GhosttyTerminalView.swift`) — C FFI singleton, surface lifecycle, frame scheduling
- **Neovim** (`NvimController.swift`, `NvimRPC.swift`) — MessagePack RPC, buffer sync, ext UI
- **Editor** (`MultiCursorTextView.swift`, `SyntaxHighlighting.swift`) — STTextView, TreeSitter
- **Skills** (`SkillScanner.swift`, views) — discovery, activation, wizard
- **IPC** (`SmithersCtlInterpreter.swift`, `SmithersIPCServer.swift`) — Unix socket, parsing

v1: 7.1K-line `WorkspaceState` god object, 2.5K-line `ContentView`. v2 decomposes. Services/integrations = excellent reference. **Study patterns, don't copy-paste.**

### 16.1 v1 study guide

Reference (not copy-paste) patterns:

| v1 | Study | v2 |
|---|---|---|
| `GhosttyApp.swift` | C FFI singleton, callbacks, tick sched | `Terminal/GhosttyApp.swift` |
| `GhosttyTerminalView.swift` | NSView lifecycle, userdata, frame sched | `Terminal/GhosttyTerminalView.swift` |
| `GhosttyInput.swift` | Key map, Option-as-Meta | `Terminal/GhosttyInput.swift` |
| `NvimRPC.swift` | MessagePack codec | `Neovim/NvimRPC.swift` |
| `NvimController.swift` | Socket RPC, UI attach, autocmd | `Neovim/NvimController.swift` |
| `JSONRPCTransport.swift` | Pipe JSON-RPC, correlation, async | `Services/JSONRPCTransport.swift` (external providers). Codex uses `src/codex_client.zig` (in-process Zig API). |
| `CodexService.swift` | Events, threads, notifications | `Services/CodexService.swift` → `src/orchestrator.zig` |
| `SmithersCtlInterpreter.swift` | Parsing, vim +line:col | `Services/SmithersCtlInterpreter.swift` |
| `SyntaxHighlighting.swift` | TreeSitter pipeline, cancellation, registry | `Editor/TreeSitterHighlighter.swift` |
| `ContentView.swift` (editor) | STTextView NSViewRep, Coordinator, state | `Editor/CodeEditorView.swift` |
| `MultiCursorTextView.swift` | STTextView subclass, multi-cursor undo | `Editor/MultiCursorTextView.swift` |
| `GhostTextOverlayView.swift` | NSView overlay, NSLayoutManager | `Editor/GhostTextOverlayView.swift` |
| `ScrollbarOverlayView.swift` | Custom NSView scrollbar, drawing, hit test | `Editor/ScrollbarOverlayView.swift` |
| `JJService.swift` | CLI invoke, template JSON parse | `Services/JJService.swift` → `src/jj.zig` |
| `JJSnapshotStore.swift` | GRDB, migration, async | `Services/JJSnapshotStore.swift` |
| `SmithersIPCServer.swift` | NWListener socket, wait-close | `Services/IPCServer.swift` |
| `CloseGuard.swift` | NSWindowDelegate, async confirm, bypass | `App/CloseGuard.swift` |
| `WindowFrameStore.swift` | Per-workspace frame, screen adjust | `Services/WindowFrameStore.swift` |
| `AppTheme.swift` | Theme, hex parse, Neovim derive | `DesignSystem/Theme/AppTheme.swift` |
| `ChatHistoryStore.swift` | SHA256 hash, image storage, version | `Services/ChatHistoryStore.swift` |

### 16.2 NOT carry forward

- **WorkspaceState.swift** — 7.1K-line god object. Decompose → AppModel + WorkspaceModel + sub-models. (God object pattern OK, 7K-line file not.)
- **ContentView.swift** — 2.5K monolith. Split → IDEWorkspaceDetailView, CodeEditorView, IDETabBar, BreadcrumbBar, IDEStatusBar.
- **`ObservableObject` + `@Published`** → replaced `@Observable`.
- **Single-window** → multi-window scene-based (Chrome DevTools style).
- **SmithersShared compiled both targets** → v2 shared in `macos/Sources/`, single Xcode target. Zig core handles logic.
- **Hardcoded welcome** → AI-generated workspace-aware (`SuggestionService`).
- **External binaries** — v1 PATH lookup. v2 builds codex-app-server, jj from source (submodules), bundles in `.app`. Users install Smithers only.

---

## 18. v1 Features (297 commits, ~250 features)

Under-specified features from v1 audit (others covered earlier):

### 18.1 Auto-update
Sparkle `SPUStandardUpdaterController` → `UpdateController.swift`. Channels: Release/Snapshot enum `UpdateChannel` (UserDefaults) → feed URL. Manual "Check for Updates..." menu. Feed URL per-channel Info.plist, Snapshot = pre-release.

### 18.2 URL schemes
`smithers://`, `smithers-open-file://`, `smithers-chat://` registered Info.plist. External opens (Finder, CLI, URL) → `ExternalOpenRequest` batch. Pending queue if pre-workspace, process on load. Workspace root inferred from file hierarchy.

### 18.3 File ops
Create file/folder (tree context). Rename inline. Delete → Trash (not permanent). Non-UTF-8 detection → read-only placeholder, no save/auto-save.

### 18.4 Auto-save
Intervals: 5s, 10s, 30s. Toggle prefs. Toast on save. Guard: never non-UTF-8.

### 18.5 Session persist
Tabs + selected + sidebar widths per workspace. Terminal state across restarts. Last workspace on launch. Chat session ID → thread resume. Editor state (scroll, selection) per file. Shortcuts panel visibility. Sidebar mode (Chats/Source/Agents). Debounced on changes, explicit on close.

### 18.6 Perf monitor (debug)
`PerformanceMonitor` singleton: FPS, frame, render, highlight, glyph cache. `PerformanceOverlayView` debug HUD. Log JSON. Toggle prefs (debug only). Instrumented: highlight, Ghostty render, glyph cache.

### 18.7 Pinch-zoom
Editor magnification gesture, live preview, temp font size adjust.

### 18.8 Press-hold disable
`PressAndHoldDisabler` — disable macOS accent popup → key repeat works (editor/terminal). Required vim nav.
