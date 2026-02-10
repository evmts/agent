# Architecture

- **libsmithers** (Zig core) — 5 interfaces: C API (Swift), MCP server (Codex), CLI (smithers-ctl), HTTP/WS (web app), Zig API (internal)
- **Codex fork** (`submodules/codex/`) — wraps entire Codex in Zig API, static lib linked into libsmithers. NO child process, NO JSON-RPC. Storage callbacks = Zig function pointers.
- **JJ fork** (`submodules/jj/`) — version control. No code changes, Zig build wrapper only.
- **SolidJS Vite PWA** (`web/`) — visual parity with native. shadcn-solid + Tailwind + Monaco + xterm.js.
- **SQLite** (`pkg/sqlite/`) — persistence. GRDB.swift on Swift side. WAL mode. Same database.
- **Zap** (`pkg/zap/`) — HTTP server wraps facil.io. No auth (localhost).
- **TreeSitter** (`pkg/`) — syntax parsing.
- **build.zig** — builds EVERYTHING: Zig, C deps, Rust submodules, Swift app, web app.
- **libsmithers = PLATFORM AGNOSTIC** — theoretically compiles to WASM. Use DEPENDENCY INJECTION for platform-specific (SQLite, HTTP, filesystem).
- **Zig library = single source of truth** for all business logic.
