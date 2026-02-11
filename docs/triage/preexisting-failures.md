# Pre-existing Failures (Escape Hatch Log)

Date: 2026-02-10

- Issue: `xcodebuild -list -project macos/Smithers.xcodeproj` fails with `NSCocoaErrorDomain Code=3840` (JSON parse error: “JSON text did not start with array or object”).
- Impact: Blocks `xcodebuild test` discovery; unrelated to chat window shell logic.
- Attempts:
  - Validated `project.pbxproj` structure; schemes present; no `Package.resolved` in swiftpm path.
  - Rebuilt `project.xcworkspace/xcshareddata` with a minimal valid `WorkspaceSettings.xcsettings`.
  - Inspected workspace and scheme XML; error persists.
- Notes: The error indicates Xcode is parsing a JSON file (likely SwiftPM metadata) that is missing or malformed despite no `swiftpm` folder present. This requires deeper Xcode project diagnosis beyond this ticket’s scope.
- Next steps (separate ticket): Regenerate or repair Xcode workspace metadata; ensure `Package.resolved` and `WorkspaceSettings.xcsettings` are valid; confirm `xcodebuild -list` succeeds.

Date: 2026-02-11

- Note: No pre-existing Zig build/test/format failures required the escape hatch for this ticket.
