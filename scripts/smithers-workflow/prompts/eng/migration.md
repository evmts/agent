# Migration & Reference Code / Features from v1 Git History Audit

## 16. Migration & Reference Code

### 16.0 v1 reference codebase location

The v1 Smithers desktop app lives at **`../smithers/apps/desktop/`** (relative to this repo root). It contains ~92 Swift files and ~31K LOC with working implementations of:

- **Chat + AI integration** (`CodexService.swift`, `ChatView.swift`, `ChatHistoryStore.swift`) — v1 used JSON-RPC over stdio; v2 uses in-process Zig API. Study event patterns and message rendering.
- **Agent orchestration** (`AgentOrchestrator.swift`) — parallel agent workspaces via jj, merge queue
- **JJ version control** (`JJService.swift`, `JJPanelView.swift`, `JJSnapshotStore.swift`) — full VCS panel, snapshot persistence
- **Terminal/Ghostty** (`GhosttyApp.swift`, `GhosttyTerminalView.swift`) — C FFI singleton, surface lifecycle, frame scheduling
- **Neovim** (`NvimController.swift`, `NvimRPC.swift`) — MessagePack RPC, bidirectional buffer sync, ext UI overlays
- **Editor** (`MultiCursorTextView.swift`, `SyntaxHighlighting.swift`) — STTextView, TreeSitter pipeline
- **Skills** (`SkillScanner.swift`, skill UI views) — discovery, activation, creation wizard
- **IPC** (`SmithersCtlInterpreter.swift`, `SmithersIPCServer.swift`) — Unix socket, command parsing

The v1 architecture uses a single 7,100-line `WorkspaceState` god object and a 2,500-line `ContentView`. v2 decomposes these, but the individual service/integration implementations are excellent reference code. **Study the patterns, don't copy-paste.**

### 16.1 Code to study from v1

These v1 files contain implementation patterns that should be understood and referenced (not copy-pasted) when building v2:

| v1 File | What to study | v2 Target |
|---------|---------------|-----------|
| `GhosttyApp.swift` | C FFI singleton, callback pattern, tick scheduling | `Terminal/GhosttyApp.swift` |
| `GhosttyTerminalView.swift` | NSView surface lifecycle, userdata pattern, frame scheduler | `Terminal/GhosttyTerminalView.swift` |
| `GhosttyInput.swift` | Key mapping, Option-as-Meta translation | `Terminal/GhosttyInput.swift` |
| `NvimRPC.swift` | MessagePack encoder/decoder | `Neovim/NvimRPC.swift` |
| `NvimController.swift` | Socket RPC, UI attachment, autocmd installation | `Neovim/NvimController.swift` |
| `JSONRPCTransport.swift` | Pipe-based JSON-RPC, request/response correlation, async streams | `Services/JSONRPCTransport.swift` → eventually `src/codex_client.zig` |
| `CodexService.swift` | Event types, thread management, notification routing | `Services/CodexService.swift` → eventually `src/orchestrator.zig` |
| `SmithersCtlInterpreter.swift` | Command parsing, vim-style +line:col | `Services/SmithersCtlInterpreter.swift` |
| `SyntaxHighlighting.swift` | TreeSitter pipeline, requestID cancellation, language registry | `Editor/TreeSitterHighlighter.swift` |
| `ContentView.swift` (CodeEditor) | STTextView NSViewRepresentable, Coordinator pattern, view state save/restore | `Editor/CodeEditorView.swift` |
| `MultiCursorTextView.swift` | STTextView subclass, multi-cursor undo grouping | `Editor/MultiCursorTextView.swift` |
| `GhostTextOverlayView.swift` | NSView overlay, NSLayoutManager text layout | `Editor/GhostTextOverlayView.swift` |
| `ScrollbarOverlayView.swift` | Custom NSView scrollbar, knob drawing, hit testing | `Editor/ScrollbarOverlayView.swift` |
| `JJService.swift` | jj CLI invocation, template-based JSON parsing | `Services/JJService.swift` → eventually `src/jj.zig` |
| `JJSnapshotStore.swift` | GRDB setup, migration, async wrappers | `Services/JJSnapshotStore.swift` |
| `SmithersIPCServer.swift` | NWListener socket server, wait-for-close pattern | `Services/IPCServer.swift` |
| `CloseGuard.swift` | NSWindowDelegate, async confirmation with bypass flag | `App/CloseGuard.swift` |
| `WindowFrameStore.swift` | Per-workspace frame persistence, screen adjustment | `Services/WindowFrameStore.swift` |
| `AppTheme.swift` | Theme struct, NSColor hex parsing, Neovim derivation | `DesignSystem/Theme/AppTheme.swift` |
| `ChatHistoryStore.swift` | SHA256 workspace hash, image storage, versioned format | `Services/ChatHistoryStore.swift` |

