# Plan: web-build-step-guard — Guard web/playwright steps when pnpm is missing

## Problem

`zig build web` and `zig build playwright` fail on machines without pnpm when `web/` directory exists. Lines 163-175 of `build.zig` check for `web/` directory but not for `pnpm` binary availability. The codebase already has the exact guard pattern on lines 232-236 (`command -v <tool> >/dev/null 2>&1` for prettier, typos, shellcheck).

## Scope

- **Layer:** build system (shell strings in `build.zig`)
- **Files modified:** 1 (`build.zig`)
- **Files created:** 0 (test already exists at `tests/web_guard_test.sh`)
- **Risk:** Minimal — string edits to shell commands, no Zig logic changes

## Steps

### Step 1: Update web step shell guard (build.zig lines 163-168)

**File:** `build.zig`

Current shell script (line 167):
```shell
if [ -d web ]; then cd web && pnpm install && pnpm build; else echo "skipping web: web/ not found"; fi
```

New shell script:
```shell
if [ ! -d web ]; then echo 'skipping web: web/ not found'; elif ! command -v pnpm >/dev/null 2>&1; then echo 'skipping web: pnpm not installed'; else cd web && pnpm install && pnpm build; fi
```

This follows the existing pattern from lines 232-236 (prettier/typos/shellcheck) and provides distinct skip messages for each failure case.

### Step 2: Update playwright step shell guard (build.zig lines 170-175)

**File:** `build.zig`

Current shell script (line 174):
```shell
if [ -d web ]; then cd web && pnpm install && pnpm exec playwright test; else echo "skipping playwright: web/ not found"; fi
```

New shell script:
```shell
if [ ! -d web ]; then echo 'skipping playwright: web/ not found'; elif ! command -v pnpm >/dev/null 2>&1; then echo 'skipping playwright: pnpm not installed'; else cd web && pnpm install && pnpm exec playwright test; fi
```

### Step 3: Run `zig build all` to verify Always Green

Run `zig build all` — must pass with zero errors. The web step should either:
- Run pnpm build (if pnpm installed + web/ exists)
- Print "skipping web: pnpm not installed" (if web/ exists but no pnpm)
- Print "skipping web: web/ not found" (if no web/ directory)

### Step 4: Run `tests/web_guard_test.sh` to verify acceptance criteria

The test already exists at `tests/web_guard_test.sh`. It:
- Constrains PATH to exclude pnpm but keep zig
- Runs `zig build web`
- Asserts output contains `"skipping web: pnpm not installed"`
- Prints `web_guard_test: PASS` on success

## Verification

1. `tests/web_guard_test.sh` passes (prints `web_guard_test: PASS`)
2. `zig build web` prints `skipping web: pnpm not installed` when pnpm is absent
3. `zig build all` succeeds on host without pnpm
4. Existing behavior unchanged when pnpm is present (web builds normally)
5. No other build steps regressed

## Risk Assessment

- **Low risk:** Two shell string edits. No Zig compilation logic changes.
- **Pattern proven:** Exact same `command -v` guard pattern already used by prettier/typos/shellcheck steps (lines 232-236).
- **Backward compatible:** When pnpm IS available, behavior is identical to current.
