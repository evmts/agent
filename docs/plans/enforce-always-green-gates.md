# Plan: enforce-always-green-gates

## Goal

Harden `zig build all` to be a true quality gate. No silent skips for missing lint/format tools. Xcode test step must execute tests (not just compile). Failures propagate as non-zero exit.

## Conflict Resolution

The original draft below kept `web`, `playwright`, `codex`, and `jj` optional. Validation feedback for this ticket explicitly requires non-skippable gates and flagged optional gates as false-green.

Precedence applied:
1. **Always Green** (non-skippable quality gate)
2. **Current ticket validation failures** (must be fixed)

Decision: make `web` and `playwright` hard-required in `zig build all` with actionable errors. Keep `codex` and `jj` as explicit steps until their submodule sources are initialized in this repo.

## Current State

1. **Lint tools silently skip** (lines 239-241 of `build.zig`): `prettier`, `typos`, `shellcheck` use `echo 'skipping ...'` + implicit exit 0 when not installed. None of these are currently installed locally, confirming false-green.
2. **xcode-test only builds, doesn't run** (line 193): Uses `xcodebuild build-for-testing` but never calls `test` or `test-without-building`.
3. **`all` step uses `xcode-build` not `xcode-test`** (line 252): `all_step.dependOn(xcode_build_step)` only compiles the app, never runs Xcode tests.

## Reference Pattern

Lines 260-264 already demonstrate the correct pattern for required tools (xcframework tools check): `command -v $t` with `exit 1` on missing. Lint steps should follow this pattern.

## Implementation Steps

### Step 0: Create `typos.toml` config file

**Files:** `typos.toml`

Before making `typos` mandatory, create a config file with domain-word allowlist so `typos` doesn't flag project-specific terms when first run. Words: smithers, libsmithers, smitherskit, ghosttykit, codex, jj, jujutsu, xcframework, macos, swiftui, appkit, neovim, nvim, xterm, tmux, grdb, sttextview, zap, facil, solidjs, tailwind, pnpm, treesitter, errdefer, deinit, xcresult, pbxproj, xcworkspace, xcodebuild, xcodeproj.

### Step 1: Change lint steps from skip-on-missing to fail-on-missing

**Files:** `build.zig`

Transform the three lint shell scripts from silent-skip to hard-fail with actionable install instructions.

**prettier-check** (line 239):
```bash
# BEFORE:
if command -v prettier >/dev/null 2>&1; then prettier --check .; else echo 'skipping prettier-check: prettier not installed'; fi

# AFTER:
if ! command -v prettier >/dev/null 2>&1; then echo 'ERROR: prettier not found. Install: npm install -g prettier' >&2; exit 1; fi; prettier --check .
```

**typos-check** (line 240):
```bash
# BEFORE:
if command -v typos >/dev/null 2>&1; then typos; else echo 'skipping typos-check: typos not installed'; fi

# AFTER:
if ! command -v typos >/dev/null 2>&1; then echo 'ERROR: typos not found. Install: brew install typos-cli' >&2; exit 1; fi; typos
```

**shellcheck** (line 241):
```bash
# BEFORE:
if command -v shellcheck >/dev/null 2>&1; then find ...; else echo 'skipping shellcheck: shellcheck not installed'; fi

# AFTER:
if ! command -v shellcheck >/dev/null 2>&1; then echo 'ERROR: shellcheck not found. Install: brew install shellcheck' >&2; exit 1; fi; find . -type f -name '*.sh' -exec shellcheck --severity=warning {} +; find . -type f -name '*.bash' -exec shellcheck --severity=warning {} +
```

Also update step descriptions from "skips if missing" to "fails if missing" for prettier-check, typos-check, and shellcheck.

Also convert skip-style optional scripts for `web` and `playwright` into hard-required gates.

### Step 2: Fix xcode-test to actually execute tests

**Files:** `build.zig`

Change the xcode-test shell command (line 193) from `build-for-testing` to `test`:

```bash
# BEFORE:
if [ -d macos ]; then rm -rf .build/xcode/tests.xcresult; xcodebuild build-for-testing -project macos/Smithers.xcodeproj -scheme Smithers -destination 'platform=macOS' -derivedDataPath .build/xcode; else echo "skipping xcode-test: macos/ not found"; fi

# AFTER:
if [ -d macos ]; then rm -rf .build/xcode/tests.xcresult; xcodebuild test -project macos/Smithers.xcodeproj -scheme Smithers -destination 'platform=macOS' -derivedDataPath .build/xcode -resultBundlePath .build/xcode/tests.xcresult; else echo "skipping xcode-test: macos/ not found"; fi
```

Using `xcodebuild test` (single command) rather than `build-for-testing` + `test-without-building` for simplicity. The `-resultBundlePath` captures test results for CI inspection.

### Step 3: Wire `xcode-test` into `all` step (replacing `xcode-build`)

**Files:** `build.zig`

Change line 252 from:
```zig
all_step.dependOn(xcode_build_step);
```
To:
```zig
all_step.dependOn(xcode_test_step);
```

This ensures `zig build all` runs the full test suite, not just compilation. Since `xcode-test` already depends on `xcframework` (line 207), the dependency chain is preserved. The `xcode-build` step remains available standalone for when users want a fast compile-only check.

### Step 3.5: Wire all required build/test gates into `all`

