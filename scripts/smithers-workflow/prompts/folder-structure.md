# Smithers v2 Folder Structure

Mirrors Ghostty layout. Single `build.zig` builds all code.

```
smithers-v2/
├── build.zig              # Thin — delegates to src/build/main.zig
├── build.zig.zon          # Zig package manifest
├── CLAUDE.md              # AI agent conventions
├── docs/
│   ├── design.md          # UI/UX spec (~1400 lines)
│   ├── engineering.md     # Engineering spec (~2800 lines)
│   └── folder-structure.md
├── issues/*.md            # Feature specs (NOT implementation details)
├── src/                   # Zig source (libsmithers — portable logic)
│   ├── main.zig           # CLI entry (smithers-ctl)
│   ├── build/
│   │   ├── main.zig       # Build orchestration
│   │   └── *.zig          # Each artifact/step = PascalCase.zig
│   ├── storage.zig        # SQLite storage
│   ├── host.zig           # Platform abstraction (comptime vtable/DI)
│   └── <module>/
│       ├── main.zig       # Namespace (re-exports, test discovery)
│       └── *.zig          # PascalCase.zig=struct, snake_case.zig=module
├── include/
│   └── smithers.h         # C API — contract between Zig/Swift
│                          # smithers_ prefix; _e(enum), _s(struct), _t(opaque), _cb(callback)
├── pkg/                   # Vendored C/C++ deps + Zig wrappers
│   ├── sqlite/build.zig   # SQLite amalgamation
│   ├── zap/build.zig      # Zap HTTP (wraps facil.io)
│   └── tree-sitter/build.zig
├── submodules/            # Git submodules (Rust → static libs)
│   ├── codex/build.zig    # EVMTS fork — Codex as Zig API (cargo wrapper)
│   └── jj/build.zig       # EVMTS fork — Jujutsu (no code changes, cargo wrapper)
├── macos/                 # Swift app (Xcode project, NOT Package.swift)
│   ├── Smithers.xcodeproj/
│   └── Sources/Features/  # Feature-based: App/, Chat/, IDE/, Terminal/, Editor/
├── web/                   # SolidJS Vite PWA (parity with native)
│   ├── package.json       # pnpm
│   ├── vite.config.ts
│   ├── src/
│   │   ├── components/    # SolidJS (shadcn-solid)
│   │   ├── stores/        # Plain SolidJS stores
│   │   ├── pages/         # SPA routes
│   │   └── lib/           # Utils, API client
│   └── tests/*.spec.ts    # Playwright e2e
├── prototype0 -> ../smithers/apps/desktop  # v1 reference
├── prototype1/            # Next.js frozen reference (delete when done)
├── scripts/smithers-workflow/  # 3 AI agents build product
└── .github/workflows/     # CI: Zig tests→Rust→Swift→Playwright→web
```

## Naming Conventions

### Zig
- **PascalCase.zig** = struct-as-file (file IS struct, `const Self = @This();`). Ex: `App.zig`, `Surface.zig`, `Terminal.zig`, `Storage.zig`
- **snake_case.zig** = namespace/module (re-exports, shared types). Ex: `config.zig`, `apprt.zig`, `renderer.zig`
- Subsystem = **directory + namespace file**: `terminal/` + `terminal/main.zig`

### Swift
- **Feature-based**: `macos/Sources/Features/{FeatureName}/`
- **Namespace**: `Smithers.Action.swift`, `Smithers.App.swift` (enum as namespace)
- **Extensions**: `TypeName+Extension.swift`

### Web
- **Components**: `web/src/components/` (SolidJS, shadcn-solid)
- **Stores**: `web/src/stores/` (SolidJS createStore)
- **Tests**: `web/tests/*.spec.ts` (Playwright)

## Build Commands

```bash
zig build              # Everything
zig build dev          # Build + launch macOS
zig build test         # ALL tests (Zig + Swift)
zig build web          # Web only
zig build playwright   # Web + server + Playwright e2e
zig build codex        # Codex static lib
zig build jj           # JJ only
```

## Key Principles

1. **build.zig builds EVERYTHING** — Zig, C deps, Rust (cargo), Swift, web
2. **Vendor C/C++** in `pkg/` with Zig wrappers
3. **Rust** as git submodules in `submodules/` → static libs
4. **Swift deps** via Xcode SPM (Sparkle, STTextView, GRDB.swift)
5. **Web deps** via pnpm in `web/`
6. **No Turborepo/Nx** — `build.zig` = monorepo tool
