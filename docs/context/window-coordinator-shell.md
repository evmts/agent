# Context: window-coordinator-shell

## Ticket
Add WindowCoordinator and wire Chat "Open Editor" button to show the IDE window.

## Current State

### Files to Modify
1. **`macos/Sources/App/AppModel.swift`** — Add `windowCoordinator` property
2. **`macos/Sources/Features/Chat/Views/ChatWindowRootView.swift`** — Wire `onOpenEditor` callback to coordinator
3. **`macos/Sources/Features/Chat/Views/ChatTitleBarZone.swift`** — Already done: has `onOpenEditor` closure, `accessibilityIdentifier("open_editor")`, reads `@Environment(AppModel.self)`
4. **`macos/Sources/Features/IDE/Views/IDEWindowRootView.swift`** — Flesh out stub so it's visible

### Files to Create
1. **`macos/Sources/App/WindowCoordinator.swift`** — New `@Observable @MainActor` class
2. **`macos/SmithersTests/WindowCoordinatorTests.swift`** — Unit test (optional — see gotchas)

### Xcode Project Changes
- New source files must be added to `project.pbxproj` (PBXFileReference, PBXGroup, PBXBuildFile)
- App target source build phase: `A00000000000000000000007`
- Test target source build phase: `B11111111111111111111113`
- App group for `App/`: `A00000000000000000000018` — currently has SmithersApp.swift + AppModel.swift

## Key Patterns from Codebase

### @Environment injection (established pattern)
```swift
// In views:
@Environment(AppModel.self) private var appModel
@Environment(\.theme) private var theme

// In SmithersApp.swift:
ChatWindowRootView()
    .environment(appModel)
    .environment(\.theme, appModel.theme)
```

### @Observable pattern (AppModel)
```swift
@Observable @MainActor
final class AppModel {
    var theme: AppTheme = .dark
    var workspaceName: String = "Smithers"
}
```

### ChatTitleBarZone (already wired, just needs real callback)
```swift
struct ChatTitleBarZone: View {
    let onOpenEditor: () -> Void
    // ... uses onOpenEditor in IconButton action
}
```

### ChatWindowRootView (TODO stub at line 12)
```swift
ChatTitleBarZone(onOpenEditor: { /* TODO: wire WindowCoordinator */ })
```

## SwiftUI Window Opening API

### `@Environment(\.openWindow)` — macOS 13+
```swift
struct ContentView: View {
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button("Show Window") {
            openWindow(id: "workspace")  // matches Window("...", id: "workspace")
        }
    }
}
```

### Key Gotcha: `openWindow` is an Environment value, only available inside Views
- WindowCoordinator can't directly use `@Environment(\.openWindow)` because it's a plain class, not a View
- **Two approaches:**
  1. Pass `openWindow` action into WindowCoordinator from the View
  2. Use NSApp.windows directly (AppKit approach, bypasses SwiftUI)
  3. Have the View call openWindow directly, coordinator just tracks state

### `NSApp.windows` approach (v1 pattern, AppKit)
```swift
// Find window by identifier
NSApp.windows.first { $0.identifier?.rawValue == "workspace" }
// Show existing: window.orderFront(nil); window.makeKeyAndOrderFront(nil)
```

**Important:** SwiftUI `Window` scenes assign identifiers automatically based on the `id:` parameter. The NSWindow identifier for `Window("Smithers IDE", id: "workspace")` should be accessible, but the exact identifier format may vary. Testing required.

### Recommended Approach for This Ticket
The simplest correct approach: **have the View hold `@Environment(\.openWindow)` and pass it to the coordinator** or call it directly. The coordinator tracks `isWorkspacePanelVisible` state.

Per spec, WindowCoordinator should expose:
```swift
@Observable @MainActor
final class WindowCoordinator {
    private(set) var isWorkspacePanelVisible: Bool = false

    func showWorkspacePanel() {
        isWorkspacePanelVisible = true
        // Actual window opening delegated to view layer
    }
}
```

