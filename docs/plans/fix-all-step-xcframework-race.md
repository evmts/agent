# Plan: fix-all-step-xcframework-race

## Scope

Stabilize `zig build all` by removing the race between `xcframework` production and Xcode consumption of `dist/SmithersKit.xcframework`.

Layers in scope:
- Zig build graph (`build.zig`)
- Xcode project build phase (`macos/Smithers.xcodeproj/project.pbxproj`)
- Build validation scripts/log checks (`tests/`)
- Build/triage docs (`README.md`, `docs/triage/preexisting-failures.md`)

## Conflict Resolution

Detected conflict:
- Existing fallback behavior in `build.zig` and Xcode build phase can each invoke `zig build xcframework` for convenience.
- Current ticket requires deterministic ordering and no concurrent re-create/delete of `dist/SmithersKit.xcframework`.

Resolution:
- Precedence applied: **Always Green (1)** and **Current ticket (4)** over convenience fallback behavior.
- Plan removes multi-writer fallback paths from the `zig build all` path and enforces explicit dependency edges.

## Implementation Steps (Atomic, Ordered)

### Step 0 — Plan artifact (this file)
- Layer: docs
- Files:
  - `docs/plans/fix-all-step-xcframework-race.md`
- Outcome:
  - Locked execution order and file-level scope before edits.

### Step 1 — Add deterministic race regression test script
- Layer: zig
- Files:
  - `tests/build_all_xcframework_single_writer_test.sh` (new)
- Change:
  - Add a shell integration script that:
    1. Removes `dist/SmithersKit.xcframework`
    2. Runs `zig build all` once (must pass)
    3. Runs `zig build all` 3 consecutive times
    4. Fails if logs contain xcframework code-70 signatures
- Why first:
  - Satisfies test-first ordering and provides repeatable acceptance validation.

### Step 2 — Serialize build DAG so Xcode build is a strict consumer of xcframework
- Layer: zig
- Files:
  - `build.zig`
- Change:
  - Add hard edge: `xcode_build_step.dependOn(xc_step)`.
  - Make `all` depend on `xcode-build` (consumer) and remove redundant sibling ordering that leaves intent ambiguous.
  - Ensure no `all` dependency branch can mutate `dist/SmithersKit.xcframework` while `xcode-build` is running.

### Step 3 — Remove nested xcframework rebuild fallback from `xcode-build` shell step
- Layer: zig
- Files:
  - `build.zig`
- Change:
  - Remove inline fallback `if missing -> zig build xcframework` from the `xcode-build` script body.
  - Keep xcode invocation as pure consumer because dependency graph now guarantees producer completion.

### Step 4 — Make Xcode project phase verify-only (no recursive producer call)
- Layer: zig
- Files:
  - `macos/Smithers.xcodeproj/project.pbxproj`
- Change:
  - Update `Verify SmithersKit.xcframework` shell phase to fail fast with actionable error if missing, and stop invoking `zig build xcframework`.
  - Keep stamp write for incremental behavior.
- Why:
  - Ensures a single producer in normal flows and eliminates hidden recursive writes during Xcode builds.

### Step 5 — Validate canonical green path and ticket acceptance checks
- Layer: zig
- Files:
  - `tests/build_all_xcframework_single_writer_test.sh`
- Commands:
  - `zig build all`
  - `rm -rf dist/SmithersKit.xcframework && zig build all`
  - `tests/build_all_xcframework_single_writer_test.sh`
- Pass criteria:
  - Three consecutive `zig build all` runs succeed.
  - First run from clean xcframework succeeds.
  - No code-70 xcframework race signatures in produced logs.

### Step 6 — Update docs after tests are green
- Layer: docs
- Files:
  - `docs/triage/preexisting-failures.md`
  - `README.md`
- Change:
  - Append resolution note in triage doc with date, root cause, and fix summary.
  - Update build docs to state deterministic ordering (`xcframework` materialized before Xcode build in `zig build all`).

## Acceptance Mapping

- `zig build all` succeeds 3 consecutive runs from clean:
  - Covered by Step 5 script + direct command.
- `rm -rf dist/SmithersKit.xcframework && zig build all` succeeds:
  - Covered by Step 5 direct command.
- No code-70 race remains:
  - Covered by Step 5 log scan in script.
- Docs updated:
  - Covered by Step 6.

## Risks and Mitigations

1. Risk: Removing fallback in pbxproj may break direct Xcode-only invocation from a clean repo.
   - Mitigation: Verify phase emits explicit remediation (`run zig build xcframework`), and `zig build all`/`zig build xcode-build` remain deterministic.

2. Risk: Over-constraining dependencies could unintentionally skip standalone `zig build xcframework`.
   - Mitigation: Keep `xcframework` step independently invokable and only serialize consumer steps.

3. Risk: Log-signature checks may miss new failure wording.
   - Mitigation: Scan for both `code 70` and `all -> xcframework` failure patterns in regression script.
