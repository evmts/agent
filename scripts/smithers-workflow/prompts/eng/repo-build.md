## 2. Repository & Build

### 2.1 Structure

```
smithers/
├── build.zig                  # THE makefile: Zig core, vendored C, Rust subs (Codex, JJ), xcframework, Swift, web
├── build.zig.zon              # Zig package manifest
├── AGENTS.md / CLAUDE.md      # Agent / Claude Code instructions
├── docs/{design,engineering}.md
├── issues/                    # Post-MVP feature specs
├── prototype/                 # Next.js UI reference
├── include/libsmithers.h      # C API header — THE Zig↔Swift contract
├── src/                       # Zig (libsmithers logic)
│   ├── lib.zig               # Root: C API exports
│   ├── orchestrator.zig, agent.zig, codex_client.zig, jj.zig, search.zig
│   ├── file_watcher.zig, chat_state.zig, snapshot.zig, suggestion.zig
│   ├── ipc.zig, mcp_server.zig, http_server.zig, scheduler.zig
│   ├── storage.zig, memory.zig
│   └── models/               # Zig structs → C structs → Swift
├── pkg/                       # Vendored C/C++ + Zig wrappers
│   ├── sqlite/, zap/, tree-sitter/grammars/, macos/
├── submodules/                # Git subs (Rust forks + Zig wrappers)
│   ├── codex/                # EVMTS fork: cargo → static lib → Zig API
│   └── jj/                   # EVMTS fork: no code changes, Zig build wrapper
├── macos/                     # Swift app (Ghostty pattern)
│   ├── Smithers.xcodeproj/   # Real Xcode (no Package.swift, no xcodegen)
│   ├── Smithers-Info.plist, Smithers.entitlements
│   ├── SmithersKit.xcframework/, GhosttyKit.xcframework/
│   ├── Assets.xcassets/
│   ├── Sources/
│   │   ├── App/              # Entry, scenes, window coord
│   │   ├── Ghostty/SmithersCore.swift  # C FFI bridge
│   │   ├── Features/         # Chat, IDE, Terminal, Editor, Neovim, Agents, Skills, Settings, Command Palette, Search, Update
│   │   ├── Helpers/{Extensions, DesignSystem}
│   │   └── Services/         # Thin over libsmithers C API
│   ├── Tests/, SmithersUITests/
├── web/                       # SolidJS parallel app
│   ├── package.json          # SolidJS + shadcn-solid + Tailwind + Monaco
│   ├── src/{index.tsx, components/, features/, lib/, styles/}
└── dist/                      # Packaging, signing
```

**Mirrors Ghostty:** `src/` Zig, `pkg/` vendored C + Zig wrappers, `include/` C API, `macos/` Swift + real Xcode, `build.zig` THE makefile, `submodules/` Rust forks, `web/` SolidJS (talks HTTP), feature-based `macos/Sources/Features/`.

**No Package.Swift.** Real Xcode. SPM via Xcode (Sparkle, STTextView, GRDB.swift) — Ghostty approach.

**Vendor + Zig wrap:** C/C++ → `pkg/` + Zig wrappers (SQLite, Zap/facil.io, TreeSitter). Rust → `submodules/` forks + Zig wrappers calling `cargo build` (EVMTS org). Swift → Xcode SPM. Web → npm/pnpm.

**Pattern:** Every dep has `build.zig` wrapper → `zig build dev` builds all from source.

**Zig→Swift migration:** MVP starts more Swift (v1 is Swift, proven). `src/` Zig grows, `Services/` shrinks. `Ghostty/` Swift wrapper thins as logic migrates.

**Feature-based:** `macos/Sources/Features/` — views+models+VMs per feature, not by arch layer. Findable.

### 2.2 Xcode (no Package.swift)

Ghostty approach: real `Smithers.xcodeproj`, no SPM app target. SPM via Xcode: Sparkle (binary xcframework), STTextView, GRDB.swift.

TreeSitter vendored `pkg/tree-sitter/` — core + all grammars (Swift, JS, TS, Python, JSON, Bash, Markdown, Zig, Rust, Go) with C + `highlights.scm`. Zig builds → static lib → Swift links via SmithersKit.xcframework.

GhosttyKit, SmithersKit = xcframeworks pre-built by build systems → `macos/`, Xcode refs as binary.

