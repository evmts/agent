# Window Management

## Scene Definitions

Chat = fixed `Window`. Workspace panel = second `Window` (single workspace MVP).

```swift
@main
struct SmithersApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        // Chat (primary, pane 0 — always present)
        Window("Smithers", id: "chat") {
            ChatWindowRootView().environment(appModel)
        }
        .windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
        .defaultSize(width: 800, height: 900).commands { appMenuCommands }

        // Workspace panel (on-demand, shows when workspace open)
        Window("Smithers IDE", id: "workspace") {
            IDEWindowRootView().environment(appModel)
        }
        .windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 900)

        Settings { SettingsView().environment(appModel) }
    }
}
```

Future multi-workspace: panel → `WindowGroup("Workspace", id: "workspace", for: UUID.self)`

## WindowCoordinator

Manages workspace panel. Chat always present (SwiftUI scene lifecycle).

```swift
@Observable @MainActor
final class WindowCoordinator {
    private(set) var isWorkspacePanelVisible: Bool = false

    func showWorkspacePanel() {
        // NSApp.windows find by identifier → if not found OpenWindowAction create
        // If found but hidden → orderFront+makeKey
        isWorkspacePanelVisible = true
    }

    func hideWorkspacePanel() {
        // Find+orderOut panel. Do NOT close (triggers scene teardown)
        isWorkspacePanelVisible = false
    }

    func showInEditor(fileURL: URL, line: Int? = nil, column: Int? = nil) {
        showWorkspacePanel()
        // Route to workspace TabModel+EditorStateModel
    }
}
```

**Chrome DevTools analogy:** Chat = main Chrome, workspace panel = DevTools. Everything = tabs (chat, diff, editor, terminal, anything).

**Window access:** `NSApp.windows.first { $0.identifier?.rawValue == "workspace-\(id)" }` in `onAppear`. Retry-with-delay (SwiftUI creates async).

## Window Chrome

Both windows:

```swift
.onAppear {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == windowId }) else { return }
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        // Install NSWindowDelegate for close guards + frame persistence
    }
}
```

## Close Behavior

**Chat close → background (not quit):**
`NSWindowDelegate.windowShouldClose` hides, does NOT quit. Smithers continues w/ menu bar icon (scheduled agents). Quit = explicit Cmd+Q or menu "Quit".

**Workspace close → hide:**
`windowShouldClose` returns `false`, calls `windowCoordinator.hideWorkspacePanel()`. Hidden not destroyed. Tab state, scroll, sidebar width preserved in memory.

**App termination:**
`NSApplicationDelegate.applicationShouldTerminate` returns `.terminateLater`, runs close guard, persists session state → `NSApp.reply(toApplicationShouldTerminate: true)`

## Frame Persistence

`WindowFrameStore` saves frames keyed by type+workspace path:

```swift
enum WindowFrameStore {
    private static let frameMapKey = "smithers.windowFrames"

    static func saveFrame(_ frame: NSRect, window: WindowKind, workspace: URL?) { ... }
    static func loadFrame(window: WindowKind, workspace: URL?) -> NSRect? { ... }

    enum WindowKind: String { case chat, workspacePanel }
}
```

250ms debounce on `windowDidResize`/`windowDidMove`. Validates vs screen geometry on load.

## Default Sizing

```swift
static func defaultFrame(for kind: WindowKind, screen: NSScreen) -> NSRect {
    let vis = screen.visibleFrame
    switch kind {
    case .chat:
        let w = vis.width * 0.45, h = vis.height * 0.85
        let x = vis.midX - (vis.width * 0.06) - (w / 2), y = vis.midY - (h / 2)
        return NSRect(x: x, y: y, width: w, height: h)
    case .workspacePanel:
        let w = vis.width * 0.55, h = vis.height * 0.85
        let x = vis.midX + (vis.width * 0.06) - (w / 2), y = vis.midY - (h / 2)
        return NSRect(x: x, y: y, width: w, height: h)
    }
}
```
