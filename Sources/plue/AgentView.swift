import SwiftUI
import AppKit

struct AgentView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Minimal background
                DesignSystem.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Minimal Header Bar
                    agentHeaderBar
                    
                    // Chat Messages Area
                    agentChatArea
                    
                    // Control Panel
                    agentControlPanel
                    
                    // Input Area
                    agentInputArea
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Initialize worktrees and auto-refresh
            core.handleEvent(.agentRefreshWorktrees)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }
    
    // MARK: - Minimal Header Bar
    private var agentHeaderBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Left side - Session Navigation
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Previous session button
                Button(action: {
                    if appState.agentState.currentConversationIndex > 0 {
                        core.handleEvent(.agentSelectConversation(appState.agentState.currentConversationIndex - 1))
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(appState.agentState.currentConversationIndex == 0 ? DesignSystem.Colors.textTertiary.opacity(0.3) : DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Previous session (⌘[)")
                .disabled(appState.agentState.currentConversationIndex == 0)
                
                // Session indicator
                VStack(alignment: .leading, spacing: 1) {
                    Text("agent")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    Text("\(appState.agentState.currentConversationIndex + 1)/\(appState.agentState.conversations.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                // Next/New session button
                Button(action: {
                    if appState.agentState.currentConversationIndex < appState.agentState.conversations.count - 1 {
                        core.handleEvent(.agentSelectConversation(appState.agentState.currentConversationIndex + 1))
                    } else {
                        core.handleEvent(.agentNewConversation)
                    }
                }) {
                    Image(systemName: appState.agentState.currentConversationIndex < appState.agentState.conversations.count - 1 ? "chevron.right" : "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(appState.agentState.currentConversationIndex < appState.agentState.conversations.count - 1 ? "Next session (⌘])" : "New session (⌘N)")
            }
            
            Spacer()
            
            // Center - Current Workspace Indicator
            if let workspace = appState.agentState.currentWorkspace {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: workspace.status))
                        .frame(width: 6, height: 6)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("workspace")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        
                        Text(workspace.branch)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                        )
                )
            } else {
                Text("no workspace")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            
            Spacer()
            
            // Right side - Status and Actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Dagger session indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.agentState.daggerSession?.isConnected == true ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary.opacity(0.3))
                        .frame(width: 6, height: 6)
                    
                    Text("dagger")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                // Processing indicator
                if appState.agentState.isProcessing {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignSystem.Colors.warning)
                            .frame(width: 6, height: 6)
                        
                        Text("processing")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                }
                
                // Workflow execution indicator
                if appState.agentState.isExecutingWorkflow {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignSystem.Colors.primary)
                            .frame(width: 6, height: 6)
                        
                        Text("workflow")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(
            DesignSystem.Colors.surface
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(DesignSystem.Colors.border.opacity(0.3)),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Chat Messages Area
    private var agentChatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.md) {
                    // Welcome message if empty
                    if appState.agentState.currentConversation?.messages.isEmpty ?? true {
                        agentWelcomeView
                            .padding(.top, DesignSystem.Spacing.massive)
                    }
                    
                    // Agent message bubbles
                    ForEach(appState.agentState.currentConversation?.messages ?? []) { message in
                        UnifiedMessageBubbleView(
                            message: UnifiedAgentMessage(agentMessage: message),
                            style: .compact,
                            theme: appState.currentTheme
                        )
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .id(message.id)
                    }
                    
                    // Processing indicator
                    if appState.agentState.isProcessing {
                        AgentProcessingIndicatorView()
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                    }
                    
                    // Bottom spacing
                    Spacer(minLength: DesignSystem.Spacing.lg)
                }
                .padding(.vertical, DesignSystem.Spacing.md)
            }
            .scrollIndicators(.never)
            .background(DesignSystem.Colors.backgroundSecondary)
            .onChange(of: appState.agentState.currentConversation?.messages.count) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let lastMessage = appState.agentState.currentConversation?.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Welcome View
    private var agentWelcomeView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            // Minimal logo
            Circle()
                .fill(DesignSystem.Colors.textTertiary.opacity(0.1))
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                )
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("agent ready")
                    .font(DesignSystem.Typography.titleMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("git worktrees • dagger workflows • automation")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Quick actions
            VStack(spacing: 6) {
                quickActionButton("list worktrees", icon: "list.bullet")
                quickActionButton("start dagger", icon: "gearshape")
                quickActionButton("create workflow", icon: "arrow.triangle.2.circlepath")
                quickActionButton("help commands", icon: "questionmark.circle")
            }
        }
        .frame(maxWidth: 400)
        .multilineTextAlignment(.center)
    }
    
    private func quickActionButton(_ text: String, icon: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                core.handleEvent(.agentMessageSent(text))
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .frame(width: 16)
                
                Text(text)
                    .font(DesignSystem.Typography.labelMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: 280)
    }
    
    // MARK: - Control Panel
    private var agentControlPanel: some View {
        VStack(spacing: 0) {
            // Separator
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border.opacity(0.3))
            
            HStack(spacing: DesignSystem.Spacing.lg) {
                // Worktree controls
                VStack(alignment: .leading, spacing: 4) {
                    Text("worktrees")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    HStack(spacing: 6) {
                        Button("refresh") {
                            core.handleEvent(.agentRefreshWorktrees)
                        }
                        .buttonStyle(MiniButtonStyle())
                        
                        Button("create") {
                            // For demo, create a new worktree with timestamp
                            let branch = "feature-\(Int(Date().timeIntervalSince1970))"
                            let path = "/tmp/plue-\(branch)"
                            core.handleEvent(.agentCreateWorktree(branch, path))
                        }
                        .buttonStyle(MiniButtonStyle())
                        
                        if !appState.agentState.availableWorktrees.isEmpty {
                            Menu("switch") {
                                ForEach(appState.agentState.availableWorktrees, id: \.id) { worktree in
                                    Button(action: {
                                        core.handleEvent(.agentSwitchWorktree(worktree.id))
                                    }) {
                                        HStack {
                                            Text(worktree.branch)
                                            if worktree.id == appState.agentState.currentWorkspace?.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            .buttonStyle(MiniButtonStyle())
                            .menuStyle(BorderlessButtonMenuStyle())
                        }
                    }
                }
                
                Spacer()
                
                // Dagger controls
                VStack(alignment: .leading, spacing: 4) {
                    Text("dagger")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    HStack(spacing: 6) {
                        if appState.agentState.daggerSession?.isConnected == true {
                            Button("stop") {
                                core.handleEvent(.agentStopDaggerSession)
                            }
                            .buttonStyle(MiniButtonStyle())
                        } else {
                            Button("start") {
                                core.handleEvent(.agentStartDaggerSession)
                            }
                            .buttonStyle(MiniButtonStyle())
                        }
                        
                        Button("workflow") {
                            // Create a sample workflow for demo
                            let workflow = AgentWorkflow(
                                id: UUID().uuidString,
                                name: "Build & Test",
                                description: "Run build and tests in container",
                                steps: [
                                    WorkflowStep(
                                        id: UUID().uuidString,
                                        name: "Build",
                                        command: "swift build",
                                        container: "swift:latest",
                                        dependencies: [],
                                        status: .pending
                                    ),
                                    WorkflowStep(
                                        id: UUID().uuidString,
                                        name: "Test",
                                        command: "swift test",
                                        container: "swift:latest",
                                        dependencies: ["build"],
                                        status: .pending
                                    )
                                ],
                                status: .pending,
                                createdAt: Date(),
                                startedAt: nil,
                                completedAt: nil
                            )
                            core.handleEvent(.agentExecuteWorkflow(workflow))
                        }
                        .buttonStyle(MiniButtonStyle())
                        .disabled(appState.agentState.daggerSession?.isConnected != true)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.surface)
        }
    }
    
    // MARK: - Input Area
    private var agentInputArea: some View {
        VStack(spacing: 0) {
            // Separator
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border.opacity(0.3))
            
            HStack(spacing: DesignSystem.Spacing.md) {
                // Quick tools button
                Button(action: {}) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Agent tools")
                
                // Agent Chat Input
                VimChatInputView(
                    onMessageSent: { message in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            core.handleEvent(.agentMessageSent(message))
                        }
                    },
                    onMessageUpdated: { message in
                        core.handleEvent(.agentMessageSent(message))
                    },
                    onNavigateUp: {
                        print("Navigate up - not implemented")
                    },
                    onNavigateDown: {
                        print("Navigate down - not implemented")
                    },
                    onPreviousChat: {
                        if appState.agentState.currentConversationIndex > 0 {
                            core.handleEvent(.agentSelectConversation(appState.agentState.currentConversationIndex - 1))
                        }
                    },
                    onNextChat: {
                        if appState.agentState.currentConversationIndex < appState.agentState.conversations.count - 1 {
                            core.handleEvent(.agentSelectConversation(appState.agentState.currentConversationIndex + 1))
                        } else {
                            core.handleEvent(.agentNewConversation)
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignSystem.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .frame(maxWidth: .infinity)
                
                // Help indicator
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(":w")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.primary.opacity(0.8))
                        Text("send")
                            .font(.system(size: 9))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                    
                    HStack(spacing: 4) {
                        Text("⌘[]")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.6))
                        Text("nav")
                            .font(.system(size: 9))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                }
                .opacity(0.7)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
        }
    }
    
    // MARK: - Helper Functions
    
    private func statusColor(for status: GitWorktreeStatus) -> Color {
        switch status {
        case .clean: return DesignSystem.Colors.success
        case .modified: return DesignSystem.Colors.warning
        case .untracked: return DesignSystem.Colors.primary
        case .conflicts: return DesignSystem.Colors.error
        }
    }
}

// MARK: - Agent Message Bubble View

// AgentMessageBubbleView has been replaced by UnifiedMessageBubbleView with .compact style

// MARK: - Agent Processing Indicator

struct AgentProcessingIndicatorView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Agent avatar
            Circle()
                .fill(DesignSystem.Colors.accent)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                )
            
            // Processing animation
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DesignSystem.Colors.primary.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .opacity(animationPhase == index ? 1.0 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
            )
            
            Spacer()
        }
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Mini Button Style

struct MiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isPressed ? DesignSystem.Colors.surface.opacity(0.8) : DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }
}

#Preview {
    AgentView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}