codex-app-server, jj = submodules built by `build.zig` (`cargo build`) → copied to `.app` bundle.

### 2.3 Xcode project

`Smithers.xcodeproj`: Smithers app, SmithersTests, SmithersUITests. No xcodegen — maintained direct (Ghostty).

### 2.4 Build pipeline

`build.zig` THE makefile — dependency graph (Ghostty pattern):

1. Build vendored C (`pkg/sqlite/`, `pkg/tree-sitter/`, etc.)
2. Build Rust subs (`submodules/codex/build.zig` → `cargo build --release` codex; same for jj)
3. Build libsmithers (`src/` → `.a`, link vendored, gen `include/libsmithers.h`)
4. Package SmithersKit.xcframework (`.a` + header → xcframework)
5. Build macOS (`xcodebuild build -project macos/Smithers.xcodeproj -scheme Smithers`)
6. Copy binaries (codex-app-server, jj → `.app/Contents/MacOS/`)
7. Build web (optional: `cd web && pnpm install && pnpm build`)
8. Launch (`open .build/xcode/Build/Products/Debug/Smithers.app`)

**Commands:** `zig build dev` (1-8 full+launch), `zig build test` (Zig unit), `zig build xcode-test` (Swift tests), `zig build ui-test` (XCUITest), `zig build playwright` (web+HTTP+e2e), `zig build web`, `zig build codex`, `zig build jj`.

### 2.5 Binary integration

**GhosttyKit.xcframework** — pre-built C, `macos/GhosttyKit.xcframework`, Xcode binary ref, `import GhosttyKit`.

**SmithersKit.xcframework** — `build.zig` from `src/` Zig → `libsmithers.a` + `include/libsmithers.h`.

