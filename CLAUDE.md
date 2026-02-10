# Smithers v2 — The Ultimate UX for Agentic Coding

A native macOS IDE (Swift/SwiftUI) that *feels* like a TUI but has the UX of a GUI. Not a terminal app — a Swift app designed for terminal power-users. One keystroke from a real terminal (GhosttyKit), Neovim mode for file editing, tmux shortcuts everywhere. Iterating on Claude Code via GUI without losing what terminal users love.

## Project Structure (mirrors Ghostty)

- `src/` - Zig source (libsmithers — the portable logic layer)
- `pkg/` - Vendored C/C++ deps with Zig build wrappers (SQLite, Zap/facil.io, TreeSitter)
- `include/` - C API header (libsmithers.h — THE contract between Zig and Swift)
- `macos/` - Swift app (Xcode project, feature-based organization)
- `web/` - SolidJS Vite PWA (developed in tandem, visual parity with native app)
- `submodules/codex/` - EVMTS fork: wraps Codex in a Zig API + storage callbacks. Rebased on upstream.
- `submodules/jj/` - EVMTS fork of Jujutsu (no code changes, Zig build wrapper)
- `build.zig` / `build.zig.zon` - Builds EVERYTHING. Zig is the monorepo build tool.
- `prototype0` → symlink to `../smithers/apps/desktop` (v1 Swift app reference)
- `prototype1/` - Next.js UI prototype (frozen design reference for both native + web, delete when done)
- `issues/` - Feature specs (take features literally, NOT implementation details — stale from v1)
- `scripts/smithers-workflow/` - Automated workflow (3 AI agents build the product e2e)

## Architecture Overview

**libsmithers** (Zig core) exposes five interfaces, all backed by the same capability surface:
1. **C API** → consumed by Swift UI layer via xcframework (libghostty pattern)
2. **MCP server** → injected into Codex at runtime
3. **CLI** (`smithers-ctl`) → consumed by shell/scripts/user
4. **HTTP/WebSocket server** → consumed by SolidJS web app + Playwright tests. Uses Zap (`pkg/zap/`). No auth.
5. **Zig API** → internal

**Key principle:** Tools in the CLI = command palette = MCP server = HTTP API. One capability surface, multiple access methods.

## Codex Fork — Zig API Wrapper (In-Process, No JSON-RPC)

EVMTS fork at `submodules/codex/`. The fork does ONE thing: **wraps the entire Codex in a Zig API**. Codex compiles as a static library and is linked directly into libsmithers. No child process, no JSON-RPC, no pipes. Storage callbacks (Zig function pointers) passed in at init — our Zig implementation (`src/storage.zig` + `pkg/sqlite/`) writes to shared SQLite. Codex doesn't know about SQLite. Fork rebased on upstream.

## Web App (SolidJS Vite PWA) — Developed in Tandem

**Every feature in the native app is also in the web app.** SolidJS + Vite PWA + shadcn-solid + Tailwind + Monaco + xterm.js. Plain SolidJS stores. Hand-maintained TypeScript types (AI + e2e tests keep in sync). pnpm package manager.

**Playwright tests are a primary reason for the web app** — e2e tests exercise full Zig core through web UI.

## Execution Mode

**YOLO mode only.** No approvals, no sandbox. Future: sandboxing.

## Project Config Files

Reads: `AGENTS.md` (preferred), `CLAUDE.md`, and skills from workspace.

## Dependency Strategy

- **Zig/C deps:** Vendor in `pkg/` with Zig build wrappers (SQLite, Zap, TreeSitter)
- **Rust deps:** Git submodules in `submodules/` — compiled as static libs, linked into libsmithers
- **Swift deps:** Xcode's built-in SPM (Sparkle, STTextView, GRDB.swift)
- **Web deps:** pnpm in `web/` (SolidJS, Vite, shadcn-solid, Tailwind, Monaco, xterm.js, Playwright)
- **Monorepo tool:** `build.zig` orchestrates everything. No Turborepo/Nx.

## Build

```bash
zig build            # Build everything wired in build.zig
zig build run        # Build + run CLI (current)
zig build test       # Zig unit tests
zig build all        # Build + tests + fmt/lint (canonical green check)

# Planned (once build.zig defines these steps):
# zig build dev        # Build everything + launch
# zig build web        # Build web app only
# zig build playwright # Build web + start HTTP server + run Playwright e2e tests
# zig build codex      # Build codex static lib only
# zig build jj         # Build jj only
# zig build xcode-test # Swift tests
# zig build ui-test    # XCUITest e2e
```

## CI/CD

GitHub Actions with macOS runners. Full pipeline: Zig tests → Rust submodule builds → Swift tests → Playwright e2e → web build.
