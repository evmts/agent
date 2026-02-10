# Smithers v2 — Engineering Specification

## Chat-First, TUI-Native macOS IDE

**Goal: Build the ultimate UX for agentic coding that evolves from TUI to GUI.**

This document specifies the complete engineering architecture for Smithers v2, a ground-up rewrite as a native macOS IDE built in SwiftUI. The app is a native Swift GUI that *feels* like a TUI — keyboard first, one keystroke from a real terminal (via GhosttyKit), Neovim mode for file editing, tmux shortcuts everywhere — with a chat-first agentic approach. It covers repository structure, module decomposition, state management, window coordination, and implementation details for every subsystem. An engineering team should be able to build the app from this spec plus the companion design spec (`docs/design.md`) without ambiguity.

**Target platform:** macOS 14+ (Sonoma)
**UI layer:** Swift 5.10+ / SwiftUI / AppKit interop
**Logic layer:** Zig (business logic, state management, subprocess orchestration) — Swift syncs with Zig
**Design reference:** `docs/design.md`
**UI prototype:** `prototype/` (Next.js + TypeScript + shadcn/ui prototype — reference for layout, colors, component structure). Also available live at: https://v0.app/chat/mac-os-ide-prototype-cEqmBbcomU7
**v1 reference code:** `../smithers/apps/desktop/` (read-only reference, not imported — contains ~92 Swift files, ~31K LOC with working implementations of chat, agents, JJ, terminal/Ghostty, Neovim, editor, skills, and all major features. Architecture has been significantly improved for v2 but v1 has useful implementation patterns.)

### Target user

Smithers targets **TUI-power-users who want a bit more** — people who already use Claude Code in a terminal and want a better harness, not VS Code users looking for an AI plugin. It's a native Swift/SwiftUI app — not a terminal app — but it's designed to *feel* like a terminal. The terminal is always one keystroke away (via GhosttyKit embedded terminal surfaces), keyboard navigation is first-class, Tmux-compatible prefix keys work everywhere, and Neovim mode makes file editing feel like vim. The GUI exists as a **harness** that makes complex workflows possible — orchestrating multiple agents, visual diff review, quad-pane layouts, long-running parallel tasks — things that are painful in a raw terminal. We're iterating on Claude Code via GUI without throwing the baby out with the bathwater.

Think of it as **Chrome DevTools for AI coding**: the main chat is pane 0 (always there), and workspace panels can attach/detach as secondary windows. Not just "chat + IDE" but "main chat + N workspace panels."

---

## 1. Goals & Constraints

### 1.1 What v2 solves

v1 has a single 7,100-line `WorkspaceState` god object that owns all app state — files, editor, chat, terminals, VCS, themes, search, and UI chrome. A 2,500-line `ContentView` contains the editor's `NSViewRepresentable`, tab bar, breadcrumbs, status bar, and overlays. Everything compiles as one target with no module boundaries, meaning a change to the theme system recompiles the entire app.

v2 fixes this with:

1. **Files split for findability, not strict isolation** — We are NOT trying to eliminate the god object pattern. A single, centralized state tree (Flux-style) is fine and actually desirable. What we're fixing is that v1's `WorkspaceState.swift` is 7,100 lines in one file, and `ContentView.swift` is 2,500 lines in one file. v2 splits code into smaller files organized by domain so you can find things easily. The codebase uses SPM targets for basic build structure, but the dependency graph is intentionally flat and simple — not a complex DAG of isolated modules. If a file needs to import something, it imports it. Don't make it complicated.

2. **Composed state model** — Instead of one massive class that holds every piece of state in the app, we have a top-level `AppModel` that contains smaller, focused sub-models: `ChatModel` (chat messages and sessions), `FileTreeModel` (the file browser), `TabModel` (open editor tabs), etc. Each sub-model is ~100-250 lines and owns exactly one domain. This makes the code navigable — when you need to understand how chat works, you read `ChatModel`, not a 7,000-line file. But they all compose into a single god object (`AppModel`) — and that's by design.

