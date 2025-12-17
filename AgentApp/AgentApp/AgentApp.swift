import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct AgentApp: App {
    @StateObject private var appStateContainer = AppStateContainer()

    init() {
        #if os(macOS)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            PlueContentView(appState: $appStateContainer.appState)
                .frame(minWidth: 900, minHeight: 600)
                .background(DesignSystem.Colors.background)
                .onAppear {
                    #if os(macOS)
                    configureWindow()
                    #endif
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    appStateContainer.handleEvent(.agentNewConversation)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    #if os(macOS)
    private func configureWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.backgroundColor = NSColor(DesignSystem.Colors.background(for: appStateContainer.appState.currentTheme))
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: appStateContainer.appState.currentTheme == .dark ? .darkAqua : .aqua)
        window.minSize = NSSize(width: 800, height: 600)

        // Hide standard buttons (we have custom ones)
        window.standardWindowButton(.closeButton)?.alphaValue = 0
        window.standardWindowButton(.miniaturizeButton)?.alphaValue = 0
        window.standardWindowButton(.zoomButton)?.alphaValue = 0
    }
    #endif
}

// MARK: - State Container

class AppStateContainer: ObservableObject {
    @Published var appState = PlueAppState.initial
    private let core = PlueCore.shared

    init() {
        core.subscribe { [weak self] newState in
            DispatchQueue.main.async {
                self?.appState = newState
            }
        }
    }

    func handleEvent(_ event: PlueEvent) {
        core.handleEvent(event)
    }
}

// MARK: - Window Controls

#if os(macOS)
enum WindowAction {
    case close, minimize, maximize
}

struct CustomWindowButton: View {
    let action: WindowAction
    let color: Color
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: performAction) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isPressed ? 0 : 0.3),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 8
                        )
                    )
                    .frame(width: 12, height: 12)

                if isHovered {
                    iconForAction
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.black.opacity(0.6))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
    }

    @ViewBuilder
    private var iconForAction: some View {
        switch action {
        case .close:
            Image(systemName: "xmark").scaleEffect(0.8)
        case .minimize:
            Image(systemName: "minus")
        case .maximize:
            Image(systemName: "plus").scaleEffect(0.9)
        }
    }

    private func performAction() {
        guard let window = NSApplication.shared.windows.first else { return }
        switch action {
        case .close: window.close()
        case .minimize: window.miniaturize(nil)
        case .maximize: window.zoom(nil)
        }
    }
}
#endif
