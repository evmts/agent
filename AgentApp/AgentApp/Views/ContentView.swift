import SwiftUI

struct PlueContentView: View {
    @Binding var appState: PlueAppState
    @State private var previousTab: TabType = .agent

    private func handleEvent(_ event: PlueEvent) {
        PlueCore.shared.handleEvent(event)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom Title Bar with Tabs
            CustomTitleBar(
                selectedTab: Binding(
                    get: { appState.currentTab },
                    set: { newTab in handleEvent(.tabSwitched(newTab)) }
                ),
                currentTheme: appState.currentTheme,
                onThemeToggle: { handleEvent(.themeToggled) }
            )

            // Main Content Area
            ZStack {
                Rectangle()
                    .fill(DesignSystem.Colors.background(for: appState.currentTheme))
                    .ignoresSafeArea()

                Group {
                    switch appState.currentTab {
                    case .agent:
                        AgentChatView(appState: appState)
                            .transition(.opacity)
                    case .terminal:
                        TerminalTabView()
                            .transition(.opacity)
                    case .editor:
                        EditorTabView(appState: appState)
                            .transition(.opacity)
                    }
                }
                .animation(DesignSystem.Animation.tabSwitch, value: appState.currentTab)
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
    }
}

// MARK: - Custom Title Bar

struct CustomTitleBar: View {
    @Binding var selectedTab: TabType
    let currentTheme: DesignSystem.Theme
    let onThemeToggle: () -> Void
    @State private var isHovered = false

    #if os(macOS)
    private let windowActions: [WindowAction] = [.close, .minimize, .maximize]
    private let windowActionColors: [Color] = [.red, .yellow, .green]
    #endif

    var body: some View {
        HStack(spacing: 0) {
            #if os(macOS)
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
            .frame(height: 40)
            .onHover { hover in isHovered = hover }

            Divider()
                .frame(width: 1, height: 16)
                .background(DesignSystem.Colors.border(for: currentTheme))
                .padding(.horizontal, 4)
            #endif

            // Tab Buttons
            HStack(spacing: 2) {
                ForEach(TabType.allCases, id: \.self) { tab in
                    TabButton(tab: tab, selectedTab: $selectedTab, theme: currentTheme)
                }
            }
            .padding(.horizontal, 4)

            Spacer()

            // Theme Toggle
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
                DesignSystem.Colors.background(for: currentTheme)
                Rectangle().fill(.ultraThinMaterial)
                VStack {
                    Spacer()
                    Divider().background(DesignSystem.Colors.border(for: currentTheme))
                }
            }
        )
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let tab: TabType
    @Binding var selectedTab: TabType
    let theme: DesignSystem.Theme
    @State private var isHovered = false

    private var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button(action: {
            withAnimation(DesignSystem.Animation.tabSwitch) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                Text(tab.title)
                    .font(.system(size: 10, weight: .regular))
            }
            .frame(width: 70, height: 40)
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
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
    }
}

// MARK: - Terminal Tab View

struct TerminalTabView: View {
    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            TerminalView()
            #else
            Text("Terminal not available on iOS")
                .foregroundColor(DesignSystem.Colors.textSecondary)
            #endif
        }
    }
}

// MARK: - Editor Tab View

struct EditorTabView: View {
    let appState: PlueAppState
    @State private var content: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Editor toolbar
            HStack {
                Text("Editor")
                    .font(DesignSystem.Typography.titleMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))

                Spacer()

                if appState.editorState.hasUnsavedChanges {
                    Text("Unsaved changes")
                        .font(DesignSystem.Typography.labelSmall)
                        .foregroundColor(DesignSystem.Colors.warning)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))

            Divider()

            // Editor content
            TextEditor(text: $content)
                .font(DesignSystem.Typography.monoMedium)
                .scrollContentBackground(.hidden)
                .background(DesignSystem.Colors.background(for: appState.currentTheme))
                .onAppear {
                    content = appState.editorState.content
                }
                .onChange(of: content) { _, newValue in
                    PlueCore.shared.handleEvent(.editorContentChanged(newValue))
                }
        }
    }
}
