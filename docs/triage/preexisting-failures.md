# Preexisting Failures

## 2026-02-11 — zig build all fails in xcode-test (missing SmithersKit.xcframework)

- Command: zig build all
- Failure: Xcode test step reports: There is no XCFramework found at /Users/williamcory/agent/dist/SmithersKit.xcframework.
- Observations: Running zig build all can race the xcode-test step before the xcframework step fully materializes the artifact. A subsequent run shows the xcframework directory exists at the expected path, but the earlier test invocation still failed.
- Evidence: See /tmp/zig_all2.out in this validation and ls dist/SmithersKit.xcframework shows present after failure.
- Suspected root cause: Step ordering/parallelization in build.zig. Although xcode-test depends on xcframework, execution logs indicate the test may start before the artifact is on disk.
- Proposed fix: Ensure strict serialization: keep xcode_test_step.dependOn(xc_step) and avoid running web_step (or other independent steps) before xc_step completes; or make xcode-test a script that verifies/creates dist/SmithersKit.xcframework (runs zig build xcframework if missing) before invoking xcodebuild.
- Scope: Unrelated to current ticket (ide-file-tree-shell).

## 2026-02-12 — resolved: xcframework multi-writer race in `zig build all`

- Command: `zig build all` after clean xcframework output
- Root cause: Multiple build paths could write `dist/SmithersKit.xcframework` (`all -> xcframework`, nested `zig build xcframework` fallback in `xcode-build`, and Xcode verify-phase fallback).
- Fix applied:
  - `xcode-build` now strictly depends on `xcframework` through command-step ordering.
  - Nested fallback rebuilds were removed from `xcode-build`/`xcode-test`.
  - Xcode `Verify SmithersKit.xcframework` phase is verify-only and no longer rebuilds.
  - Added regression script: `tests/build_all_xcframework_single_writer_test.sh` (3 clean `zig build all` runs).
- Validation: clean-output reproduction and repeated runs pass without `xcodebuild -create-xcframework` exit code 70.
