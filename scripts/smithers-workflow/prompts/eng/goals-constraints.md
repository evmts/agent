# Goals & Constraints

## 1.1 What v2 Solves

v1 has single 7,100-line `WorkspaceState` god object owning all state (files, editor, chat, terminals, VCS, themes, search, UI chrome). 2,500-line `ContentView` contains editor `NSViewRepresentable`, tab bar, breadcrumbs, status bar, overlays. One target, no module boundaries → theme change recompiles entire app.

v2 fixes:

1. **Files split for findability, not isolation** — NOT eliminating god object. Single centralized state tree (Flux-style) = fine, desirable. Fix: v1's 7,100-line files. v2 splits code into smaller domain-organized files. Xcode project with a flat dependency graph — no complex DAG. File needs import → import it. Don't overcomplicate.

2. **Composed state model** — Instead of massive class holding everything, top-level `AppModel` contains smaller sub-models: `ChatModel` (msgs/sessions), `FileTreeModel` (browser), `TabModel` (editor tabs), etc. Each ~100-250 lines, owns one domain. Navigable — understand chat → read `ChatModel`, not 7,000-line file. Compose into single god object (`AppModel`) — by design.

3. **Chrome DevTools window arch** — Main chat = "pane 0" (always present; closing hides to menu bar, does NOT quit). MVP uses two windows (chat + single workspace panel). Architecture should expand to multiple workspace panels later. Everything = tabs. Secondary window shows editor/terminal/diff/chat tabs. Windows positioned/resized/managed independently, share data via model layer.

4. **Workspace-optional** — Works without workspace. Launch → just chat, no folder needed. Create/open workspace via main agent or Cmd+Shift+O. Usually users open in workspace dir.

5. **Zig as logic layer (libghostty model)** — Ideal arch = libghostty pattern: Zig lib (`libsmithers`) handles business logic, Swift = thin UI syncing with it. Zig = source of truth (state, subprocess mgmt, agent orchestration, protocols). Swift observes Zig state, renders UI. Evaluated case-by-case — some stays Swift (UI-adjacent: scroll positions, animation), but default direction = push to Zig. Key reason: **cross-platform portability**. Smithers on Linux eventually → Zig core unchanged, only UI replatformed. See 2.6 for Zig ↔ Swift arch.

6. **Testability** — Models/services in own files with clear boundaries → unit tests run instantly with `swift test` (no simulator, no Xcode). Zig logic tested with `zig build test`. v1: testing service = import entire app.

## 1.2 Hard Constraints

### macOS 14+ (Sonoma) + `@Observable` Macro

Target macOS 14 (Sonoma) min. Important: macOS 14 introduced **Observation framework** with `@Observable` macro — fundamentally better than old approach.

**Background — SwiftUI updates:**

SwiftUI = declarative. Describe UI given data, SwiftUI figures out changes, re-renders affected parts. Critical: how does SwiftUI know data changed?

**Old way (v1): `ObservableObject` + `@Published` (Combine)**

```swift
class WorkspaceState: ObservableObject {
    @Published var editorText: String = ""
    @Published var chatMessages: [ChatMessage] = []
    @Published var selectedFileURL: URL?
    // ... 100+ @Published properties
}
```

Problem: when ANY `@Published` changes, SwiftUI re-evaluates EVERY view observing object. `chatMessages` changes → editor (only reads `editorText`) still re-evaluated. 100+ published props on one object = constant unnecessary work.

**New way (v2): `@Observable` macro (Observation framework)**

```swift
@Observable
class WorkspaceModel {
    var editorText: String = ""
    var chatMessages: [ChatMessage] = []
    var selectedFileURL: URL?
}
```

`@Observable` → SwiftUI tracks which specific props each view reads during last render. View only reads `editorText` → ONLY re-renders when `editorText` changes, not `chatMessages`. *Fine-grained observation* — dramatically more efficient.

Simpler syntax: no `@Published` wrapper, just plain `var`. `@Observable` macro generates tracking at compile time.

### Other Constraints

