# CRITICAL: ALWAYS GREEN

Codebase MUST be green. ZERO tolerance for failures (even pre-existing).

## Canonical Command

**`zig build all`** — Run after EVERY change. Runs ALL checks in parallel.
Do NOT commit until passes with zero errors.

## Individual Checks

`zig build all` is canonical, but individual checks:

### 1. Build
- `zig build` — zero errors, zero warnings
- `zig build web` / `zig build codex` / `zig build jj` — all must compile cleanly

### 2. Tests
- `zig build test` — ALL Zig unit tests pass (use std.testing.allocator for leak detection)
- `zig build playwright` — ALL e2e tests pass
- Xcode tests via `zig build test` — ALL Swift tests pass
- ANY failure (even pre-existing) — fix before moving on

### 3. Formatting
- `zig fmt --check .` — all Zig formatted (run `zig fmt .` to fix)
- `prettier --check .` — JSON/YAML/Markdown/JS/TS formatted
- Swift: Xcode default (4-space indent)

### 4. Linting
- Zero Zig warnings (treat as errors)
- Zero Swift concurrency warnings (Swift 6 strict)
- `shellcheck --severity=warning` on shell scripts
- `typos` — spell check (configure typos.toml for domain words)

### 5. Memory Safety
- std.testing.allocator — zero leaks
- errdefer on every failable allocation — no resource leaks on error paths
- `self.* = undefined` after deinit (poison use-after-free)

### 6. Correctness
- Exhaustive switches (no `else` for unknown variants)
- Explicit error sets (never `anyerror`)
- Public APIs must have tests

## Rules
- NEVER accept failing test (even pre-existing)
- NEVER leave build broken
- NEVER commit code that doesn't compile
- Pre-existing failure → fix as part of current work
- Run full check suite after EVERY change; failures → fix before moving on
- When in doubt, run more checks, not fewer
