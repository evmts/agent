# Plan: window-coordinator-shell

## Ticket
Add WindowCoordinator and wire Chat "Open Editor" button to show the IDE window.

## Acceptance Criteria
- App builds; clicking "Open Editor" in Chat title bar shows the IDE window.
- `WindowCoordinator.showWorkspacePanel()` is idempotent (no crash when already visible).
- `ChatTitleBarZone` compiles with environment injection and has accessibility identifier `"open_editor"` (already done).
- `xcodebuild build` and `zig build all` pass.

## Architecture Decision

**Approach:** The View (`ChatWindowRootView`) holds `@Environment(\.openWindow)` and calls it directly. `WindowCoordinator` is an `@Observable @MainActor` class owned by `AppModel` that tracks `isWorkspacePanelVisible` state. The coordinator does NOT hold the `openWindow` action — that's a SwiftUI environment value only available in View context.

**Flow:**
1. User clicks "Open Editor" button in `ChatTitleBarZone`
2. `onOpenEditor` closure fires
3. `ChatWindowRootView` calls `appModel.windowCoordinator.showWorkspacePanel()`
4. Coordinator sets `isWorkspacePanelVisible = true`
5. View also calls `openWindow(id: "workspace")` to actually open the SwiftUI window

This separation means the coordinator tracks state (useful for other features: "is IDE open?") while the view layer handles the SwiftUI-specific window opening API.

## Implementation Steps

### Step 0: Write plan document
- **File:** `docs/plans/window-coordinator-shell.md` (this file)

### Step 1: Create WindowCoordinator.swift
- **File (create):** `macos/Sources/App/WindowCoordinator.swift`
- **Layer:** Swift
- **Details:**
  - `@Observable @MainActor final class WindowCoordinator`
  - `private(set) var isWorkspacePanelVisible: Bool = false`
  - `func showWorkspacePanel()` — sets `isWorkspacePanelVisible = true` (idempotent)
  - `func hideWorkspacePanel()` — sets `isWorkspacePanelVisible = false`
  - Per spec §1.1/§5.3.1: coordinator manages show/hide/focus of workspace panel

### Step 2: Write WindowCoordinator tests (TDD)
- **File (create):** `macos/SmithersTests/WindowCoordinatorTests.swift`
- **Layer:** Swift tests
- **Details:**
  - Test `showWorkspacePanel()` sets `isWorkspacePanelVisible = true`
  - Test `showWorkspacePanel()` is idempotent (calling twice still true, no crash)
  - Test `hideWorkspacePanel()` sets `isWorkspacePanelVisible = false`
  - Test initial state is `false`
  - `@MainActor` annotation required (WindowCoordinator is MainActor)

### Step 3: Add windowCoordinator to AppModel
- **File (modify):** `macos/Sources/App/AppModel.swift`
- **Layer:** Swift
- **Details:**
  - Add `let windowCoordinator = WindowCoordinator()` property
  - `let` because the coordinator instance is stable; its internal state is `@Observable`

### Step 4: Wire ChatWindowRootView to open IDE window
- **File (modify):** `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift`
- **Layer:** Swift
- **Details:**
  - Add `@Environment(\.openWindow) private var openWindow`
  - Replace `onOpenEditor: { /* TODO */ }` with closure that:
    1. Calls `appModel.windowCoordinator.showWorkspacePanel()`
    2. Calls `openWindow(id: "workspace")`
  - This wires the actual SwiftUI window opening + coordinator state tracking

### Step 5: Flesh out IDEWindowRootView
- **File (modify):** `macos/Sources/Features/IDE/Views/IDEWindowRootView.swift`
- **Layer:** Swift
- **Details:**
  - Add `@Environment(AppModel.self)` and `@Environment(\.theme)` (match Chat pattern)
  - Show themed background (`theme.background`)
  - Centered label "Smithers IDE" with `DS.Typography.xl` and `theme.foregroundColor`
  - Subtle "workspace" identifier text below in `DS.Typography.s` / `theme.mutedForeground`
  - Accessibility identifier `"ide_window_root"` on the root
  - Enough to visually confirm the window opened when clicking "Open Editor"

### Step 6: Add new files to project.pbxproj
- **File (modify):** `macos/Smithers.xcodeproj/project.pbxproj`
- **Layer:** Xcode project
- **Details:**
  - **WindowCoordinator.swift:**
    - PBXFileReference: `WC0000000000000000000001` → `WindowCoordinator.swift`
    - PBXBuildFile (app): `WC0000000000000000000002` → in Sources build phase `A00000000000000000000007`
    - Add to App PBXGroup `A00000000000000000000018`
  - **WindowCoordinatorTests.swift:**
    - PBXFileReference: `WC0000000000000000000003` → `WindowCoordinatorTests.swift`
    - PBXBuildFile (tests): `WC0000000000000000000004` → in Tests Sources build phase `B11111111111111111111113`
    - Add to Tests PBXGroup `B1111111111111111111111B`
    - Also add WindowCoordinator.swift to test target: `WC0000000000000000000005` (so @testable import works with host app, but since TEST_HOST is set, the test target loads the app binary — so we DON'T need to add source files to test target separately)

### Step 7: Verify build passes
- **Commands:**
  - `zig build all` — Zig checks pass
  - `xcodebuild build -project macos/Smithers.xcodeproj -scheme Smithers -derivedDataPath .build/xcode` — Swift compiles
  - `xcodebuild test -project macos/Smithers.xcodeproj -scheme SmithersTests -derivedDataPath .build/xcode` — Tests pass

## Files Summary

### Create
1. `macos/Sources/App/WindowCoordinator.swift`
2. `macos/SmithersTests/WindowCoordinatorTests.swift`

### Modify
1. `macos/Sources/App/AppModel.swift` — add windowCoordinator property
2. `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` — wire openWindow
3. `macos/Sources/Features/IDE/Views/IDEWindowRootView.swift` — themed stub
4. `macos/Smithers.xcodeproj/project.pbxproj` — register new files

## Risks
1. **SwiftUI `openWindow` idempotency** — calling `openWindow(id:)` when window already visible should be safe (brings to front), but behavior needs verification at runtime. Mitigation: the coordinator state check is there; if needed, guard with `if !isWorkspacePanelVisible`.
2. **project.pbxproj manual edits** — easy to break Xcode project. Mitigation: follow exact patterns from existing entries, verify with `xcodebuild build` immediately.
3. **Swift 6 strict concurrency** — `@MainActor` on coordinator + `@MainActor` test annotation must be consistent. Build setting `SWIFT_STRICT_CONCURRENCY = complete` is enabled. Mitigation: test function must be `@MainActor`.
4. **Test target file visibility** — Tests use `TEST_HOST` + `BUNDLE_LOADER` + `@testable import Smithers`, so test target accesses app internals via host app binary. New source files only need to be in app target, not duplicated in test target.
