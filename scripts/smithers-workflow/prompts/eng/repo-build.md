## 2. Repository & Build System

### 2.1 Repository structure

```
smithers/
├── build.zig                        # Build orchestrator — THE makefile. Builds EVERYTHING:
│                                    #   Zig core, vendored C deps, Rust submodules (Codex fork,
│                                    #   JJ fork), xcframework, Swift app, web app
├── build.zig.zon                    # Zig package manifest (dependencies)
├── AGENTS.md                        # Agent instructions for Codex (preferred over CLAUDE.md)
├── CLAUDE.md                        # Claude Code instructions (also read, lower priority)
├── docs/
│   ├── design.md                    # UI/UX specification
│   └── engineering.md               # Engineering specification (this file)
├── issues/                          # Post-MVP feature specs (numbered markdown files)
├── prototype/                       # Next.js UI prototype (reference for target look and feel)
├── include/
│   └── libsmithers.h               # C API header — THE contract between Zig and Swift
├── src/                             # Zig source (libsmithers — the logic layer)
│   ├── lib.zig                      # Root: exports C API (like ghostty's main.zig)
│   ├── orchestrator.zig             # Main chat orchestrator logic
│   ├── agent.zig                    # Sub-agent lifecycle management
│   ├── codex_client.zig             # Zig API client for in-process Codex library
│   ├── jj.zig                       # JJ CLI wrapper (spawns process, parses output)
│   ├── search.zig                   # Ripgrep wrapper for workspace search
│   ├── file_watcher.zig             # FSEvents wrapper (macOS) / inotify (Linux later)
│   ├── chat_state.zig               # Chat session state machine
│   ├── snapshot.zig                 # JJ snapshot management
│   ├── suggestion.zig               # AI-generated suggestion generation
│   ├── ipc.zig                      # IPC protocol (app ↔ smithers-ctl)
│   ├── mcp_server.zig              # MCP server for Codex orchestrator
│   ├── http_server.zig             # HTTP/WebSocket server for web app
│   ├── scheduler.zig               # Scheduled agent runner (cron-like)
│   ├── storage.zig                 # Storage trait + SQLite implementation
│   ├── memory.zig                   # Arena allocator helpers, lifetime patterns
│   └── models/                      # Shared data types (Zig structs → C structs → Swift)
├── pkg/                             # Vendored C/C++ dependencies with Zig build wrappers
│   ├── sqlite/                      # SQLite (vendored, built by Zig — used by storage.zig)
│   ├── zap/                         # Zap HTTP server (wraps facil.io — used by http_server.zig)
│   ├── tree-sitter/                 # TreeSitter core + grammar parsers (vendored, built by Zig)
│   │   └── grammars/              # Per-language grammar C sources + highlights.scm
│   └── macos/                       # macOS framework wrappers (like ghostty's pkg/macos/)
├── submodules/                      # Git submodules (Rust dependencies we fork + wrap with Zig)
│   ├── codex/                       # EVMTS fork of codex-app-server
│   │   ├── build.zig               # Zig build wrapper: cargo build → static lib → Zig API
│   │   └── ...                     # Codex Rust source (minimal fork: Zig API wrapper + storage callbacks)
│   └── jj/                          # EVMTS fork of Jujutsu (no code changes, just Zig wrapper)
│       ├── build.zig               # Zig build wrapper around `cargo build`
│       └── ...                     # JJ Rust source (unmodified)
├── macos/                           # macOS Swift application (follows Ghostty's macos/ pattern)
│   ├── Smithers.xcodeproj/         # Xcode project (maintained directly, no xcodegen)
│   ├── Smithers-Info.plist         # App bundle metadata
│   ├── Smithers.entitlements       # App sandbox/capabilities
│   ├── SmithersKit.xcframework/    # Pre-built libsmithers as xcframework (built by build.zig)
│   ├── GhosttyKit.xcframework/    # Pre-built Ghostty terminal framework
│   ├── Assets.xcassets/            # App icons and images
│   ├── Sources/
│   │   ├── App/                     # Entry point, scenes, window coordination
│   │   ├── Ghostty/                 # Core libsmithers Swift wrapper (like Ghostty's Ghostty/ dir)
│   │   │   └── SmithersCore.swift  # C FFI bridge: Swift ↔ libsmithers interop
│   │   ├── Features/               # Feature-based organization (like Ghostty's Features/)
│   │   │   ├── Chat/              # Chat window views + models
│   │   │   ├── IDE/                # Workspace panel views (file tree, tabs, editor wrapper)
│   │   │   ├── Terminal/           # Ghostty terminal integration
│   │   │   ├── Editor/             # STTextView wrapper, TreeSitter, cursors, ghost text
│   │   │   ├── Neovim/            # NvimController, RPC, overlays
│   │   │   ├── Agents/            # Agent dashboard, background agents
│   │   │   ├── Skills/            # Skills browser, activation, creation
│   │   │   ├── Settings/          # Preferences views
│   │   │   ├── Command Palette/   # Cmd+P fuzzy finder
│   │   │   ├── Search/            # Workspace search panel
│   │   │   └── Update/            # Sparkle auto-update
│   │   ├── Helpers/                # Utility code, extensions
│   │   │   ├── Extensions/        # Swift extensions
│   │   │   └── DesignSystem/      # Tokens, theme, shared UI components
│   │   └── Services/               # Swift service wrappers (thin layer over libsmithers C API)
│   ├── Tests/                      # Swift unit tests
│   └── SmithersUITests/            # XCUITest
├── web/                             # SolidJS web application (parallel to native app)
│   ├── package.json                # SolidJS + shadcn-solid + Tailwind CSS + Monaco editor
│   ├── src/
│   │   ├── index.tsx              # Entry point
│   │   ├── components/            # shadcn-solid UI components
│   │   ├── features/              # Feature-based (Chat, IDE, Agents, etc. — mirrors macos/)
│   │   ├── lib/                   # API client, WebSocket connection to libsmithers HTTP server
│   │   └── styles/                # Tailwind config, design tokens
│   └── public/
└── dist/                            # Distribution scripts, packaging, signing
```

