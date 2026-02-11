# Preexisting Failures

## 2026-02-11 — zig build all fails in xcode-test (missing SmithersKit.xcframework)

- Command: zig build all
- Failure: Xcode test step reports: There is no XCFramework found at /Users/williamcory/agent/dist/SmithersKit.xcframework.
- Observations: Running zig build all can race the xcode-test step before the xcframework step fully materializes the artifact. A subsequent run shows the xcframework directory exists at the expected path, but the earlier test invocation still failed.
- Evidence: See /tmp/zig_all2.out in this validation and ls dist/SmithersKit.xcframework shows present after failure.
- Suspected root cause: Step ordering/parallelization in build.zig. Although xcode-test depends on xcframework, execution logs indicate the test may start before the artifact is on disk.
- Proposed fix: Ensure strict serialization: keep xcode_test_step.dependOn(xc_step) and avoid running web_step (or other independent steps) before xc_step completes; or make xcode-test a script that verifies/creates dist/SmithersKit.xcframework (runs zig build xcframework if missing) before invoking xcodebuild.
- Scope: Unrelated to current ticket (ide-file-tree-shell).
