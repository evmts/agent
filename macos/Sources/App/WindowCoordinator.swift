import Observation
import AppKit
import SwiftUI

@Observable @MainActor
final class WindowCoordinator {
    private(set) var isWorkspacePanelVisible: Bool = false

    func showWorkspacePanel() {
        isWorkspacePanelVisible = true
    }

    /// Opens or focuses the workspace window, centralizing presentation logic.
    /// - Parameter openWindow: SwiftUI `OpenWindowAction` for the workspace scene.
    func showWorkspacePanel(_ openWindow: OpenWindowAction) {
        if let win = workspaceWindow() {
            win.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "workspace")
        }
        isWorkspacePanelVisible = true
    }

    /// Bring existing workspace window to front if present.
    func focusWorkspacePanel() {
        workspaceWindow()?.makeKeyAndOrderFront(nil)
    }

    func hideWorkspacePanel() {
        if let win = workspaceWindow() {
            win.orderOut(nil)
        }
        isWorkspacePanelVisible = false
    }

    private func workspaceWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "workspace" }
    }
}
