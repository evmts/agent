import SwiftUI

struct PlueApp: App {
    @StateObject private var appStateContainer = AppStateContainer()

    init() {
        // Initialize AppleScript support
        _ = PlueAppleScriptSupport.shared
    }

    var body: some Scene {
        WindowGroup {
            // Directly use the main ContentView
            ContentView(appState: $appStateContainer.appState)
                .frame(minWidth: 1000, minHeight: 700)
                .background(DesignSystem.Colors.background) // Use the design system background
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar) // This is the correct style for a custom borderless window
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// Create a simple container to hold and manage the AppState
class AppStateContainer: ObservableObject {
    @Published var appState = AppState.initial
    private let core = PlueCore.shared

    init() {
        // Use the initial directory from command line arguments if provided
        if let initialDir = initialDirectory {
            _ = core.initialize(workingDirectory: initialDir)
        } else {
            _ = core.initialize()
        }
        
        core.subscribe { [weak self] newState in
            DispatchQueue.main.async {
                self?.appState = newState
            }
        }
    }

    func handleEvent(_ event: AppEvent) {
        core.handleEvent(event)
    }
}

// MARK: - Custom Window Controls

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
                // Base circle
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                
                // Gradient overlay for depth
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
                
                // Icon overlay
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
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
    
    @ViewBuilder
    private var iconForAction: some View {
        switch action {
        case .close:
            Image(systemName: "xmark")
                .scaleEffect(0.8)
        case .minimize:
            Image(systemName: "minus")
        case .maximize:
            Image(systemName: "plus")
                .scaleEffect(0.9)
        }
    }
    
    private func performAction() {
        guard let window = NSApplication.shared.windows.first else { return }
        
        switch action {
        case .close:
            window.close()
        case .minimize:
            window.miniaturize(nil)
        case .maximize:
            if window.isZoomed {
                window.zoom(nil)
            } else {
                window.zoom(nil)
            }
        }
    }
}

