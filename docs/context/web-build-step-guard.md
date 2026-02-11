# Research Context: web-build-step-guard

## Problem

Lines 136-137 of `build.zig` define `web` and `playwright` steps that check for `web/` directory existence but **do not check for `pnpm` availability**. On machines without pnpm, `zig build all` (line 172 depends on `web_step`) will fail when `web/` exists.

## Exact Lines to Change

**build.zig line 136** (web step):
```
const web_step = addOptionalShellStep(b, "web", "Build web app (if web/ exists)", "if [ -d web ]; then cd web && pnpm install && pnpm build; else echo 'skipping web: web/ not found'; fi");
```

**build.zig line 137** (playwright step):
```
const playwright_step = addOptionalShellStep(b, "playwright", "Run Playwright e2e (if web/ exists)", "if [ -d web ]; then cd web && pnpm install && pnpm exec playwright test; else echo 'skipping playwright: web/ not found'; fi");
```

## Existing Guard Pattern (lines 159-161)

The **exact pattern to follow** already exists for prettier, typos, and shellcheck:

```shell
# prettier (line 159)
if command -v prettier >/dev/null 2>&1; then prettier --check .; else echo 'skipping prettier-check: prettier not installed'; fi

# typos (line 160)
if command -v typos >/dev/null 2>&1; then typos; else echo 'skipping typos-check: typos not installed'; fi

# shellcheck (line 161)
if command -v shellcheck >/dev/null 2>&1; then find . -type f -name '*.sh' -exec shellcheck --severity=warning {} +; ...; else echo 'skipping shellcheck: shellcheck not installed'; fi
```

## Required Fix

Nest both checks: directory existence **AND** pnpm availability. The shell script should:
1. Check `[ -d web ]` — skip if no web/ directory
2. Check `command -v pnpm >/dev/null 2>&1` — skip if pnpm not installed
3. Run `cd web && pnpm install && pnpm build` only when both pass

### Proposed shell for web step:
```shell
if [ -d web ] && command -v pnpm >/dev/null 2>&1; then cd web && pnpm install && pnpm build; elif [ ! -d web ]; then echo 'skipping web: web/ not found'; else echo 'skipping web: pnpm not installed'; fi
```

### Proposed shell for playwright step:
```shell
if [ -d web ] && command -v pnpm >/dev/null 2>&1; then cd web && pnpm install && pnpm exec playwright test; elif [ ! -d web ]; then echo 'skipping playwright: web/ not found'; else echo 'skipping playwright: pnpm not installed'; fi
```

## Architecture Note

`addOptionalShellStep` (line 3-8) is a simple helper that creates a build step running `sh -c <script>`. No Zig-side complexity — the guard is purely shell logic inside the string argument.

## Consumers of web_step

- `all_step` (line 172): `all_step.dependOn(web_step)` — **this is the failing path**
- `dev_step` (line 149): `dev_step.dependOn(web_step)`

## No Other Files Need Changes

The fix is entirely within `build.zig` lines 136-137. Two string edits.

## Test Plan

1. **Without pnpm**: `PATH='' zig build all` should succeed, printing "skipping web: pnpm not installed"
2. **With pnpm**: `zig build web` should run `pnpm install && pnpm build` normally
3. **Without web/**: Should still print "skipping web: web/ not found"
4. **`zig build all`**: Must pass with zero regressions (run full suite)
