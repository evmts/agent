# Window Management

## Scene Definitions

The chat window is a fixed `Window` scene. The workspace panel is a second `Window` (single workspace MVP).

```swift
@main
struct SmithersApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        // Chat window (primary, pane 0 — always present)
        Window("Smithers", id: "chat") {
            ChatWindowRootView()
                .environment(appModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 900)
        .commands { appMenuCommands }

        // Workspace panel window (on-demand, shows when workspace is open)
        Window("Smithers IDE", id: "workspace") {
            IDEWindowRootView()
                .environment(appModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 900)

        // Settings
        Settings {
            SettingsView()
                .environment(appModel)
        }
    }
}
```

Future multi-workspace: workspace panel becomes `WindowGroup("Workspace", id: "workspace", for: UUID.self)`.

## WindowCoordinator

Manages the workspace panel window. Chat window is always present (managed by SwiftUI scene lifecycle).

```swift
@Observable
@MainActor
final class WindowCoordinator {
    private(set) var isWorkspacePanelVisible: Bool = false

    func showWorkspacePanel() {
        // Use NSApp.windows to find the workspace window by identifier
        // If not found, use OpenWindowAction to create it
        // If found but hidden, orderFront and makeKey
        isWorkspacePanelVisible = true
    }

    func hideWorkspacePanel() {
        // Find and orderOut the panel window
        // Do NOT close it — closing triggers SwiftUI scene teardown
        isWorkspacePanelVisible = false
    }

    func showInEditor(fileURL: URL, line: Int? = nil, column: Int? = nil) {
        showWorkspacePanel()
        // Route to workspace's TabModel and EditorStateModel
    }
}
```

**Chrome DevTools analogy:** Chat window = main Chrome window, workspace panel = DevTools. Everything is tabs — the workspace panel can show chat, diff, editor, terminal, anything.

**Window access pattern:** Access `NSWindow` via `NSApp.windows.first { $0.identifier?.rawValue == "workspace-\(id)" }` in `onAppear`. Requires retry-with-delay pattern (SwiftUI creates windows asynchronously).

## Window Chrome Setup

Both windows need:

```swift
.onAppear {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == windowId }) else { return }
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        // Install NSWindowDelegate for close guards and frame persistence
    }
}
```

## Close Behavior

**Chat window close → background the app (not quit):**
`NSWindowDelegate.windowShouldClose` hides the window but does NOT quit. Smithers continues with a menu bar icon (for scheduled agents). Quitting is explicit via Cmd+Q or menu bar icon's "Quit".

**Workspace panel close → hide:**
`windowShouldClose` returns `false`, calls `windowCoordinator.hideWorkspacePanel()`. Window hidden, not destroyed. Tab state, scroll positions, sidebar width preserved in memory.

**App termination:**
`NSApplicationDelegate.applicationShouldTerminate` returns `.terminateLater`, runs close guard, persists session state, then calls `NSApp.reply(toApplicationShouldTerminate: true)`.

## Frame Persistence

`WindowFrameStore` saves frames keyed by window type + workspace path:

```swift
enum WindowFrameStore {
    private static let frameMapKey = "smithers.windowFrames"

    static func saveFrame(_ frame: NSRect, window: WindowKind, workspace: URL?) { ... }
    static func loadFrame(window: WindowKind, workspace: URL?) -> NSRect? { ... }

    enum WindowKind: String {
        case chat
        case workspacePanel
    }
}
```

Debounced 250ms on `windowDidResize` / `windowDidMove`. Validates against current screen geometry on load.

## Default Sizing

```swift
static func defaultFrame(for kind: WindowKind, screen: NSScreen) -> NSRect {
    let visible = screen.visibleFrame
    switch kind {
    case .chat:
        let w = visible.width * 0.45
        let h = visible.height * 0.85
        let x = visible.midX - (visible.width * 0.06) - (w / 2)
        let y = visible.midY - (h / 2)
        return NSRect(x: x, y: y, width: w, height: h)
    case .workspacePanel:
        let w = visible.width * 0.55
        let h = visible.height * 0.85
        let x = visible.midX + (visible.width * 0.06) - (w / 2)
        let y = visible.midY - (h / 2)
        return NSRect(x: x, y: y, width: w, height: h)
    }
}
```
