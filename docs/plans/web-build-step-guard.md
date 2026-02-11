# Plan: web-build-step-guard — Guard web/playwright steps when pnpm is missing

## Problem

`zig build all` fails on machines without pnpm when `web/` directory exists. Lines 136-137 of `build.zig` check for `web/` but not `pnpm` binary availability. The codebase already has the exact guard pattern on lines 159-161 (`command -v <tool> >/dev/null 2>&1`).

## Scope

Single file change: `build.zig` lines 136-137. Two shell string edits. No Zig API, no new files, no test files (shell behavior verified by `zig build all`).

## Steps

### Step 1: Update web step shell guard (build.zig line 136)

**File:** `build.zig`

Change the shell script string from:
```shell
if [ -d web ]; then cd web && pnpm install && pnpm build; else echo 'skipping web: web/ not found'; fi
```

To:
```shell
if [ ! -d web ]; then echo 'skipping web: web/ not found'; elif ! command -v pnpm >/dev/null 2>&1; then echo 'skipping web: pnpm not installed'; else cd web && pnpm install && pnpm build; fi
```

This follows the existing pattern from lines 159-161 (prettier/typos/shellcheck) and provides distinct skip messages for each failure case.

### Step 2: Update playwright step shell guard (build.zig line 137)

**File:** `build.zig`

Change the shell script string from:
```shell
if [ -d web ]; then cd web && pnpm install && pnpm exec playwright test; else echo 'skipping playwright: web/ not found'; fi
```

To:
```shell
if [ ! -d web ]; then echo 'skipping playwright: web/ not found'; elif ! command -v pnpm >/dev/null 2>&1; then echo 'skipping playwright: pnpm not installed'; else cd web && pnpm install && pnpm exec playwright test; fi
```

### Step 3: Run `zig build all` to verify Always Green

Run `zig build all` — must pass with zero errors. The web step should either:
- Run pnpm build (if pnpm installed + web/ exists)
- Print "skipping web: pnpm not installed" (if web/ exists but no pnpm)
- Print "skipping web: web/ not found" (if no web/ directory)

## Verification

1. `zig build all` succeeds on host without pnpm (prints skip message)
2. `zig build all` still runs pnpm when available
3. `zig build web` individually prints skip or runs correctly
4. No other build steps regressed

## Why no test file changes

The guard is purely shell logic inside `addOptionalShellStep` string arguments. The existing `zig build all` integration test (running the full build) validates correctness. Adding a Zig unit test for a shell string would be testing the wrong abstraction — the shell interpreter is the test harness.
