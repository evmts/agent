import Observation
import AppKit
import SwiftUI
import OSLog

@Observable @MainActor
final class WindowCoordinator {
    private(set) var isWorkspacePanelVisible: Bool = false
    private var windowDelegate: WorkspaceWindowDelegate?
    private var delegateRetryCount: Int = 0
    private let logger = Logger(subsystem: "com.smithers", category: "window")

    func showWorkspacePanel() {
        isWorkspacePanelVisible = true
    }

    /// Opens or focuses the workspace window, centralizing presentation logic.
    func showWorkspacePanel(_ openWindow: OpenWindowAction) {
        if let win = workspaceWindow() {
            win.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "workspace")
        }
        isWorkspacePanelVisible = true
        ensureWindowDelegate()
    }

    /// Bring existing workspace window to front if present.
    func focusWorkspacePanel() {
        workspaceWindow()?.makeKeyAndOrderFront(nil)
        ensureWindowDelegate()
    }

    func hideWorkspacePanel() {
        if let win = workspaceWindow() {
            win.orderOut(nil)
        }
        isWorkspacePanelVisible = false
    }

    /// Internal: mark hidden when the NSWindow closes or is ordered out externally.
    func markWorkspacePanelHidden() {
        isWorkspacePanelVisible = false
    }

    private func workspaceWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "workspace" }
    }

    private func ensureWindowDelegate() {
        guard let win = workspaceWindow() else {
            // SwiftUI may not have created the window yet; retry with backoff up to 10 times.
            if delegateRetryCount < 10 {
                delegateRetryCount += 1
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    self?.ensureWindowDelegate()
                }
            } else {
                logger.warning("Workspace window delegate install retries exhausted")
            }
            return
        }
        if (win.delegate as? WorkspaceWindowDelegate) == nil {
            let del = WorkspaceWindowDelegate(coordinator: self)
            win.delegate = del
            self.windowDelegate = del // keep alive
        }
    }
}

@MainActor
private final class WorkspaceWindowDelegate: NSObject, NSWindowDelegate {
    weak var coordinator: WindowCoordinator?
    init(coordinator: WindowCoordinator) {
        self.coordinator = coordinator
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.markWorkspacePanelHidden()
    }
}
