# Research Context: enforce-always-green-gates

## Summary

`zig build all` currently silently skips `prettier`, `typos`, and `shellcheck` when not installed (prints "skipping X: X not installed" and exits 0). The `xcode-test` step only runs `build-for-testing`, not actual test execution. The `all` step depends on `xcode-build` (build-only), not `xcode-test`. This ticket hardens all three areas so `zig build all` is a true quality gate.

Validation follow-up also requires eliminating skip-style false-green paths for `web` and `playwright` in `all`, plus ensuring `codex`/`jj` explicit steps are real wrappers (not no-op scaffolds).

## Problem Analysis

### 1. Lint/format tools silently skip (false-green)

Lines 239-241 of `build.zig` use `addOptionalShellStep` with `command -v` guards that print "skipping" and exit 0:

```zig
// build.zig:239-241 (current)
const prettier_check_step = addOptionalShellStep(b, "prettier-check", "...",
  "if command -v prettier >/dev/null 2>&1; then prettier --check .; else echo 'skipping prettier-check: prettier not installed'; fi");
const typos_check_step = addOptionalShellStep(b, "typos-check", "...",
  "if command -v typos >/dev/null 2>&1; then typos; else echo 'skipping typos-check: typos not installed'; fi");
const shellcheck_step = addOptionalShellStep(b, "shellcheck", "...",
  "if command -v shellcheck >/dev/null 2>&1; then find . -type f -name '*.sh' -exec shellcheck --severity=warning {} +; ...; else echo 'skipping shellcheck: shellcheck not installed'; fi");
```

**Local environment**: None of `prettier`, `typos`, `shellcheck` are currently installed — `zig build all` silently skips ALL lint checks.

### 2. xcode-test step only builds, doesn't run tests

Line 193:
```
"if [ -d macos ]; then rm -rf .build/xcode/tests.xcresult; xcodebuild build-for-testing -project macos/Smithers.xcodeproj -scheme Smithers -destination 'platform=macOS' -derivedDataPath .build/xcode; else echo \"skipping xcode-test: macos/ not found\"; fi"
```

This runs `build-for-testing` — compiles tests but does NOT execute them. To actually run tests, it should use `xcodebuild test` or `xcodebuild test-without-building` (after build-for-testing).

### 3. `all` step depends on `xcode-build`, not `xcode-test`

Line 252: `all_step.dependOn(xcode_build_step);` — the `all` step only builds the Xcode app, never runs Xcode tests.

## Key Files to Modify

| File | Change |
|------|--------|
| `build.zig` | Change lint tool steps from skip-on-missing to fail-on-missing; wire `xcode-test` into `all`; fix xcode-test to actually run tests |
| `README.md` | Document required local toolchain (prettier, typos, shellcheck) |
| `docs/context/always-green-zig-015.md` | Update to reflect strict gate behavior |
| `tests/build_all_xcframework_single_writer_test.sh` | Update/extend for new gate behavior validation |

## Reference Patterns

### Pattern 1: xcframework tools check (CORRECT — fail on missing)

Lines 260-264 of `build.zig` already demonstrate the RIGHT pattern for required tools:
```zig
const xc_tools_check = b.addSystemCommand(&.{
    "sh", "-c",
    "for t in libtool lipo xcodebuild; do if ! command -v $t >/dev/null 2>&1; then echo 'xcframework: missing' $t >&2; exit 1; fi; done",
});
```
This fails with exit 1 and clear message when tools are missing. The lint steps should follow this pattern.

### Pattern 2: addOptionalShellStep helper (build.zig:17-27)

```zig
fn addOptionalShellStep(b: *std.Build, name: []const u8, description: []const u8, script: []const u8) *std.Build.Step {
    const step = b.step(name, description);
    const cmd = b.addSystemCommand(&.{ "sh", "-c", script });
    step.dependOn(&cmd.step);
    return step;
}
```

This is a generic helper — the "optional" behavior comes from the shell script body, not the Zig step infrastructure. For required tools, either:
- Change the shell script to `exit 1` on missing tool (simplest)
- Or create a new `addRequiredShellStep` helper

### Pattern 3: Existing test scripts

`tests/web_guard_test.sh` tests the CURRENT skip behavior (expects "skipping web: pnpm not installed"). This test will need updating since the behavior changes from skip to fail.