### 16.2 What NOT to carry forward

- **WorkspaceState.swift** — the 7,100-line god object. Decomposed into AppModel + WorkspaceModel + sub-models across multiple files. (The god object pattern is fine — the 7,100-line single file is not.)
- **ContentView.swift** — the 2,500-line monolith. Split into smaller view files: IDEWorkspaceDetailView, CodeEditorView, IDETabBar, BreadcrumbBar, IDEStatusBar.
- **`ObservableObject` + `@Published` pattern** — replaced by `@Observable`.
- **Single-window architecture** — replaced by Chrome DevTools-style multi-window with scene-based management.
- **SmithersShared compiled as sources in both targets** — in v2, shared code lives in `macos/Sources/` with a single Xcode app target. The Zig core (`libsmithers`) handles shared logic.
- **Hardcoded welcome screen suggestions** — replaced by AI-generated, workspace-aware suggestions via `SuggestionService`.
- **External binary dependencies** — v1 relied on PATH lookup for some tools. v2 builds `codex-app-server` and `jj` from source (git submodules) and bundles them inside the `.app` bundle. Users install nothing beyond Smithers itself.

---

## 18. Features from v1 Git History Audit

The following features were found in the v1 codebase (297 commits, ~250 features) and must be present in v2. Features already covered in earlier sections are not repeated here — this section captures features that were under-specified or missing.

### 18.1 Auto-update system
- **Sparkle integration** via `SPUStandardUpdaterController`. Ships in v2 via `UpdateController.swift`.
- **Update channels:** Release vs. Snapshot enum (`UpdateChannel`). Persisted to UserDefaults. Changes which feed URL is checked.
- **Manual check:** "Check for Updates..." menu item.
- **Feed URL:** Configured per-channel in Info.plist. Snapshot channel may include pre-release builds.

### 18.2 URL scheme deep linking
- **`smithers://` and `smithers-open-file://`** URL schemes registered in Info.plist.
- **`smithers-chat://`** scheme for opening specific chat sessions.
- **External file opening:** Finder, CLI, and URL scheme all funnel through `ExternalOpenRequest` with batch support.
- **Pending URL queue:** If files are opened before workspace is ready, they queue and process once workspace loads.
- **Workspace root inference:** When opening a file, infer the workspace root from the file's directory hierarchy.

### 18.3 File operations (CRUD)
- **Create file/folder** from file tree context menu.
- **Rename file/folder** with inline text field.
- **Delete to Trash** (not permanent delete) from context menu.
- **Non-UTF-8 file detection:** Read-only placeholder display. Prevents saving/auto-saving non-UTF-8 files.

### 18.4 Auto-save
- **Configurable interval:** 5s, 10s, 30s options.
- **Toggle on/off** in preferences.
- **Toast notification** on auto-save.
- **Guard:** Never auto-saves non-UTF-8 files.

### 18.5 Session persistence (full)
- **Open tabs + selected tab + sidebar widths** saved per workspace.
- **Terminal state** preserved across restarts.
- **Last opened workspace** restored on launch.
- **Chat session ID** persisted for thread resume.
- **Editor view state** (scroll position, selection range) per file.
- **Shortcuts panel visibility** persisted.
- **Sidebar mode** (Chats/Source/Agents) persisted.
- **Debounced persistence** on tab/selection changes. Explicit save on window/app close.

### 18.6 Performance monitoring (debug)
- **PerformanceMonitor** singleton tracks FPS, frame time, render time, syntax highlight time, glyph cache hits/misses.
- **PerformanceOverlayView** — debug HUD displaying live metrics.
- **Performance logging** to file with JSON encoding.
- **Toggle** via preferences (debug builds only).
- **Instrumented points:** syntax highlighting, Ghostty render calls, glyph frame cache.

### 18.7 Pinch-to-zoom
- **Editor magnification gesture** with live preview. Adjusts font size temporarily.

### 18.8 Press-and-hold disable
- **`PressAndHoldDisabler`** — disables macOS press-and-hold accent popup so key repeat works in the editor and terminal. Required for vim-style navigation.
