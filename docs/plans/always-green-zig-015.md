# Plan: always-green-zig-015 — Fix Zig 0.15 Build and Formatting

## Goal

Restore `zig build all` to green on Zig 0.15.2 by fixing three trivial issues: deprecated `std.time.sleep` calls, an unused mutable variable, and formatting non-conformance.

## Scope

**Zig-only.** No Swift, web, or architecture changes. Three mechanical edits + formatter run.

## Precedence

- **Always Green** (precedence 1) — this ticket exists solely to restore green.
- **Language rules** (precedence 3) — correct Zig 0.15 API usage.

## Steps

### Step 1: Replace `std.time.sleep` with `std.Thread.sleep` in `src/codex_client.zig`

Zig 0.15 moved `sleep` from `std.time` to `std.Thread`. Two call sites:

- **Line 16** (inside `Spawn.run`): `std.time.sleep(10 * std.time.ns_per_ms)` → `std.Thread.sleep(10 * std.time.ns_per_ms)`
- **Line 64** (inside test polling loop): `std.time.sleep(5 * std.time.ns_per_ms)` → `std.Thread.sleep(5 * std.time.ns_per_ms)`

`std.time.ns_per_ms` is unchanged in 0.15 — no modification needed for the constant.

### Step 2: Change `var msg` to `const msg` in `src/App.zig`

Line 60: `var msg = cs.message;` is never mutated. Zig 0.15 treats unused mutability as an error.

Change to: `const msg = cs.message;`

### Step 3: Run `zig fmt .` to fix formatting

`src/codex_client.zig` has non-conforming indentation on the `while` loop in the test (lines 57-65). Running `zig fmt .` after steps 1-2 will auto-fix.

### Step 4: Verify with `zig build all`

Run the canonical green check. All sub-checks must pass:
- `zig build` (compile)
- `zig build test` (unit tests)
- `zig fmt --check .` (formatting)
- Linters (prettier, typos, shellcheck — skip if not installed)

### Step 5: Triage check

If any non-trivial preexisting failure surfaces during step 4, append to `docs/triage/preexisting-failures.md`. Based on research, none expected.

## Files Modified

| File | Change |
|------|--------|
| `src/codex_client.zig` | 2x `std.time.sleep` → `std.Thread.sleep` + zig fmt |
| `src/App.zig` | `var msg` → `const msg` |

## Files Created

None.

## Tests

No new tests needed. Existing tests in both files already cover the affected code paths:
- `src/codex_client.zig`: `test "streaming emits >=2 deltas then complete"` — exercises both sleep call sites
- `src/App.zig`: `test "app wakeup callback invoked on performAction"` — exercises the `msg` variable path

The fixes are API migrations, not behavior changes. The existing tests validate correctness.

## Risks

- **None material.** All three changes are mechanical with identical runtime behavior.
- `std.Thread.sleep` has the same signature as the removed `std.time.sleep` — nanoseconds in, void out.