`tests/build_all_xcframework_single_writer_test.sh` runs 3 clean `zig build all` cycles — this should still pass after changes (assuming tools are installed).

## Implementation Approach

### Lint tool gates

For each of `prettier`, `typos`, `shellcheck`:
- Change from `echo 'skipping ...' (exit 0)` to `echo 'ERROR: ... Install with: brew install ...' >&2; exit 1`
- Include actionable install instructions in the error message

Example transformation:
```bash
# BEFORE (silently skips):
if command -v prettier >/dev/null 2>&1; then prettier --check .; else echo 'skipping prettier-check: prettier not installed'; fi

# AFTER (fails with guidance):
if ! command -v prettier >/dev/null 2>&1; then echo 'ERROR: prettier not found. Install: npm install -g prettier' >&2; exit 1; fi; prettier --check .
```

### Xcode test execution

The xcode-test step should actually run tests. Two approaches:

**Option A**: Change `build-for-testing` to `test` (simpler, single command):
```bash
xcodebuild test -project macos/Smithers.xcodeproj -scheme Smithers -destination 'platform=macOS' -derivedDataPath .build/xcode
```

**Option B**: Keep build-for-testing + add test-without-building (better for CI caching):
```bash
xcodebuild build-for-testing ... && xcodebuild test-without-building ...
```

Then wire `xcode-test` into `all` step alongside (or replacing) `xcode-build`.

### Test file changes

1. **New test**: `tests/lint_tool_gate_test.sh` — removes one lint tool from PATH, runs `zig build all`, expects failure with guidance message.
2. **Existing**: `tests/build_all_xcframework_single_writer_test.sh` — should still pass (no regression) when run in fully provisioned environment.
3. **Existing**: `tests/web_guard_test.sh` — web/playwright are required gates in `all`; missing `pnpm` must fail with an explicit install hint.

## Zig Build API Reference (verified against 0.15.2 stdlib)

```zig
// /Users/williamcory/.zvm/0.15.2/lib/std/Build.zig:925
pub fn addSystemCommand(b: *Build, argv: []const []const u8) *Step.Run

// /Users/williamcory/.zvm/0.15.2/lib/std/Build/Step/Run.zig:530
pub fn expectExitCode(run: *Run, code: u8) void

// /Users/williamcory/.zvm/0.15.2/lib/std/Build.zig:1052
pub fn addFmt(b: *Build, options: Step.Fmt.Options) *Step.Fmt
```

All APIs verified in `/Users/williamcory/.zvm/0.15.2/lib/std/`.

## Gotchas / Pitfalls

1. **web_guard_test.sh will break** — It currently asserts "skipping web: pnpm not installed" message. With strict gates, test must assert hard failure + actionable message.

2. **xcode-test in `all` may be slow** — Running actual Xcode tests adds significant time to `zig build all`. Consider whether `all` should run `xcode-test` (with actual test execution) or `xcode-build` (compile only, faster). The ticket says "executes Zig tests and Xcode test execution steps" — so yes, `all` should include test execution.

3. **Shell scripts may not exist for shellcheck** — The shellcheck step uses `find . -name '*.sh'`. If there are no `.sh` files, shellcheck has nothing to check and exits 0. Currently there ARE shell files in `tests/` and `scripts/`. But the `.sh` extension detection should be verified.

4. **Xcode test infrastructure** — Xcode tests require the test target to be properly configured in `project.pbxproj`. If SmithersTests target has build issues, this will block `zig build all`. Check current state of test target before wiring.

5. **`addOptionalShellStep` naming** — After making lint steps mandatory, the function name `addOptionalShellStep` is misleading for them. Consider either renaming or using `addSystemCommand` directly for mandatory steps.

## Open Questions

1. **Does `xcodebuild test` currently pass?** The Xcode project has had parse/configuration issues documented in triage. If tests don't pass, wiring them into `all` immediately will block all development. May need to verify test target health first.

2. **`typos.toml` doesn't exist** — The always-green spec mentions "configure typos.toml for domain words" but no `typos.toml` exists. When typos becomes mandatory, it may flag domain-specific words (Smithers, libsmithers, etc.) as typos. A `typos.toml` allowlist should be created.