- **Same features as v1:** editor with TreeSitter syntax, Ghostty terminal, Neovim modal editing, JJ version control, Codex AI chat, skills plugins, agent orchestration (parallel AI workers), command palette, workspace search, diff viewer.
- **JJ bundled.** `jj` binary built + included in `.app` bundle. Users don't install separately — Smithers ships it. Hard dependency: agent orchestration, snapshot system, VCS UI all depend on jj.
- **TUI-native interaction.** Native GUI must feel familiar to TUI users: terminal one keystroke away (Ctrl+A c or Cmd+`), Neovim mode for editing, all actions have keyboard shortcuts, Tmux-compat prefix keys, no mouse required for core workflows. GUI adds value via visual diff review, multi-agent dashboards, quad-pane layouts, parallel workspace mgmt — not replacing terminal.
- **Native macOS:** Standard window chrome (traffic lights), standard keyboard shortcuts (Cmd+S, Cmd+C, etc.), proper window mgmt (resize, minimize, fullscreen), focus rings, right-click context menus, drag-drop.
- **Bundled binaries (shipped inside `.app`):**
  - **GhosttyKit** — Terminal = C lib (Zig, compiled to C-compat framework). Pre-built `.xcframework` (Apple format for pre-compiled libs). Swift calls Ghostty C functions via C interop (FFI).
  - **codex-app-server** — Small fork of OpenAI Codex (Rust binary, git submodule in EVMTS org). Fork wraps Codex in **Zig API** — ONLY thing it does. libsmithers calls Zig API directly (no JSON-RPC, no child process). Storage handlers (SQLite) passed as callbacks. Built from source by `build.zig`, linked as static lib into libsmithers.
  - **jj** — Jujutsu VCS binary. Pre-built, copied into `Contents/MacOS/` during build. Located at runtime via `Bundle.main.path(forAuxiliaryExecutable: "jj")`. JJService always uses bundled binary, never user's PATH version.

## 1.3 Non-Goals

Explicitly NOT doing in v2 (scope mgmt):

- **Cross-platform (iOS, Linux) — deferred, not abandoned.** v2 ships macOS-only. SwiftUI technically supports iOS, but heavy AppKit interop (native macOS UI framework) for editor/terminal has no iOS equivalent. **However**, cross-platform (esp Linux) = explicit future goal. Why libsmithers in Zig — Zig core fully portable. Smithers on Linux → only UI replatformed; entire Zig business logic unchanged. Architect libsmithers with portability in mind.
- **Rewriting Ghostty or Neovim.** Wrap as black boxes. Manage lifecycle (start, stop, communicate), don't modify internals. (Note: codex-app-server IS forked — only for Zig API wrapper + storage callbacks. Codex internals not rewritten.)
- **LSP integration (Language Server Protocol).** Powers "go to definition", "find references", rich autocompletion in VS Code. Deferred to v2.1+ — large subsystem, can be added non-disruptively later.
- **Native git support.** Use jj exclusively. jj "colocated" mode maintains `.git` alongside `.jj` → users can `git push`/`pull` through jj. No separate git integration needed.
- **Custom font bundling.** Use system monospace (SF Mono on macOS) + system UI font (SF Pro). No font files shipped.

## 1.3.1 Features from Issues Directory

`issues/` contains feature specs from v1 arch. **Take feature descriptions literally, NOT implementation details** — stale, based on old arch. v2 impl follows this spec.

**MVP features (from issues):**
- **007** — Background + scheduled agents (tab-based agents, cron schedules)
- **004** — Claude Code / OpenCode integration (multiple agent backends, not just Codex)

**Post-MVP:**
- **038** — Multi-workspace + Conductor parity (workspace switcher, cross-workspace search)
- **039** — Workflow Studio (Bun workflow engine, AI-powered workflow creation)
- **020** — Workspace tools sidebar panels (buffer list, markdown preview, search results)
- **013** — MiniApps (local-first web apps with JS bridge to Smithers SDK)
- **010** — Telegram agent bridge (mobile access to coding agents)
- **033** — Remote development (SSH/TCP Neovim sessions)

**Explicitly NOT MVP:**
- JJ merge queue UI (agent work merges via simple jj ops, no dedicated queue view)
- MiniApps
- Multi-workspace
- Remote development

## 1.4 Key Terminology

| Term | Meaning |
|------|---------|
| **SwiftUI** | Apple's declarative UI framework (React for macOS/iOS). Describe views as function of state, framework handles render/updates. |
| **AppKit** | Older imperative macOS UI framework. Needed for things SwiftUI can't do well (custom text editors, terminal rendering). SwiftUI embeds AppKit via `NSViewRepresentable`. |
| **NSViewRepresentable** | SwiftUI protocol wrapping AppKit `NSView` for use in SwiftUI layouts. `Coordinator` object = bridge between SwiftUI declarative world + AppKit delegate-based world. |
| **NSWindow** | Native macOS window object. Each on-screen window = one `NSWindow`. Two: main chat (pane 0), workspace panel. Tabs can detach into additional windows. |
| **@MainActor** | Swift annotation ensuring code runs on main thread (UI thread). All UI updates on main thread. Background work (file I/O, network, process spawn) on other threads, dispatch results to `@MainActor`. |
| **async/await** | Swift structured concurrency. `async` functions can pause (e.g., wait for network) without blocking thread. `await` marks pause point. `Task { }` creates concurrent work unit. `Task.detached { }` creates one not inheriting current actor context (for blocking work off main thread). |
| **SPM (Swift Package Manager)** | Swift's built-in dependency mgr + build system (like npm/cargo). Config via `Package.swift`. Defines targets (libs/executables), source dirs, dependencies on other targets/external packages. |
| **xcodegen** | Generates Xcode project files (`.xcodeproj`) from YAML config (`project.yml`). Needed because SPM alone can't define XCUITest targets (Apple's UI testing requires Xcode project). |
| **xcframework** | Apple format for distributing pre-compiled libs across architectures (Intel + Apple Silicon). GhosttyKit distributed this way. |
| **TreeSitter** | Parser generator producing fast, incremental parsers. Syntax highlighting — parses code into syntax tree, map nodes to colors. Each language (Swift, Python, JS, etc.) has own TreeSitter grammar. |
| **FFI (Foreign Function Interface)** | Calling functions written in one language from another. Call Ghostty C functions from Swift, Neovim MessagePack RPC from Swift. |
| **JSON-RPC** | Protocol for remote procedure calls using JSON. For communication with secondary agent backends (Claude Code, OpenCode). Primary Codex integration = in-process via Zig API (no JSON-RPC). |
| **MessagePack RPC** | Like JSON-RPC but uses MessagePack (binary serialization, like compressed JSON) instead of text JSON. Neovim's native protocol. |
| **Sendable** | Swift protocol marking type as safe to pass between concurrent threads. Value types (structs, enums) usually auto-Sendable. Ref types (classes) need explicit thread-safety. |
| **UserDefaults** | macOS built-in key-value storage for app preferences. Simple, persistent across launches, only for small data (settings, window positions). Not for large data (chat history). |
| **libsmithers** | Zig core lib. Contains business logic, agent orchestration, protocol handling. Swift calls via C FFI. Follows libghostty pattern. |
| **Zig** | Systems programming language with no runtime, no GC, C-compatible ABI. Portable logic layer (like libghostty). Compiles to any target → future cross-platform support. |
| **C FFI** | Interface between Swift + Zig. Zig exposes C-compat functions Swift calls directly. State change notifications via callback function pointers with opaque `userdata` pointers (GhosttyKit pattern). |
| **Orchestrator** | Main chat's role. Answers simple questions directly (via MCP tools to read state), primarily delegates work tasks to sub-agents. Has full app state context, coordinates everything. All async — delegate fast, respond immediately, process results as they come. |
| **Sub-agent** | Ephemeral CodexService instance spawned by orchestrator for specific task. Appears as `.chat` tab in workspace panel. Has own jj workspace branch. |