**codex-app-server (EVMTS fork)** — small OpenAI Codex fork, EVMTS org submodule `submodules/codex/`. **Wraps Codex in Zig API.** Compiles static lib (not binary), Zig API libsmithers calls direct. Storage handlers as Zig callbacks → `src/storage.zig` writes SQLite (Codex doesn't know SQLite). Fork `build.zig` wraps `cargo build --release --lib` → static → Zig API. `zig build dev` builds+links. Minimal fork rebased upstream. **No child process, no JSON-RPC, no pipes** — in-process linked lib.

**jj (EVMTS fork)** — Jujutsu fork EVMTS org `submodules/jj/`. **No code changes** — just Zig `build.zig` wrapper. `zig build dev` builds jj binary, copies `.app/Contents/MacOS/`. No user PATH dep.

**SQLite (vendored)** — `pkg/sqlite/` + Zig wrapper. Used `src/storage.zig`. Separate from GRDB.swift (Swift layer). Both access same db WAL mode concurrent.

### 2.6 Zig↔Swift (libsmithers model)

**libghostty pattern:** Zig business logic, Swift thin UI syncs.

**Why Zig:** Cross-platform (Zig unchanged, UI replatformed Linux/Windows). Performance (no runtime, no GC). Testability (`zig build test` no Apple deps).

**Split:**
| Layer | Lang | Responsibilities |
|-------|------|------------------|
| libsmithers (Zig) | Zig | Agent orchestration, codex protocol, jj ops, file watch, IPC, chat state, suggestion, search, snapshot. Source of truth. |
| SmithersUI (Swift) | Swift/SwiftUI | Render, animations, AppKit (STTextView, Ghostty surface, NSWindow), input, a11y. Observes libsmithers → renders. |

**Communication (libghostty exact patterns):**

**1. C header contract:**

```c
// include/libsmithers.h — THE Zig↔Swift contract

// Opaque (Swift never sees Zig internals)
typedef struct smithers_app_s* smithers_app_t;
typedef struct smithers_surface_s* smithers_surface_t;  // per-workspace

// Lifecycle
smithers_app_t smithers_app_new(const smithers_config_t* config);
void smithers_app_free(smithers_app_t app);

// Actions (Swift→Zig intent dispatch) — tagged union, one fn many types
typedef enum {
    SMITHERS_ACTION_CHAT_SEND, SMITHERS_ACTION_WORKSPACE_OPEN,
    SMITHERS_ACTION_WORKSPACE_CLOSE, SMITHERS_ACTION_AGENT_SPAWN,
    SMITHERS_ACTION_AGENT_CANCEL, SMITHERS_ACTION_FILE_SAVE,
    SMITHERS_ACTION_FILE_OPEN, SMITHERS_ACTION_SEARCH,
    SMITHERS_ACTION_JJ_COMMIT, SMITHERS_ACTION_JJ_UNDO,
    SMITHERS_ACTION_SETTINGS_CHANGE, SMITHERS_ACTION_SUGGESTION_REFRESH,
    // ... grows
} smithers_action_tag_e;

typedef union { /* per-action payloads */ } smithers_action_payload_u;

void smithers_app_action(smithers_app_t app, smithers_action_tag_e tag,
                         smithers_action_payload_u payload);

// Callbacks (Zig→Swift) — ghostty: fn ptr + opaque userdata
typedef void (*smithers_wakeup_cb)(void* userdata);
typedef void (*smithers_action_cb)(void* userdata, smithers_action_tag_e tag,
                                   const void* data, size_t len);

typedef struct {
    smithers_wakeup_cb wakeup;       // "changed, re-read"
    smithers_action_cb action;       // "specific event"
    void* userdata;                  // Unmanaged<App>.toOpaque()
} smithers_runtime_config_s;
```

**2. Zig exports (ghostty CAPI):**

```zig
// src/lib.zig
const App = @import("app.zig").App;

pub const CAPI = struct {
    pub export fn smithers_app_new(config: *const c.smithers_config_t) callconv(.c) ?*App {
        return App.init(config) catch null;
    }
    pub export fn smithers_app_free(app: *App) callconv(.c) void {
        app.deinit();
    }
    pub export fn smithers_app_action(
        app: *App, tag: c.smithers_action_tag_e, payload: c.smithers_action_payload_u,
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

**3. Swift bridge (Unmanaged pattern):**

```swift
// Bridge/LibSmithers.swift
final class SmithersCore {
    private let app: smithers_app_t

    init(config: SmithersConfig) throws {
        var cConfig = config.toCConfig()
        // Callbacks — Unmanaged pattern
        cConfig.runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        cConfig.runtime.wakeup = { userdata in
            let core = Unmanaged<SmithersCore>.fromOpaque(userdata!).takeUnretainedValue()
            DispatchQueue.main.async { core.handleWakeup() }
        }
        cConfig.runtime.action = { userdata, tag, data, len in
            let core = Unmanaged<SmithersCore>.fromOpaque(userdata!).takeUnretainedValue()
            core.handleAction(tag, data: data, len: len)
        }
        guard let app = smithers_app_new(&cConfig) else { throw SmithersError.initFailed }
        self.app = app
    }

    deinit { smithers_app_free(app) }

    // Actions → Zig (Swift never mutates state)
    func sendChatMessage(_ text: String) {
        text.withCString { cStr in
            var payload = smithers_action_payload_u()
            payload.chat_send.message = cStr
            smithers_app_action(app, SMITHERS_ACTION_CHAT_SEND, payload)
        }
    }

    // Zig callbacks → Swift NotificationCenter
    private func handleAction(_ tag: smithers_action_tag_e, data: UnsafeRawPointer?, len: Int) {
        switch tag {
        case SMITHERS_ACTION_CHAT_DELTA:
            NotificationCenter.default.post(name: .smithersChatDelta, object: /* decoded */)
        case SMITHERS_ACTION_AGENT_STATUS:
            NotificationCenter.default.post(name: .smithersAgentStatus, object: /* decoded */)
        default: break
        }
    }

    private func handleWakeup() {
        NotificationCenter.default.post(name: .smithersWakeup, object: nil)
    }
}
```

**4. libsmithers interfaces (critical):**

**Multiple consumers, same Zig API. Principle: CLI tools = command palette = MCP server. One capability, multiple access.**

**Interfaces:**
1. **C API** → Swift UI (above). libghostty pattern.
2. **MCP server** → Codex orchestrator. **Inject libsmithers MCP into Codex runtime** — how Codex controls Smithers. Exposes IDE tools (open files, terminals, search, spawn agents, etc.). Transport (stdio/socket/in-process) = engineering decision from Codex source study.
3. **CLI** (`smithers-ctl`) → external tools, scripts, shell. Same capability as palette+MCP.
4. **HTTP/WS server** → **SolidJS web app** (`web/`). Same capability C API, MCP, CLI over HTTP REST + WS real-time. Zig (`src/http_server.zig`) using **Zap** (vendored `pkg/zap/`, wraps facil.io ~3.2k stars, WebSocket). No auth (localhost). Serves web static, WS PTY for xterm.js. **Playwright primary consumer** — e2e tests full Zig via web.
5. **Zig API** → internal.

MCP exposes palette capabilities. Main Codex connects MCP. **Sub-agents NO MCP** — only filesystem+terminal scoped to jj branch.

**MCP↔Codex:** Figure best injection (stdio/socket/in-process). Study `codex-app-server` source.

```
┌──────────────────────────────────────────────────────────┐
│                  libsmithers (Zig)                        │
│ ┌────────┐ ┌────────┐ ┌─────┐ ┌─────┐ ┌──────┐          │
│ │Zig API │ │ C API  │ │ MCP │ │ CLI │ │HTTP  │          │
│ │(intern)│ │(Swift) │ │Serv │ │stdio│ │ /WS  │          │
│ └────────┘ └────────┘ └─────┘ └─────┘ └──────┘          │
│     ↑          ↑         ↑       ↑        ↑              │
│  [Zig mods] [Swift]  [Codex] [smithers-ctl] [SolidJS]   │
└──────────────────────────────────────────────────────────┘
```

**5. Zig memory (arenas):**

**Rule: same lifetime → same arena.** Eliminates individual frees, trivial cleanup.

- **Lifetime allocation:** Shared lifetime = shared arena. Agent session = one arena (complete → free all). Chat message = message arena. Workspace = workspace arena.
- **Arena everywhere:** `std.heap.ArenaAllocator` default. App arena = process life. Workspace = until close. Agent = until complete. Request = MCP/CLI duration.
- **Owned return:** Return owned data → internal arena scratch, copy caller allocator before return. Predictable lifetimes, no dangling.
- **No hidden allocs:** Every allocating fn takes explicit `Allocator` param. Idiomatic Zig, obvious ownership.

```zig
// Arena-per-agent
pub const Agent = struct {
    arena: std.heap.ArenaAllocator,
    messages: std.ArrayList(Message),
    workspace_path: []const u8,
    // All from arena

    pub fn deinit(self: *Agent) void {
        self.arena.deinit();  // One free kills all
    }
};

// Owned return with caller alloc
pub fn getAgentListJson(app: *App, caller_alloc: Allocator) ![]const u8 {
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    const tmp = try buildJsonArray(scratch.allocator(), app.agents);
    return try caller_alloc.dupe(u8, tmp);  // Caller owns
}
```

**Build approach — Zig TDD, UI parallel:**

TDD — `zig build test` instant, no Apple deps. Swift parallel using mocks.

1. **Phase A (Zig):** `src/` modules + comprehensive `zig build test`. Mock Codex, recorded sessions.
2. **Phase B (Swift parallel):** Views + `@Observable` using `MockSmithersCore` canned data. No Zig block.
3. **Phase C (integration):** Replace Mock → real `SmithersCore` wrapping `libsmithers.a`. Integration tests.

**Build integration (`build.zig`):**
1. Vendored C `pkg/` (SQLite, TreeSitter, etc.)
2. Rust subs `cargo build --release` (codex, jj)
3. Compile libsmithers `.a` + gen `include/libsmithers.h`
4. Package SmithersKit.xcframework
5. `zig build test`
6. `xcodebuild` Swift (links SmithersKit+GhosttyKit)
7. Copy Rust bins → `.app/Contents/MacOS/`
8. Web (optional): `cd web && pnpm install && pnpm build`
9. Launch

**Zig-wrapped deps:** Logic layer owns from day one:

- **jj** — Zig spawns bundled binary, parses JSON. `src/jj.zig` owns VCS.
- **codex-app-server** — Zig calls in-process Zig API. `src/codex_client.zig` wraps, `src/orchestrator.zig` dispatches.
- **ripgrep** — Zig wraps `rg`. `src/search.zig`.
- **File watch** — FSEvents macOS C API (`CoreServices`), inotify Linux later. `src/file_watcher.zig`.
- **MCP** — Zig implements protocol. `src/mcp_server.zig`.

**Stay Swift:** UI render, STTextView/editor coord, Ghostty surface (Zig via GhosttyKit), Neovim RPC (deep AppKit), prefs UI, window mgmt, a11y.