3. **Chrome DevTools window architecture** — The app follows a Chrome DevTools-style model. The main chat is "pane 0" — always present, closing it quits the app. Workspace panels (editor, terminal, diff viewer, etc.) can attach/detach as secondary windows. It's not a rigid "two windows" system — it's "main chat + N workspace panels" where panels are grouped by workspace. Everything is tabs. The second window can show a chat, a diff, an IDE tab, anything. Windows can be positioned, resized, and managed independently, but they share the same underlying data through the model layer.

4. **Workspace-optional** — The app works without a workspace open. You can launch Smithers and just chat — no folder needed. Creating or opening a workspace can happen by talking to the main agent, or via Cmd+Shift+O. But most of the time, users will open the app in a workspace directory.

5. **Zig as the logic layer (libghostty model)** — The ideal architecture follows the same pattern as **libghostty**: a Zig library (`libsmithers`) handles business logic, and Swift is a thin UI layer that syncs with it. Zig is the source of truth for state, subprocess management, agent orchestration, and protocol handling. Swift observes Zig's state and renders the UI. This is evaluated case-by-case — some things make sense to stay in Swift (especially UI-adjacent state like scroll positions and animation), but the default direction is to push logic into Zig. The key reason: **cross-platform portability**. When Smithers eventually ships on Linux, the Zig core stays unchanged — only the UI layer is replatformed. See Section 2.6 for the full Zig ↔ Swift architecture.

6. **Testability** — Because models and services are in their own files with clear boundaries, we can write unit tests that run instantly with `swift test` (no simulator, no Xcode project needed). Zig logic is tested independently with `zig build test`. In v1, testing a service meant importing the entire app.

### 1.2 Hard constraints

#### macOS 14+ (Sonoma) and the `@Observable` macro

We target macOS 14 (Sonoma) as the minimum OS version. This is important because macOS 14 introduced the **Observation framework** with the `@Observable` macro, which is a fundamentally better way to connect data to UI than the older approach.

**Background — how SwiftUI updates the screen:**

SwiftUI is a *declarative* UI framework. You describe what the UI should look like given some data, and SwiftUI figures out what changed and re-renders only the affected parts. The critical question is: *how does SwiftUI know when data changed?*

**The old way (v1): `ObservableObject` + `@Published` (Combine framework)**

```swift
class WorkspaceState: ObservableObject {
    @Published var editorText: String = ""
    @Published var chatMessages: [ChatMessage] = []
    @Published var selectedFileURL: URL?
    // ... 100+ more @Published properties
}
```

The problem: when ANY `@Published` property changes, SwiftUI re-evaluates EVERY view that observes this object. So if `chatMessages` changes, the editor view (which only reads `editorText`) still gets re-evaluated. With 100+ published properties on one object, this causes constant unnecessary work.

**The new way (v2): `@Observable` macro (Observation framework)**

```swift
@Observable
class WorkspaceModel {
    var editorText: String = ""
    var chatMessages: [ChatMessage] = []
    var selectedFileURL: URL?
}
```

With `@Observable`, SwiftUI tracks which specific properties each view actually reads during its last render. If a view only reads `editorText`, it will ONLY re-render when `editorText` changes — not when `chatMessages` changes. This is called *fine-grained observation* and it's dramatically more efficient.

The syntax is also simpler: no `@Published` wrapper needed, just plain `var` properties. The `@Observable` macro generates the tracking code at compile time.

#### Other constraints

