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
                // Use native macOS background with material
                Rectangle()
                    .fill(DesignSystem.Colors.background(for: appState.currentTheme))
                    .background(DesignSystem.Materials.adaptive(for: appState.currentTheme))
                    .ignoresSafeArea()

                // 3. View Switching Logic with Smart Contextual Transitions
                Group {
                    switch appState.currentTab {
                    case .prompt:
                        ModernChatView(appState: appState, core: PlueCore.shared)
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
                        // TODO: Implement proper code editor view
                        // For now, using EditorView as placeholder
                        EditorView(appState: appState, core: PlueCore.shared)
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
        window.backgroundColor = NSColor(DesignSystem.Colors.background(for: appState.currentTheme))
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        
        // Configure window appearance
        window.appearance = NSAppearance(named: appState.currentTheme == .dark ? .darkAqua : .aqua)
        window.minSize = NSSize(width: 800, height: 600)
        
        // Don't hide the standard buttons, just let our custom ones handle the actions
        window.standardWindowButton(.closeButton)?.alphaValue = 0
        window.standardWindowButton(.miniaturizeButton)?.alphaValue = 0
        window.standardWindowButton(.zoomButton)?.alphaValue = 0
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
                        .opacity(isHovered ? 1.0 : 0.4)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 40) // Define a fixed height for the title bar area
            .onHover { hover in isHovered = hover }

            // Tab Buttons with visual separator
            Divider()
                .frame(width: 1, height: 16)
                .background(DesignSystem.Colors.border(for: currentTheme))
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(TabType.allCases, id: \.self) { tab in
                        TabButton(tab: tab, selectedTab: $selectedTab, theme: currentTheme)
                    }
                }
                .padding(.horizontal, 4)
            }
            
            Spacer()
            
            // Theme Toggle Button with better styling
            Button(action: onThemeToggle) {
                Image(systemName: currentTheme == .dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: currentTheme))
                    .padding(6)
                    .background(
                        Circle()
                            .fill(DesignSystem.Colors.surface(for: currentTheme))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(DesignSystem.Colors.border(for: currentTheme), lineWidth: 0.5)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Toggle theme")
            .padding(.trailing, 12)
        }
        .frame(height: 40)
        .background(
            ZStack {
                // Base background
                DesignSystem.Colors.background(for: currentTheme)
                
                // Material effect for depth
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                // Bottom border
                VStack {
                    Spacer()
                    Divider()
                        .background(DesignSystem.Colors.border(for: currentTheme))
                }
            }
        )
    }
}


// MARK: - New Tab Button View
struct TabButton: View {
    let tab: TabType
    @Binding var selectedTab: TabType
    let theme: DesignSystem.Theme
    @State private var isHovered = false
    
    private var isSelected: Bool { selectedTab == tab }
    
    private var title: String {
        switch tab {
        case .prompt: return "Prompt"
        case .farcaster: return "Social"
        case .agent: return "Agent"
        case .terminal: return "Terminal"
        case .web: return "Web"
        case .editor: return "Editor"
        case .diff: return "Diff"
        case .worktree: return "Worktree"
        }
    }
    
    private var icon: String {
        switch tab {
        case .prompt: return "bubble.left.and.bubble.right"
        case .farcaster: return "person.2.wave.2"
        case .agent: return "brain"
        case .terminal: return "terminal"
        case .web: return "safari"
        case .editor: return "doc.text"
        case .diff: return "arrow.left.arrow.right"
        case .worktree: return "folder.badge.gearshape"
        }
    }
    
    private var accessibilityID: String {
        switch tab {
        case .prompt: return AccessibilityIdentifiers.tabButtonPrompt
        case .farcaster: return AccessibilityIdentifiers.tabButtonFarcaster
        case .agent: return AccessibilityIdentifiers.tabButtonAgent
        case .terminal: return AccessibilityIdentifiers.tabButtonTerminal
        case .web: return AccessibilityIdentifiers.tabButtonWeb
        case .editor: return AccessibilityIdentifiers.tabButtonEditor
        case .diff: return AccessibilityIdentifiers.tabButtonDiff
        case .worktree: return AccessibilityIdentifiers.tabButtonWorktree
        }
    }

    var body: some View {
        Button(action: { 
            withAnimation(DesignSystem.Animation.tabSwitch) {
                selectedTab = tab 
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 10, weight: .regular))
            }
            .frame(width: 60, height: 40)
            .foregroundColor(
                isSelected ? DesignSystem.Colors.primary :
                isHovered ? DesignSystem.Colors.textPrimary(for: theme) :
                DesignSystem.Colors.textSecondary(for: theme)
            )
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.Colors.primary.opacity(0.1))
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(DesignSystem.Colors.primary.opacity(0.2), lineWidth: 0.5)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.Colors.surface(for: theme).opacity(0.5))
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(accessibilityID)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
    }
}

#Preview {
    ContentView(appState: .constant(AppState.initial))
        .frame(width: 1200, height: 800)
}