# CRITICAL: ALWAYS GREEN

Codebase MUST be green. ZERO tolerance for failures (even pre-existing).

## Canonical Command

**`zig build all`** — Run after EVERY change. Runs ALL checks wired in `build.zig` in parallel.
Do NOT commit until passes with zero errors.

## Individual Checks

`zig build all` is canonical, but individual checks:

### 1. Build
- `zig build` — zero errors, zero warnings
- When `build.zig` defines them: `zig build dev`, `zig build web`, `zig build codex`, `zig build jj`

### 2. Tests
- `zig build test` — ALL Zig unit tests pass (use std.testing.allocator for leak detection)
- When defined: `zig build playwright`, `zig build xcode-test`, `zig build ui-test`
- If those steps are not yet wired, run the equivalent manual commands (e.g., `xcodebuild test`, `pnpm exec playwright test`)
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
- Pre-existing failure → fix as part of current work WHEN TRIVIAL
- Run full check suite after EVERY change; failures → fix before moving on
- When in doubt, run more checks, not fewer

## Escape Hatch for Pre-Existing Failures
If `zig build all` fails due to unrelated pre-existing failures AND fixing them is non-trivial (would significantly expand ticket scope):
1. Document the failure in `docs/triage/preexisting-failures.md` (append, don't overwrite)
2. Note it in the validation failingSummary so a dedicated ticket is created in the next Discover pass
3. Continue with the current ticket — do NOT go down unrelated rabbit holes
This keeps the workflow from stalling on issues orthogonal to the current work.