- **Same feature set as v1:** editor with TreeSitter syntax highlighting, Ghostty terminal emulator, Neovim modal editing mode, JJ version control integration, Codex AI chat, skills plugin system, agent orchestration (parallel AI workers), command palette, workspace-wide search, diff viewer.
- **JJ (Jujutsu) is bundled.** The `jj` binary is built and included inside the `.app` bundle. Users do not need to install jj separately — Smithers ships it. This is a hard dependency: the agent orchestration, snapshot system, and version control UI all depend on jj.
- **TUI-native interaction model.** The app is a native GUI that must feel familiar to TUI users: terminal is always one keystroke away (Ctrl+A c or Cmd+`), Neovim mode for file editing, all common actions have keyboard shortcuts, Tmux-compatible prefix keys, no mouse required for core workflows. The GUI adds value through visual diff review, multi-agent orchestration dashboards, quad-pane layouts, and parallel workspace management — not by replacing the terminal.
- **Native macOS behavior:** Standard macOS window chrome (the red/yellow/green "traffic light" buttons), standard keyboard shortcuts (Cmd+S, Cmd+C, etc.), proper window management (resize, minimize, fullscreen), focus rings on focused elements, right-click contextual menus, drag-and-drop.
- **Bundled binaries (all shipped inside the `.app` bundle):**
  - **GhosttyKit** — The terminal emulator is a C library (written in Zig, compiled to a C-compatible framework). We use a pre-built `.xcframework` (Apple's format for distributing pre-compiled libraries). Our Swift code calls Ghostty's C functions directly through Swift's C interop (called "FFI" — Foreign Function Interface).
  - **codex-app-server** — A **small fork of OpenAI's Codex** (Rust binary, git submodule in EVMTS org). The fork wraps the entire Codex in a **Zig API** — that's the only thing the fork does. libsmithers calls this Zig API directly (no JSON-RPC, no child process). Storage handlers (SQLite writes) are passed into the Zig API as callbacks. Built from source by `build.zig`, linked as a static library into libsmithers.
  - **jj** — The Jujutsu VCS binary. Pre-built and copied into `Contents/MacOS/` during the build. Located at runtime via `Bundle.main.path(forAuxiliaryExecutable: "jj")`. JJService always uses this bundled binary, never the user's PATH version.

### 1.3 Non-goals

These are things we are explicitly NOT doing in v2 to keep scope manageable:

- **Cross-platform (iOS, Linux) — deferred, not abandoned.** v2 ships macOS-only. SwiftUI technically supports iOS, but our app uses heavy AppKit interop (the native macOS UI framework) for the editor and terminal, which has no iOS equivalent. **However**, cross-platform (especially Linux) is an explicit future goal. This is why libsmithers is written in Zig — the Zig core is fully portable. When we ship on Linux, only the UI layer is replatformed; the entire Zig business logic layer stays unchanged. Architect all libsmithers code with this portability in mind.
- **Rewriting Ghostty or Neovim.** We wrap these external tools as black boxes. Our code manages their lifecycle (start, stop, communicate) but doesn't modify their internals. (Note: codex-app-server IS forked — but only to add a Zig API wrapper and storage callbacks. The Codex internals themselves are not rewritten.)
- **LSP integration (Language Server Protocol).** This is the protocol that powers features like "go to definition", "find references", and rich autocompletion in editors like VS Code. It's deferred to v2.1+ because it's a large subsystem that can be added non-disruptively later.
- **Native git support.** We use jj (Jujutsu) exclusively. jj has a "colocated" mode that maintains a `.git` directory alongside its own `.jj` directory, so users can still `git push` / `git pull` through jj. We don't need a separate git integration.
- **Custom font bundling.** We use the system monospace font (SF Mono on macOS) and system UI font (SF Pro). No need to ship font files.

### 1.3.1 Features from issues directory

The `issues/` directory contains feature specs originally written for the v1 architecture. **Take the feature descriptions literally but NOT the implementation details** — those are stale and based on the old architecture. Implementation for v2 follows this spec.

**MVP features (from issues):**
- **007** — Background and scheduled agents (tab-based agents, cron schedules)
- **004** — Claude Code / OpenCode integration (support multiple agent backends, not just Codex)

**Post-MVP features:**
- **038** — Multi-workspace + Conductor parity (workspace switcher, cross-workspace search)
- **039** — Workflow Studio (Bun workflow engine, AI-powered workflow creation)
- **020** — Workspace tools sidebar panels (buffer list, markdown preview, search results panel)
- **013** — MiniApps (local-first web apps with JS bridge to Smithers SDK)
- **010** — Telegram agent bridge (mobile access to coding agents)
- **033** — Remote development (SSH/TCP Neovim sessions)

**Explicitly NOT MVP:**
- JJ merge queue UI (agent work merges via simple jj operations, no dedicated queue view)
- MiniApps
- Multi-workspace
- Remote development

### 1.4 Key terminology

Terms used throughout this document:

| Term | What it means |
|------|---------------|
| **SwiftUI** | Apple's declarative UI framework (like React for macOS/iOS). You describe views as a function of state, and the framework handles rendering and updates. |
| **AppKit** | The older, imperative macOS UI framework. Still needed for things SwiftUI can't do well (custom text editors, terminal rendering). SwiftUI can embed AppKit views via `NSViewRepresentable`. |
| **NSViewRepresentable** | A SwiftUI protocol that wraps an AppKit `NSView` so it can be used inside SwiftUI layouts. Has a `Coordinator` object that acts as the bridge between SwiftUI's declarative world and AppKit's delegate-based world. |
| **NSWindow** | The native macOS window object. Each window on screen is one `NSWindow`. We have two: one for the main chat (pane 0), one for the workspace panel. Tabs can also be detached into additional windows. |
| **@MainActor** | A Swift annotation that ensures code runs on the main thread (the UI thread). All UI updates must happen on the main thread. Background work (file I/O, network calls, process spawning) happens on other threads and dispatches results back to `@MainActor`. |
| **async/await** | Swift's structured concurrency. `async` functions can pause (e.g., waiting for a network response) without blocking the thread. `await` marks the point where a function might pause. `Task { }` creates a new concurrent work unit. `Task.detached { }` creates one that doesn't inherit the current actor context (useful for running blocking work off the main thread). |
| **SPM (Swift Package Manager)** | Swift's built-in dependency manager and build system (like npm/cargo). Configured via `Package.swift`. Defines targets (libraries/executables), their source directories, and dependencies on other targets or external packages. |
| **xcodegen** | A tool that generates Xcode project files (`.xcodeproj`) from a YAML config (`project.yml`). We need this because SPM alone can't define XCUITest targets (Apple's UI testing framework requires an Xcode project). |
| **xcframework** | Apple's format for distributing pre-compiled libraries that work across architectures (Intel + Apple Silicon). GhosttyKit is distributed this way. |
| **TreeSitter** | A parser generator that produces fast, incremental parsers. We use it for syntax highlighting — it parses source code into a syntax tree, and we map tree nodes to colors. Each language (Swift, Python, JS, etc.) has its own TreeSitter grammar. |
| **FFI (Foreign Function Interface)** | Calling functions written in one language from another. We call Ghostty's C functions from Swift and Neovim's MessagePack RPC from Swift. |
| **JSON-RPC** | A protocol for remote procedure calls using JSON. Used for communication with secondary agent backends (Claude Code, OpenCode). The primary Codex integration is in-process via Zig API (no JSON-RPC). |
| **MessagePack RPC** | Similar to JSON-RPC but uses MessagePack (a binary serialization format, like compressed JSON) instead of text JSON. This is Neovim's native protocol. |
| **Sendable** | A Swift protocol that marks a type as safe to pass between concurrent threads. Value types (structs, enums) are usually automatically Sendable. Reference types (classes) need explicit thread-safety to be Sendable. |
| **UserDefaults** | macOS's built-in key-value storage for app preferences. Simple and persistent across app launches, but only suitable for small data (settings, window positions). Not for large data like chat history. |
| **libsmithers** | The Zig core library. Contains business logic, agent orchestration, protocol handling. Swift calls into it via C FFI. Follows the same pattern as libghostty. |
| **Zig** | A systems programming language with no runtime, no GC, and C-compatible ABI. We use it as the portable logic layer (like how Ghostty uses libghostty). Compiles to any target, enabling future cross-platform support. |
| **C FFI** | The interface between Swift and Zig. Zig exposes C-compatible functions that Swift calls directly. State change notifications flow back via callback function pointers with opaque `userdata` pointers (same pattern as GhosttyKit). |
| **Orchestrator** | The main chat's role. It can answer simple questions directly (using MCP tools to read state), but primarily delegates work tasks to sub-agents. It has full context of the app state and coordinates everything. Everything is async — delegate fast, respond immediately, process results as they come back. |
| **Sub-agent** | An ephemeral CodexService instance spawned by the orchestrator to handle a specific task. Appears as a `.chat` tab in the workspace panel. Has its own jj workspace branch. |
