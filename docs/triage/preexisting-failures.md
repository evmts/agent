# Pre-existing Failures (documented 2026-02-11)

## Xcode project parse error blocks Swift unit tests
- Symptom: `xcodebuild -project macos/Smithers.xcodeproj -scheme Smithers test` fails with:
  - “The project ‘Smithers’ is damaged and cannot be opened due to a parse error.”
- Root cause: `macos/Smithers.xcodeproj/project.pbxproj` has malformed PBXGroup entries under `Features/Chat` (missing closing braces/children terminators). This predates this ticket and is non-trivial to repair without rehydrating group structure.
- Impact: Unable to run `xcodebuild test` for Swift tests, including new `ChatHistoryStoreTests`.
- Scope decision: Non-trivial and orthogonal to current ticket (chat persistence via GRDB). Tracked here and should be fixed in a dedicated ticket (see `docs/plans/fix-xcodeproj-parse-error.md`).

## Missing GRDB dependency in Xcode project
- Symptom: New file `ChatHistoryStore.swift` imports `GRDB`, but the Xcode project currently has no SwiftPM package entries.
- Fix needed: Add SPM package for GRDB to `Smithers.xcodeproj` (XCRemoteSwiftPackageReference + XCSwiftPackageProductDependency) and link the product in the app + tests targets.
- Impact: Compilation of the macOS target will fail until GRDB is added. Does not impact `zig build all` (canonical green) since Xcode build steps are not wired yet.

## Current status for this ticket
- Implemented `ChatHistoryStore` and tests per spec using GRDB and schema parity with Zig (`src/storage.zig`).
- Verified Zig storage tests are green: `zig test src/storage.zig` → 7/7 passing.
- Verified `zig build all` is green. Web build runs; Xcode steps are not wired yet.

## Proposed follow-up ticket
- Title: “Repair `Smithers.xcodeproj` structure and add GRDB SwiftPM dependency.”
- Tasks:
  1. Fix malformed PBXGroup entries in `project.pbxproj` (Features/Chat subtree).
  2. Add Swift Package dependency for GRDB (minimum version to match macOS 14 + Swift 6).
  3. Link GRDB product to app + test targets.
  4. Re-run `xcodebuild test` and ensure all Swift tests pass.
