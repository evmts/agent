import SwiftUI

struct ContentView: View {
    @Binding var appState: AppState
    @State private var previousTab: TabType = .prompt
    
    // This will now handle the event dispatches
    private func handleEvent(_ event: AppEvent) {
        PlueCore.shared.handleEvent(event)
    }
    
    // Smart animation direction based on tab indices
    private func transitionForTab(_ tab: TabType) -> AnyTransition {
        let currentIndex = appState.currentTab.rawValue
        let previousIndex = previousTab.rawValue
        let isMovingRight = currentIndex > previousIndex
        
        return .asymmetric(
            insertion: .move(edge: isMovingRight ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isMovingRight ? .leading : .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Custom Title Bar with Integrated Tabs
            CustomTitleBar(
                selectedTab: Binding(
                    get: { appState.currentTab },
                    set: { newTab in handleEvent(.tabSwitched(newTab)) }
                ),
                currentTheme: appState.currentTheme,
                onThemeToggle: { handleEvent(.themeToggled) }
            )

            // 2. Main Content Area
            ZStack {
                // Use theme-aware background
                DesignSystem.Colors.background(for: appState.currentTheme)
                    .ignoresSafeArea()

                // 3. View Switching Logic with Smart Contextual Transitions
                Group {
                    switch appState.currentTab {
                    case .prompt:
                        VimPromptView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.prompt))
                    case .farcaster:
                        FarcasterView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.farcaster))
                    case .agent:
                        AgentView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.agent))
                    case .terminal:
                        TerminalView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.terminal))
                    case .web:
                        WebView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.web))
                    case .editor:
                        // The "Editor" tab uses the old ChatView, let's update it later if needed.
                        // For now, let's ensure it has a consistent background.
                        ChatView(appState: appState, core: PlueCore.shared)
                            .background(DesignSystem.Colors.background)
                            .transition(transitionForTab(.editor))
                    case .diff:
                        DiffView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.diff))
                    case .worktree:
                        WorktreeView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.worktree))
                    }
                }
                .animation(DesignSystem.Animation.tabSwitch, value: appState.currentTab)
                .onChange(of: appState.currentTab) { oldValue, newValue in
                    previousTab = oldValue
                }
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
        .onAppear(perform: configureWindow)
    }
    
    private func configureWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.backgroundColor = NSColor(DesignSystem.Colors.background)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        // Ensure the standard buttons are hidden since we have custom ones
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}


// MARK: - New Custom Title Bar View
struct CustomTitleBar: View {
    @Binding var selectedTab: TabType
    let currentTheme: DesignSystem.Theme
    let onThemeToggle: () -> Void
    @State private var isHovered = false

    private let windowActions: [WindowAction] = [.close, .minimize, .maximize]
    private let windowActionColors: [Color] = [.red, .yellow, .green]

    var body: some View {
        HStack(spacing: 0) {
            // Window Controls (Traffic Lights)
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    CustomWindowButton(action: windowActions[i], color: windowActionColors[i])
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 40) // Define a fixed height for the title bar area
            .onHover { hover in isHovered = hover }

            // Tab Buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(TabType.allCases, id: \.self) { tab in
                        TabButton(tab: tab, selectedTab: $selectedTab)
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Spacer()
            
            // Theme Toggle Button
            Button(action: onThemeToggle) {
                Image(systemName: currentTheme == .dark ? "sun.max" : "moon")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Toggle theme")
            .padding(.trailing, 12)
        }
        .background(DesignSystem.Colors.background)
        .onAppear {
            // This enables the window to be dragged by our custom title bar
            DispatchQueue.main.async {
                if let window = NSApplication.shared.windows.first {
                    window.isMovableByWindowBackground = true
                }
            }
        }
    }
}


// MARK: - New Tab Button View
struct TabButton: View {
    let tab: TabType
    @Binding var selectedTab: TabType
    
    private var isSelected: Bool { selectedTab == tab }
    
    private var title: String {
        switch tab {
        case .prompt: return "Prompt"
        case .farcaster: return "Social"
        case .agent: return "Agent"
        case .terminal: return "Terminal"
        case .web: return "Browser"
        case .editor: return "Editor"
        case .diff: return "Diff"
        case .worktree: return "Worktree"
        }
    }
    
    private var icon: String {
        switch tab {
        case .prompt: return "doc.text.fill"
        case .farcaster: return "person.2.circle.fill"
        case .agent: return "gearshape.2.fill"
        case .terminal: return "terminal.fill"
        case .web: return "globe"
        case .editor: return "curlybraces"
        case .diff: return "doc.on.doc.fill"
        case .worktree: return "arrow.triangle.branch"
        }
    }

    var body: some View {
        Button(action: { 
            withAnimation(DesignSystem.Animation.tabSwitch) {
                selectedTab = tab 
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .scaleEffect(isSelected ? 1.0 : 0.9)
                    .animation(DesignSystem.Animation.scaleIn.delay(DesignSystem.Animation.staggerDelay), value: isSelected)
                Text(title)
                    .font(DesignSystem.Typography.labelMedium)
                    .animation(DesignSystem.Animation.scaleIn.delay(DesignSystem.Animation.staggerDelay * 2), value: isSelected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(isSelected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textTertiary)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .fill(isSelected ? DesignSystem.Colors.surface : .clear)
                    .scaleEffect(isSelected ? 1.0 : 0.98)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .stroke(isSelected ? DesignSystem.Colors.primary.opacity(0.3) : .clear, lineWidth: 1)
                    .scaleEffect(isSelected ? 1.0 : 0.95)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(DesignSystem.Animation.tabSwitch, value: isSelected)
        .hoverEffect()
    }
}

#Preview {
    ContentView(appState: .constant(AppState.initial))
        .frame(width: 1200, height: 800)
}