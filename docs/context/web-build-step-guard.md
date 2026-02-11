# Research Context: web-build-step-guard

## Summary

One-line shell script change in `build.zig`. The `zig build web` step (lines 163-168) only checks if `web/` exists but does NOT check if `pnpm` is installed. When `pnpm` is missing, the step fails instead of skipping cleanly. Fix: nest a `command -v pnpm` check inside the existing directory check, matching the pattern already used by prettier/typos/shellcheck steps (lines 232-236). The `zig build playwright` step (lines 170-175) has the same bug and should get the same fix.

## What Needs to Change

### Current (broken) -- build.zig lines 163-168:
```zig
const web_step = addOptionalShellStep(
    b,
    "web",
    "Build web app (if web/ exists)",
    "if [ -d web ]; then cd web && pnpm install && pnpm build; else echo \"skipping web: web/ not found\"; fi",
);
```

### Target shell (fixed):
```shell
if [ -d web ]; then
  if command -v pnpm >/dev/null 2>&1; then
    cd web && pnpm install && pnpm build
  else
    echo 'skipping web: pnpm not installed'
  fi
else
  echo 'skipping web: web/ not found'
fi
```

### Playwright step (lines 170-175) -- same pattern, same fix needed.

## Established Pattern to Follow

Lines 232-236 show the `command -v` guard pattern already used for 3 other optional tools:

```zig
// Line 232
"if command -v prettier >/dev/null 2>&1; then prettier --check .; else echo 'skipping prettier-check: prettier not installed'; fi"

// Line 234
"if command -v typos >/dev/null 2>&1; then typos; else echo 'skipping typos-check: typos not installed'; fi"
```

Key details:
- `command -v TOOL >/dev/null 2>&1` -- POSIX-portable check, stdout+stderr suppressed
- Skip message format: `'skipping STEP_NAME: TOOL not installed'`
- Exit 0 implicit (shell if/else with echo exits 0)

## Test File

`tests/web_guard_test.sh` (already exists, currently FAILING):
- Constrains PATH to exclude pnpm but keep zig + system tools
- Runs `zig build web` with restricted PATH
- Asserts output contains exact string: `"skipping web: pnpm not installed"`
- Prints `web_guard_test: PASS` on success

## Key Files

| File | Lines | Relevance |
|------|-------|-----------|
| `build.zig` | 163-168 | Web step to fix (primary) |
| `build.zig` | 170-175 | Playwright step (same bug) |
| `build.zig` | 232-236 | Reference pattern (`command -v`) |
| `build.zig` | 3-13 | `addOptionalShellStep` helper |
| `build.zig` | 211-213 | `dev_step` depends on `web_step` |
| `build.zig` | 239-245 | `all_step` does NOT depend on `web_step` |
| `tests/web_guard_test.sh` | 1-18 | Acceptance test |

## Gotchas

1. **Exact skip message** -- test greps for `"skipping web: pnpm not installed"` exactly. Must match character-for-character.
2. **Nested if/else one-liner** -- web step needs TWO checks (directory + tool). Watch semicolons and `fi` placement in the single shell string.
3. **dev_step depends on web_step** (line 213) -- skip must exit 0, not fail. The echo + fi pattern ensures this.
4. **all_step depends on web_step** now (see build.zig ~line 220) -- `zig build all` runs the guard step which skips cleanly without pnpm.
5. **Playwright step unused** -- `_ = playwright_step` (line 177), not wired into any composite. Fix for consistency.

## No External Docs Needed

Purely a shell script change inside an existing Zig build step string. No Zig stdlib APIs, Swift, or web framework docs required.