**This mirrors the Ghostty pattern and extends it:**
- `src/` for the Zig core (like ghostty's `src/`)
- `pkg/` for vendored C/C++ deps with Zig build wrappers (like ghostty's `pkg/`)
- `include/` for the C API header (like ghostty's `include/`)
- `macos/` for the Swift app with a real Xcode project (like ghostty's `macos/`)
- `build.zig` orchestrates everything — it's THE makefile that builds the entire project
- `submodules/` for Rust dependencies we fork and wrap with Zig (codex, jj)
- `web/` for the SolidJS web application (talks to libsmithers via HTTP server)
- Feature-based organization in `macos/Sources/Features/` (like ghostty's `Features/`)

**No Package.swift.** Unlike the previous spec, we use a real Xcode project (`Smithers.xcodeproj`) directly — not SPM for the app target. SPM dependencies (like Sparkle) are managed by Xcode's built-in package resolution. This matches Ghostty's approach and avoids the friction of maintaining a `Package.swift` alongside an Xcode project.

**Vendor everything possible, wrap with Zig.**
- **C/C++ deps** go in `pkg/` with Zig build wrappers (SQLite, Zap/facil.io, TreeSitter, etc.).
- **Rust deps** we maintain as small forks in `submodules/` with Zig build wrappers that call `cargo build`. They are git submodules in the EVMTS GitHub org. `build.zig` builds them as part of the full build.
- **Swift deps** use Xcode's built-in SPM resolution (Sparkle, STTextView, GRDB.swift) — same approach as Ghostty uses for Sparkle.
- **Web deps** use standard npm/pnpm in `web/`.

The key pattern: **every dependency has a `build.zig` wrapper** so that `zig build dev` builds the entire project from source with one command.

**Note on the Zig → Swift migration path:** The MVP may start with more logic in Swift (since v1 is all Swift and we know it works). The `src/` Zig directory grows over time as we progressively migrate logic from `Services/` into `libsmithers`. The `Ghostty/` directory in `macos/Sources/` contains the Swift wrapper that calls into Zig via C FFI — this layer gets thinner as more logic moves to Zig.

**Feature-based Swift organization:** Following Ghostty's pattern, Swift code is organized by feature in `macos/Sources/Features/`. Each feature directory contains everything it needs — views, models, view models — rather than splitting by architectural layer. This makes features findable: when you need to understand how chat works, you look in `Features/Chat/`.

### 2.2 Xcode project (no Package.swift)

Following Ghostty's approach, we use a real Xcode project (`macos/Smithers.xcodeproj`) directly — not SPM for the app target. This avoids the friction of maintaining a `Package.swift` alongside an Xcode project and matches the proven Ghostty pattern.

**Swift dependencies managed by Xcode's SPM integration:**
- **Sparkle** — auto-update framework (binary xcframework, fetched by Xcode)
- **STTextView** — text editor component
- **GRDB.swift** — SQLite database layer

**TreeSitter is vendored in `pkg/tree-sitter/`** — the core C library and all grammar parsers are compiled by Zig as part of the build. Not an SPM dependency. Each language grammar (Swift, JS, TS, Python, JSON, Bash, Markdown, Zig, Rust, Go) has its C parser source and `highlights.scm` query file vendored in `pkg/tree-sitter/grammars/<language>/`. The Zig build wrapper compiles all grammars into a single static library that Swift links against via SmithersKit.xcframework.

**GhosttyKit and SmithersKit are xcframeworks** — pre-built by their respective build systems and placed in `macos/`. The Xcode project references them as binary targets.

**codex-app-server and jj are git submodules** at `submodules/codex/` and `submodules/jj/` — built from source by `build.zig` (which wraps `cargo build`) and copied into the `.app` bundle during the build.

### 2.3 Xcode project structure

The `Smithers.xcodeproj` contains:
- **Smithers** app target — the macOS application
- **SmithersTests** unit test target
- **SmithersUITests** UI test target

No xcodegen — the Xcode project is maintained directly (like Ghostty).

### 2.4 Build pipeline

`build.zig` is THE makefile — it builds the entire project from source with one command. It orchestrates the full build as a dependency graph (mirroring Ghostty's build.zig pattern):

1. **Build vendored C deps** — compile `pkg/sqlite/`, `pkg/tree-sitter/`, and other vendored C/C++ deps via their Zig build wrappers.
2. **Build Rust submodules** — `submodules/codex/build.zig` runs `cargo build --release` for codex-app-server. `submodules/jj/build.zig` runs `cargo build --release` for jj.
3. **Build libsmithers** — compile `src/` into a static library (`.a`), linking against vendored deps. Generate `include/libsmithers.h`.
4. **Package SmithersKit.xcframework** — wrap the built `libsmithers.a` + header into an xcframework for Xcode consumption.
5. **Build macOS app** — `xcodebuild build -project macos/Smithers.xcodeproj -scheme Smithers`.
6. **Copy binaries** — copy built `codex-app-server` and `jj` into `.app/Contents/MacOS/`.
7. **Build web app** (optional) — `cd web && pnpm install && pnpm build`.
8. **Launch** — `open .build/xcode/Build/Products/Debug/Smithers.app`.

Commands:
- `zig build dev` — steps 1–9 (full build + launch)
- `zig build test` — Zig unit tests
- `zig build xcode-test` — build + `xcodebuild test -scheme SmithersTests`
- `zig build ui-test` — build + `xcodebuild test -scheme SmithersUITests`
- `zig build playwright` — build web app + start HTTP server + run Playwright e2e tests
- `zig build web` — build web app only
- `zig build codex` — build codex-app-server only
- `zig build jj` — build jj only

### 2.5 Binary integration

**GhosttyKit.xcframework** — Pre-built C framework. Lives at `macos/GhosttyKit.xcframework`. Referenced in the Xcode project as a binary framework. Terminal module imports via `import GhosttyKit` and calls C functions directly.

**SmithersKit.xcframework** — Built by `build.zig` from the `src/` Zig code. Contains the compiled `libsmithers.a` static library and the `include/libsmithers.h` header. Swift imports via the xcframework.

**codex-app-server (EVMTS fork)** — A **small fork of OpenAI's Codex** maintained in the EVMTS GitHub org as a git submodule at `submodules/codex/`. The fork does **one thing: wraps the entire Codex in a Zig API**. Instead of Codex being a standalone binary that communicates over JSON-RPC pipes, the fork compiles Codex as a static library and exposes a Zig-native API that libsmithers calls directly. Storage handlers (for SQLite persistence) are passed into this Zig API as callbacks — Codex calls the handlers, and our Zig implementation (`src/storage.zig`) writes to SQLite. Codex doesn't know about SQLite; it just calls the callbacks.

The fork includes a `build.zig` that wraps `cargo build --release --lib` to produce a static library, then exposes the Zig API. `zig build dev` builds the Codex static lib and links it into libsmithers as part of the full build. The fork is kept minimal and rebased on upstream Codex over time. **No child process, no JSON-RPC, no pipes** — Codex runs in-process as a linked library.

**jj (EVMTS fork)** — A fork of Jujutsu maintained in the EVMTS GitHub org as a git submodule at `submodules/jj/`. **No code changes** — the fork exists solely to wrap the Rust build with a `build.zig`. This lets `zig build dev` build the jj binary as part of the full build rather than requiring a pre-built binary. Built binary is copied into `.app/Contents/MacOS/` during build. The app never relies on the user having jj in their PATH.

**SQLite (vendored)** — The SQLite C library is vendored in `pkg/sqlite/` with a Zig build wrapper. Used by `src/storage.zig` for the storage trait implementation. This is separate from GRDB.swift (which the Swift layer uses for its own SQLite access). Both the Zig layer and Swift layer can access the same database file using SQLite's WAL mode for concurrent access.

### 2.6 Zig ↔ Swift architecture (libsmithers model)

Smithers follows the same architecture as **libghostty** (Ghostty's core): a Zig library handles business logic, and Swift is a thin UI layer that syncs with it. This is the key architectural pattern for the entire app.

**Why Zig?**
- **Cross-platform portability.** Zig compiles to any target. When Smithers eventually ships on Linux (and potentially Windows), the Zig core stays unchanged — only the UI layer is replatformed. This is exactly how Ghostty works: libghostty is the portable Zig core, and the macOS app is a Swift/AppKit UI layer on top.
- **Performance.** Zig has no runtime, no GC, and predictable performance. For agent orchestration, subprocess management, and protocol handling, this matters.
- **Testability.** Zig logic is tested independently via `zig build test`, without any Apple framework dependencies.

**The split:**

| Layer | Language | Responsibilities |
|-------|----------|-----------------|
| **libsmithers** (Zig) | Zig | Agent orchestration, codex-app-server protocol, jj operations, file watching, IPC protocol, chat session state machine, suggestion generation, search coordination, snapshot management. This is the source of truth. |
| **SmithersUI** (Swift) | Swift/SwiftUI | Rendering views, animations, AppKit interop (STTextView, Ghostty surface, NSWindow management), user input handling, accessibility. Observes libsmithers state and renders it. |

**Communication pattern (follows libghostty exactly):**

The bridge between Zig and Swift uses the same proven patterns as libghostty. These are not conceptual — they're the exact patterns we copy:

**1. C header as single source of truth:**

```c
// include/libsmithers.h — THE contract between Zig and Swift
// All Zig exports go through this header. Swift imports it directly.

// --- Opaque types (Swift never sees the Zig internals) ---
typedef struct smithers_app_s* smithers_app_t;
typedef struct smithers_surface_s* smithers_surface_t;  // per-workspace handle

// --- Lifecycle ---
smithers_app_t smithers_app_new(const smithers_config_t* config);
void smithers_app_free(smithers_app_t app);

// --- Actions (Swift → Zig intent dispatch) ---
// Uses tagged union pattern: one function, many action types.
// This avoids an explosion of C functions as features grow.
typedef enum {
    SMITHERS_ACTION_CHAT_SEND,
    SMITHERS_ACTION_WORKSPACE_OPEN,
    SMITHERS_ACTION_WORKSPACE_CLOSE,
    SMITHERS_ACTION_AGENT_SPAWN,
    SMITHERS_ACTION_AGENT_CANCEL,
    SMITHERS_ACTION_FILE_SAVE,
    SMITHERS_ACTION_FILE_OPEN,
    SMITHERS_ACTION_SEARCH,
    SMITHERS_ACTION_JJ_COMMIT,
    SMITHERS_ACTION_JJ_UNDO,
    SMITHERS_ACTION_SETTINGS_CHANGE,
    SMITHERS_ACTION_SUGGESTION_REFRESH,
    // ... grows as features are added
} smithers_action_tag_e;

typedef union { /* per-action payloads */ } smithers_action_payload_u;

void smithers_app_action(smithers_app_t app, smithers_action_tag_e tag,
                         smithers_action_payload_u payload);

// --- Callbacks (Zig → Swift notifications) ---
// Exactly like ghostty: function pointer + opaque userdata.
typedef void (*smithers_wakeup_cb)(void* userdata);
typedef void (*smithers_action_cb)(void* userdata, smithers_action_tag_e tag,
                                   const void* data, size_t len);

typedef struct {
    smithers_wakeup_cb wakeup;       // "something changed, re-read state"
    smithers_action_cb action;       // "specific thing happened"
    void* userdata;                  // Swift passes Unmanaged<App>.toOpaque()
} smithers_runtime_config_s;
```

**2. Zig exports via CAPI block (same as ghostty's embedded.zig):**

```zig
// src/lib.zig
const App = @import("app.zig").App;

// All C exports in one block, exactly like ghostty's CAPI pattern
pub const CAPI = struct {
    pub export fn smithers_app_new(config: *const c.smithers_config_t) callconv(.c) ?*App {
        return App.init(config) catch null;
    }

    pub export fn smithers_app_free(app: *App) callconv(.c) void {
        app.deinit();
    }

    pub export fn smithers_app_action(
        app: *App,
        tag: c.smithers_action_tag_e,
        payload: c.smithers_action_payload_u,
    ) callconv(.c) void {
        app.performAction(tag, payload);
    }
};

// Force export all CAPI symbols
comptime {
    for (@typeInfo(CAPI).@"struct".decls) |decl| {
        _ = &@field(CAPI, decl.name);
    }
}
```

**3. Swift bridge (same Unmanaged pattern as GhosttyKit):**

```swift
// Bridge/LibSmithers.swift
import Foundation

/// Thin Swift wrapper around the libsmithers C API.
/// Same pattern as Ghostty.App.swift wrapping ghostty_app_t.
final class SmithersCore {
    private let app: smithers_app_t

    init(config: SmithersConfig) throws {
        var cConfig = config.toCConfig()

        // Callbacks — same Unmanaged pattern as Ghostty
        cConfig.runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        cConfig.runtime.wakeup = { userdata in
            let core = Unmanaged<SmithersCore>.fromOpaque(userdata!).takeUnretainedValue()
            DispatchQueue.main.async { core.handleWakeup() }
        }
        cConfig.runtime.action = { userdata, tag, data, len in
            let core = Unmanaged<SmithersCore>.fromOpaque(userdata!).takeUnretainedValue()
            core.handleAction(tag, data: data, len: len)
        }

        guard let app = smithers_app_new(&cConfig) else {
            throw SmithersError.initFailed
        }
        self.app = app
    }

    deinit { smithers_app_free(app) }

    // Actions dispatched to Zig — Swift never manipulates state directly
    func sendChatMessage(_ text: String) {
        text.withCString { cStr in
            var payload = smithers_action_payload_u()
            payload.chat_send.message = cStr
            smithers_app_action(app, SMITHERS_ACTION_CHAT_SEND, payload)
        }
    }

    // Zig calls back → Swift propagates via NotificationCenter (same as Ghostty)
    private func handleAction(_ tag: smithers_action_tag_e, data: UnsafeRawPointer?, len: Int) {
        switch tag {
        case SMITHERS_ACTION_CHAT_DELTA:
            // Decode data, post notification → ChatModel observes and updates UI
            NotificationCenter.default.post(name: .smithersChatDelta, object: /* decoded */)
        case SMITHERS_ACTION_AGENT_STATUS:
            NotificationCenter.default.post(name: .smithersAgentStatus, object: /* decoded */)
        // ... one case per action tag
        default: break
        }
    }

    private func handleWakeup() {
        // Zig says "state changed" — re-read whatever the UI needs
        NotificationCenter.default.post(name: .smithersWakeup, object: nil)
    }
}
```

**4. libsmithers interface layers (critical architecture):**

libsmithers is a Zig core with **multiple consumer interfaces**, all backed by the same internal Zig API. The key principle: **the tools available through the CLI should match the command palette, which should match the MCP server**. One capability surface, multiple access methods.

**Interfaces (v2 launch):**
1. **C API** → consumed by the Swift UI layer (as shown above). Wraps in Swift following the libghosty pattern.
2. **MCP server** → consumed by the Codex orchestrator agent. We **inject libsmithers as an MCP server into Codex at runtime** — this is how Codex controls Smithers. The MCP server exposes IDE capabilities as tools (open files, run terminals, search, spawn agents, etc.). The exact transport mechanism (stdio pipe, Unix socket, or in-process) is an engineering decision to figure out by studying the Codex source code.
3. **CLI** (`smithers-ctl`) → consumed by external tools, scripts, and the user's shell. Same capability surface as the command palette and MCP server.
4. **HTTP/WebSocket server** → consumed by the **SolidJS web app** (`web/`). Exposes the same capability surface as the C API, MCP server, and CLI over HTTP REST + WebSocket for real-time updates. Implemented in Zig (`src/http_server.zig`) using **Zap** (vendored in `pkg/zap/`, wraps facil.io — ~3.2k GitHub stars, production-tested, supports WebSocket). No authentication for now (localhost only, internal use). Also serves the built web app's static files and provides WebSocket PTY I/O for xterm.js terminals. A primary consumer is the **Playwright test suite** which exercises the full Zig core end-to-end via the web app.
5. **Zig API** → internal, used by all other interfaces.

The MCP server exposes the same capabilities as the command palette: open files, run terminals, search, read workspace state, spawn agents, etc. The main (orchestrator) Codex process connects to this MCP server. **Sub-agents do NOT have access to the MCP server** — they only have filesystem and terminal tools scoped to their jj workspace branch.

**MCP ↔ Codex integration (engineering decision).** Codex is shipped as a pre-built Rust binary. We need to figure out the best way to inject our MCP server so Codex can discover and use it at runtime. Options include: registering as an MCP server that Codex connects to via stdio/socket, or in-process transport if the Codex runtime supports it. Study the Codex source code (`codex-app-server`) to determine the best integration path.

```
┌────────────────────────────────────────────────────────────────┐
│                        libsmithers (Zig)                        │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌────────┐  ┌────────┐ ┌────────┐│
│  │ Zig API  │  │  C API   │  │  MCP   │  │  CLI   │ │  HTTP  ││
│  │(internal)│  │(→ Swift) │  │ Server │  │(stdio) │ │  /WS   ││
│  └──────────┘  └──────────┘  └────────┘  └────────┘ └────────┘│
│       ↑              ↑            ↑           ↑          ↑      │
│       │              │            │           │          │      │
│  [Zig modules]  [Swift UI]  [Codex     [smithers-  [SolidJS   │
│                             orchestr.]  ctl/shell]  web app]   │
└────────────────────────────────────────────────────────────────┘
```

**5. Zig memory design (arena allocators):**

All Zig code in libsmithers follows these memory conventions:

- **General rule: group things with the same lifetime into the same arena allocation.** This is the core memory principle. If two objects are created together and destroyed together, they share an arena. This eliminates individual free calls and makes cleanup trivial.
- **Lifetime-based allocation:** Objects that share the same lifetime use the same arena allocator. For example, all state for a single agent session lives in one arena — when the agent completes, the entire arena is freed in one shot. All state for a chat message lives in a message arena. All state for a workspace lives in a workspace arena.
- **Arena allocators everywhere:** `std.heap.ArenaAllocator` is the default. The app-level arena lives for the process lifetime. Per-workspace arenas live until the workspace closes. Per-agent arenas live until the agent completes. Per-request arenas live for the duration of a single MCP/CLI request.
- **Owned return pattern:** When a Zig function needs to return owned data to the caller (including across the C API boundary), it uses an internal arena for scratch work, then copies the result with the caller-provided allocator just before returning. This makes lifetimes predictable and avoids dangling references.
- **No hidden allocations:** Every function that allocates takes an explicit `Allocator` parameter. This is idiomatic Zig and makes memory ownership obvious.

```zig
// Example: arena-per-agent pattern
pub const Agent = struct {
    arena: std.heap.ArenaAllocator,
    // All agent state allocated from this arena
    messages: std.ArrayList(Message),
    workspace_path: []const u8,
    // ...

    pub fn deinit(self: *Agent) void {
        // One free kills everything — no individual deallocations needed
        self.arena.deinit();
    }
};

// Example: owned return with caller allocator
pub fn getAgentListJson(app: *App, caller_alloc: Allocator) ![]const u8 {
    // Internal scratch arena for temporary work
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();

    const tmp = try buildJsonArray(scratch.allocator(), app.agents);
    // Copy to caller's allocator so they own the lifetime
    return try caller_alloc.dupe(u8, tmp);
}
```

**Build approach — Zig core first (TDD), UI in parallel:**

We build the Zig core first because it enables TDD — `zig build test` runs instantly with no Apple framework dependencies. The Swift UI is built in parallel using mocks and stubs for the libsmithers C API. They hook up when both are ready.

1. **Phase A (Zig core):** Implement `src/` modules with comprehensive `zig build test` coverage. Each module (orchestrator, codex_client, jj, agent, etc.) has its own test file. Tests use mock Codex instances and recorded sessions.
2. **Phase B (Swift UI, parallel):** Implement all views and `@Observable` models using `MockSmithersCore` that returns canned data. UI development doesn't block on Zig being done.
3. **Phase C (integration):** Replace `MockSmithersCore` with the real `SmithersCore` wrapping the built `libsmithers.a`. Run integration tests.

**Build integration:** `build.zig` orchestrates everything:
1. Build vendored C deps in `pkg/` (SQLite, TreeSitter, etc.)
2. Build Rust submodules via `cargo build --release` (`submodules/codex/`, `submodules/jj/`)
3. Compile `libsmithers` as a static library (`.a`) + generate C header (`include/libsmithers.h`)
4. Package as `SmithersKit.xcframework` for Xcode
5. Run `zig build test` (Zig unit tests)
6. Build Swift app via `xcodebuild` (links SmithersKit + GhosttyKit xcframeworks)
7. Copy built Rust binaries (`codex-app-server`, `jj`) into `.app/Contents/MacOS/`
8. Build web app (optional): `cd web && pnpm install && pnpm build`
9. Launch

**Wrapping dependencies in Zig:** External tools are wrapped in Zig from day one so the logic layer owns them:

- **jj** — Zig spawns the bundled jj binary, parses output with Zig's JSON parser. `src/jj.zig` owns all VCS logic.
- **codex-app-server** — Zig calls the in-process Codex Zig API directly. `src/codex_client.zig` wraps the API, `src/orchestrator.zig` handles dispatch.
- **ripgrep** — Zig wraps `rg` for workspace search. `src/search.zig`.
- **File watching** — Zig uses FSEvents on macOS via C API (`CoreServices` framework), inotify on Linux later. `src/file_watcher.zig`.
- **MCP server** — Zig implements the MCP protocol for Codex to connect to. `src/mcp_server.zig`.

Things that **stay in Swift**: all UI rendering, STTextView/editor coordinator, Ghostty surface management (already Zig via GhosttyKit), Neovim RPC (deep AppKit integration), preferences UI, window management, accessibility.