But for **this ticket** (minimal shell), the simplest approach is:
1. WindowCoordinator owns state + has a method to trigger open
2. ChatWindowRootView reads `appModel.windowCoordinator` and passes the action
3. ChatWindowRootView uses `@Environment(\.openWindow)` to do the actual SwiftUI window open

## v1 Reference Patterns

### CloseGuard (window delegate, frame persistence)
- `prototype0/Smithers/CloseGuard.swift` — `WindowCloseDelegate: NSObject, NSWindowDelegate`
- Uses `windowShouldClose` to intercept close, `windowDidMove`/`windowDidResize` for frame persistence
- 250ms debounce on frame saves

### Window Access
```swift
// v1 pattern:
NSApp.windows.first(where: { $0.isKeyWindow || $0.isMainWindow })
```

## Test Infrastructure

### Existing Test Pattern
```swift
// macos/SmithersTests/ChatViewTests.swift
import XCTest
@testable import Smithers

final class ChatViewTests: XCTestCase {
    func testSidebarMode_allCasesAndIcons() {
        XCTAssertEqual(SidebarMode.allCases.count, 3)
    }
}
```

Also uses Swift Testing framework:
```swift
// macos/SmithersTests/SmithersTests.swift
import Testing
import SmithersKit

@Suite struct SmithersTests {
    @Test func smithersKitLinking() { ... }
}
```

### Adding New Test File to Xcode Project
Must add to `project.pbxproj`:
1. `PBXFileReference` in file refs section
2. `PBXBuildFile` in build files section
3. Add to Tests `PBXGroup` (`B1111111111111111111111B`)
4. Add to SmithersTests Sources build phase (`B11111111111111111111113`)

### Test Gotcha: WindowCoordinator Unit Tests
WindowCoordinator is mostly stateful — `isWorkspacePanelVisible` toggle. For the ticket's test plan ("unit test: instantiate ChatTitleBarZone with a test closure and assert it's invoked"), we can:
- Test that ChatTitleBarZone's `onOpenEditor` closure is called (ViewInspector or just test the closure pattern)
- Test WindowCoordinator state: `showWorkspacePanel()` sets `isWorkspacePanelVisible = true`
- Cannot test actual NSWindow behavior in unit tests (requires running app)

## IDEWindowRootView Enhancement

Current stub is minimal. For this ticket, flesh out enough to be visually recognizable:
- Add `@Environment(AppModel.self)` and `@Environment(\.theme)`
- Show themed background with centered label
- Use design tokens for consistency

## Build Verification

```bash
# Must pass after changes:
zig build all                    # Zig checks
scripts/xcode_build_and_open.sh  # Xcode build + launch

# Test:
xcodebuild test \
  -project macos/Smithers.xcodeproj \
  -scheme SmithersTests \
  -derivedDataPath .build/xcode
```

## Gotchas / Pitfalls

1. **SwiftUI Window ID vs NSWindow identifier**: SwiftUI's `Window("title", id: "workspace")` creates windows, but the NSWindow.identifier may not match the SwiftUI id exactly. For this ticket, prefer `@Environment(\.openWindow)` over NSApp.windows lookup.

2. **openWindow called multiple times**: `openWindow(id: "workspace")` when window already visible should be safe (SwiftUI brings it to front). WindowCoordinator should handle idempotent calls.

3. **Xcode project file**: Every new .swift file needs manual pbxproj edits (PBXFileReference + PBXBuildFile + PBXGroup membership + Sources build phase). Miss any = build fails. Use existing UUIDs as reference for format.

4. **@MainActor consistency**: WindowCoordinator must be `@MainActor` (window operations are main-thread). AppModel already is.

5. **Test target host app**: SmithersTests uses `TEST_HOST` and `BUNDLE_LOADER` pointing to `Smithers.app`. Tests can use `@testable import Smithers`. Testing SwiftUI views directly is hard; test the coordinator state instead.