**Files:** `build.zig`

Add a hard dependency from `all` to:
- `playwright`

and keep `web` required (already depended on by `all`).

`codex` and `jj` remain explicit steps (`zig build codex`, `zig build jj`) and must fail with actionable guidance if submodule sources are not initialized.

### Step 4: Add regression test for lint tool gate behavior

**Files:** `tests/lint_tool_gate_test.sh` (new)

Shell script that validates the missing-tool gate behavior:
1. Save current PATH
2. Restrict PATH to exclude `prettier`, `typos`, `shellcheck` (keep only `/usr/bin:/bin` + zig location)
3. Run `zig build prettier-check` — expect non-zero exit and `ERROR:` in stderr
4. Run `zig build typos-check` — expect non-zero exit and `ERROR:` in stderr
5. Run `zig build shellcheck` — expect non-zero exit and `ERROR:` in stderr
6. Report PASS/FAIL per tool

This test validates the "missing tool = hard fail" contract.

### Step 5: Update existing `build_all_xcframework_single_writer_test.sh`

**Files:** `tests/build_all_xcframework_single_writer_test.sh`

This test runs `zig build all` 3 times. After our changes, `zig build all` will fail if lint tools are missing. The test itself doesn't need changing — it will naturally validate that lint tools are installed (since `zig build all` now requires them). If the test environment lacks lint tools, the test correctly fails, surfacing the issue.

No code change needed here — just verification that it still passes in a fully-provisioned environment.

### Step 6: Update web/codex/jj gate regression coverage

**Files:** `tests/web_guard_test.sh`, `tests/failing_gate_steps_test.sh`

- `web_guard_test.sh` should now assert missing `pnpm` causes `zig build web` to fail with an explicit error.
- Extend failing-step coverage to include failing `playwright`, `codex`, and `jj` paths (non-zero propagation).

### Step 7: Update docs — always-green context

**Files:** `docs/context/always-green-zig-015.md`

Update the "linters skip if tools not installed" line (line 58) to reflect new strict behavior. Change from:
```
- prettier-check, typos-check, shellcheck (skip if tools not installed)
```
To:
```
- prettier-check, typos-check, shellcheck (REQUIRED — fails with install guidance if tools missing)
```

### Step 8: Update README with required local toolchain

**Files:** `README.md`

Add a "Requirements" section listing all tools needed for `zig build all`:

```markdown
## Requirements

- [Zig](https://ziglang.org/) (0.15+)
- [prettier](https://prettier.io/) — `npm install -g prettier`
- [typos](https://github.com/crate-ci/typos) — `brew install typos-cli`
- [shellcheck](https://www.shellcheck.net/) — `brew install shellcheck`
- Xcode (for macOS app build + tests)
- Node.js + pnpm (optional, for web app: `npm install -g pnpm`)
```

## Dependency Order

```
Step 0 (typos.toml) — independent, no deps
Step 1 (lint gates) — depends on Step 0 (typos needs config before mandatory)
Step 2 (xcode-test fix) — independent of Steps 0-1
Step 3 (wire xcode-test into all) — depends on Step 2
Step 4 (gate regression test) — depends on Step 1 (tests the new behavior)
Step 5 (verify existing test) — depends on Steps 1, 2, 3 (runs after all changes)
Step 6 (web_guard_test) — no change needed
Step 7 (always-green docs) — depends on Steps 1-3 (documents final state)
Step 8 (README) — depends on Steps 1-3 (documents final state)
```

## Risks

1. **Xcode test target health unknown.** If `SmithersTests` has build or runtime failures, wiring `xcode-test` into `all` will block all development. Mitigation: verify `xcodebuild test` works before wiring into `all`. If it fails, document in `docs/triage/preexisting-failures.md` and use escape hatch (keep `xcode-build` in `all` until tests are fixed).

2. **`typos` may flag additional words.** Even with `typos.toml` allowlist, some terms may be missed. Mitigation: run `typos` locally after creating config, iterate on allowlist before making it mandatory.

3. **Existing `build_all_xcframework_single_writer_test.sh` requires all lint tools installed.** Since it runs `zig build all`, it will fail in environments without `prettier`/`typos`/`shellcheck`. This is correct behavior — the test validates the gate works. CI must provision these tools.

4. **Shell scripts may fail shellcheck.** The existing `.sh` files in `tests/` and `scripts/` may have shellcheck warnings. Must fix any findings before making shellcheck mandatory, or `zig build all` will fail. Run `shellcheck --severity=warning` on all `.sh` files as part of Step 1 validation.

5. **`prettier` may flag formatting issues.** Existing markdown/JSON/YAML files may not conform to prettier defaults. Need a `.prettierrc` or `.prettierignore` if issues arise. Run `prettier --check .` locally before making it mandatory.

## Validation

After all steps complete:

1. `zig build all` with all tools installed — must pass
2. Remove `prettier` from PATH — `zig build all` must fail with `ERROR: prettier not found. Install: npm install -g prettier`
3. Remove `typos` from PATH — same pattern
4. Remove `shellcheck` from PATH — same pattern
5. `zig build xcode-test` — must actually run tests (not just compile)
6. `tests/lint_tool_gate_test.sh` — must PASS
7. `tests/web_guard_test.sh` — must PASS (web is required and missing `pnpm` must fail explicitly)
