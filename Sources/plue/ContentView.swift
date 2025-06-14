import SwiftUI

struct ContentView: View {
    @State private var appState = AppState.initial
    private let core = PlueCore.shared
    
    var body: some View {
        ZStack {
            // Background gradient
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            // Professional tab interface
            TabView(selection: Binding(
                get: { TabType(rawValue: appState.currentTab.rawValue) ?? .prompt },
                set: { newTab in
                    core.handleEvent(.tabSwitched(newTab))
                }
            )) {
                VimPromptView(appState: appState, core: core)
                    .tabItem {
                        TabItemView(
                            icon: "doc.text.fill",
                            title: "Prompt",
                            isSelected: appState.currentTab == .prompt
                        )
                    }
                    .tag(TabType.prompt)
                
                ModernChatView(appState: appState, core: core)
                    .tabItem {
                        TabItemView(
                            icon: "bubble.left.and.bubble.right.fill",
                            title: "Chat",
                            isSelected: appState.currentTab == .chat
                        )
                    }
                    .tag(TabType.chat)
                
                TerminalView(appState: appState, core: core)
                    .tabItem {
                        TabItemView(
                            icon: "terminal.fill",
                            title: "Terminal",
                            isSelected: appState.currentTab == .terminal
                        )
                    }
                    .tag(TabType.terminal)
                
                WebView(appState: appState, core: core)
                    .tabItem {
                        TabItemView(
                            icon: "globe",
                            title: "Browser",
                            isSelected: appState.currentTab == .web
                        )
                    }
                    .tag(TabType.web)
                
                ChatView(appState: appState, core: core)
                    .tabItem {
                        TabItemView(
                            icon: "curlybraces",
                            title: "Editor",
                            isSelected: appState.currentTab == .editor
                        )
                    }
                    .tag(TabType.editor)
                
                FarcasterView(appState: appState, core: core)
                    .tabItem {
                        TabItemView(
                            icon: "person.2.circle.fill",
                            title: "Social",
                            isSelected: appState.currentTab == .farcaster
                        )
                    }
                    .tag(TabType.farcaster)
            }
            .preferredColorScheme(.dark)
            .tint(DesignSystem.Colors.primary)
        }
        .onAppear {
            setupAppearance()
            // Initialize core and subscribe to state changes
            _ = core.initialize()
            core.subscribe { newState in
                withAnimation(DesignSystem.Animation.smooth) {
                    appState = newState
                }
            }
        }
    }
    
    private func setupAppearance() {
        // Configure window appearance for professional look
        if let window = NSApplication.shared.windows.first {
            window.backgroundColor = NSColor(DesignSystem.Colors.background)
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
        }
    }
}

// MARK: - Professional Tab Item Component

struct TabItemView: View {
    let icon: String
    let title: String
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: DesignSystem.IconSize.medium, weight: .medium))
                .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary)
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(DesignSystem.Animation.quick, value: isSelected)
            
            Text(title)
                .font(DesignSystem.Typography.labelSmall)
                .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .contentTransition()
    }
}


#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
