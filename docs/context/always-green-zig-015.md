# Research Context: always-green-zig-015

## Summary

Three issues block `zig build all` on Zig 0.15.2. All are straightforward fixes with no architectural impact.

## Issue 1: `std.time.sleep` removed in Zig 0.15

**Error:** `src/codex_client.zig:16:29: error: root source file struct 'time' has no member named 'sleep'`

In Zig 0.15, `std.time.sleep` was moved to `std.Thread.sleep`. The function signature is identical:

```zig
// /Users/williamcory/.zvm/0.15.2/lib/std/Thread.zig line 26
pub fn sleep(nanoseconds: u64) void {
```

`std.time.ns_per_ms` still exists at `/Users/williamcory/.zvm/0.15.2/lib/std/time.zig:81`.

**Fix:** Replace `std.time.sleep(...)` with `std.Thread.sleep(...)` at two locations:
- `src/codex_client.zig:16` — inside `Spawn.run()` (production stub)
- `src/codex_client.zig:64` — inside test polling loop

## Issue 2: Unused mutable variable in `src/App.zig`

**Error:** `src/App.zig:60:17: error: local variable is never mutated`

```zig
// src/App.zig:60
var msg = cs.message;  // should be const
```

**Fix:** Change `var msg` to `const msg` at line 60.

## Issue 3: Formatting non-conformance in `src/codex_client.zig`

**Error:** `zig fmt --check` reports `src/codex_client.zig: non-conforming formatting`

The while loop at lines 57-65 has incorrect indentation (extra leading whitespace on `while` keyword and closing brace compared to surrounding code at the same nesting level).

**Fix:** Run `zig fmt src/codex_client.zig` after applying the `std.time.sleep` → `std.Thread.sleep` changes. The formatter will fix indentation.

## Files to Modify

1. **`src/codex_client.zig`** — 2 sleep replacements + run zig fmt
2. **`src/App.zig`** — 1 var→const change

## Verification

```bash
zig build all  # Must pass cleanly (build + test + fmt-check + linters)
```

The `zig build all` step runs (in parallel):
- `zig build` (compile lib + exe)
- `zig build test` (unit tests for lib module + exe module)
- `zig fmt --check .` (formatting)
- prettier-check, typos-check, shellcheck (skip if tools not installed)
- web build, codex build, jj build (skip if dirs not present)
- C header compile smoke test

## Key API Reference

```zig
// Zig 0.15 — sleep is on Thread, not time
std.Thread.sleep(nanoseconds: u64) void  // CORRECT in 0.15
std.time.sleep(...)                       // REMOVED in 0.15

// Constants unchanged
std.time.ns_per_ms  // = 1_000_000 (still in std.time)
```

## No Preexisting Failures Expected

All three issues are trivially fixable. No escape hatch entry needed unless something unexpected surfaces during verification.
