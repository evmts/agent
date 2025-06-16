import SwiftUI

// MARK: - Migration Examples
// This file demonstrates how to migrate existing message bubble views to use the unified component

// MARK: - Example 1: Migrating ModernChatView
struct ModernChatViewMigrationExample: View {
    let appState: AppState
    let core: PlueCoreInterface
    @State private var activeMessageId: String? = nil
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.lg) {
                if let messages = appState.promptState.currentConversation?.messages {
                    ForEach(messages) { message in
                        // OLD: ProfessionalMessageBubbleView(message: message, isActive: activeMessageId == message.id, theme: appState.currentTheme)
                        
                        // NEW: Using UnifiedMessageBubbleView with professional style
                        UnifiedMessageBubbleView(
                            message: message,
                            style: .professional,
                            isActive: activeMessageId == message.id,
                            theme: appState.currentTheme,
                            onTap: { tappedMessage in
                                if tappedMessage.type != .user {
                                    print("AI message tapped: \(tappedMessage.id)")
                                    activeMessageId = tappedMessage.id
                                }
                            }
                        )
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .id(message.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }
                }
            }
            .padding(.vertical, DesignSystem.Spacing.lg)
        }
    }
}

// MARK: - Example 2: Migrating AgentView
struct AgentViewMigrationExample: View {
    let agentState: AgentState
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.md) {
                ForEach(agentState.currentConversation?.messages ?? []) { message in
                    // OLD: AgentMessageBubbleView(message: message)
                    
                    // NEW: Using UnifiedMessageBubbleView with compact style
                    UnifiedMessageBubbleView(
                        message: UnifiedAgentMessage(agentMessage: message),
                        style: .compact,
                        theme: .dark
                    )
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .id(message.id)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.md)
        }
    }
}

// MARK: - Example 3: Custom Style Configuration
struct CustomStyledMessageExample: View {
    let message: PromptMessage
    
    // Custom style that matches specific design requirements
    let customStyle = MessageBubbleStyle(
        avatarSize: 32,
        avatarStyle: .iconWithText,
        bubbleCornerRadius: 16,
        bubblePadding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
        maxBubbleWidth: 600,
        contentFont: .system(size: 15, weight: .regular),
        timestampFont: .system(size: 11),
        metadataFont: .system(size: 10),
        avatarSpacing: 10,
        timestampSpacing: 6,
        metadataSpacing: 4,
        userBubbleBackground: Color.blue.opacity(0.9),
        assistantBubbleBackground: Color(NSColor.controlBackgroundColor),
        systemBubbleBackground: Color.gray.opacity(0.1),
        errorBubbleBackground: Color.red.opacity(0.1),
        showAnimations: true,
        animationDuration: 0.25
    )
    
    var body: some View {
        UnifiedMessageBubbleView(
            message: message,
            style: customStyle,
            theme: .dark
        )
    }
}

// MARK: - Example 4: Creating a Typing Indicator with Unified Style
struct UnifiedTypingIndicatorView: View {
    let style: MessageBubbleStyle
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Use same layout as assistant messages
            HStack(alignment: .top, spacing: style.avatarSpacing) {
                // Avatar
                Circle()
                    .fill(DesignSystem.Colors.accentGradient)
                    .frame(width: style.avatarSize, height: style.avatarSize)
                    .overlay(
                        Circle()
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: style.avatarSize * 0.4, weight: .medium))
                            .foregroundColor(.white)
                    )
                
                // Typing animation bubble
                HStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(DesignSystem.Colors.primary.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .scaleEffect(animationPhase == index ? 1.3 : 0.7)
                            .opacity(animationPhase == index ? 1.0 : 0.4)
                            .animation(
                                DesignSystem.Animation.plueStandard
                                    .repeatForever()
                                    .delay(Double(index) * 0.15),
                                value: animationPhase
                            )
                    }
                }
                .padding(style.bubblePadding)
                .background(
                    RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                        .fill(style.assistantBubbleBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                                .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                        )
                )
                
                Spacer()
            }
        }
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Example 5: Message List Component with Unified Bubbles
struct UnifiedMessageListView<Message: UnifiedMessage>: View {
    let messages: [Message]
    let style: MessageBubbleStyle
    let theme: DesignSystem.Theme
    let isProcessing: Bool
    
    @State private var activeMessageId: String? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: style.avatarSpacing) {
                    ForEach(messages) { message in
                        UnifiedMessageBubbleView(
                            message: message,
                            style: style,
                            isActive: activeMessageId == message.id,
                            theme: theme,
                            onTap: { tappedMessage in
                                withAnimation(DesignSystem.Animation.quick) {
                                    activeMessageId = tappedMessage.id
                                }
                            }
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .id(message.id)
                    }
                    
                    if isProcessing {
                        UnifiedTypingIndicatorView(style: style)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                    
                    // Bottom spacing
                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
                .padding(.vertical, DesignSystem.Spacing.md)
            }
            .scrollIndicators(.never)
            .onChange(of: messages.count) { _ in
                withAnimation(DesignSystem.Animation.plueStandard) {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Style Configuration Examples
extension MessageBubbleStyle {
    // Terminal-style messages (for system logs, etc.)
    static let terminal = MessageBubbleStyle(
        avatarSize: 20,
        avatarStyle: .icon,
        bubbleCornerRadius: 4,
        bubblePadding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8),
        maxBubbleWidth: nil,
        contentFont: .system(size: 12, weight: .regular, design: .monospaced),
        timestampFont: .system(size: 9, design: .monospaced),
        metadataFont: .system(size: 9, design: .monospaced),
        avatarSpacing: 8,
        timestampSpacing: 2,
        metadataSpacing: 2,
        userBubbleBackground: Color.green.opacity(0.2),
        assistantBubbleBackground: Color.black.opacity(0.8),
        systemBubbleBackground: Color.gray.opacity(0.2),
        errorBubbleBackground: Color.red.opacity(0.2),
        showAnimations: false,
        animationDuration: 0
    )
    
    // Large display style (for presentations, etc.)
    static let display = MessageBubbleStyle(
        avatarSize: 48,
        avatarStyle: .iconWithText,
        bubbleCornerRadius: 20,
        bubblePadding: EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24),
        maxBubbleWidth: 800,
        contentFont: .system(size: 18, weight: .regular),
        timestampFont: .system(size: 12),
        metadataFont: .system(size: 12),
        avatarSpacing: 16,
        timestampSpacing: 8,
        metadataSpacing: 6,
        userBubbleBackground: DesignSystem.Colors.primary,
        assistantBubbleBackground: DesignSystem.Colors.surface,
        systemBubbleBackground: DesignSystem.Colors.surfaceSecondary,
        errorBubbleBackground: DesignSystem.Colors.error.opacity(0.15),
        showAnimations: true,
        animationDuration: 0.3
    )
}

// MARK: - Preview
#Preview("Migration Examples") {
    VStack(spacing: 40) {
        // Professional style (chat view)
        VStack(alignment: .leading) {
            Text("Professional Style (Chat)")
                .font(.headline)
            
            UnifiedMessageListView(
                messages: [
                    PromptMessage(
                        id: "1",
                        content: "Hello! How can I help you today?",
                        type: .assistant,
                        timestamp: Date(),
                        promptSnapshot: nil
                    ),
                    PromptMessage(
                        id: "2",
                        content: "I need help creating a unified message bubble component",
                        type: .user,
                        timestamp: Date(),
                        promptSnapshot: nil
                    )
                ],
                style: .professional,
                theme: .dark,
                isProcessing: true
            )
            .frame(height: 200)
        }
        
        // Compact style (agent view)
        VStack(alignment: .leading) {
            Text("Compact Style (Agent)")
                .font(.headline)
            
            UnifiedMessageListView(
                messages: [
                    UnifiedAgentMessage(agentMessage: AgentMessage(
                        id: "3",
                        content: "Starting workflow execution...",
                        type: .workflow,
                        timestamp: Date(),
                        metadata: AgentMessageMetadata(
                            worktree: "feature-ui",
                            workflow: "build-test",
                            containerId: nil,
                            exitCode: nil,
                            duration: nil
                        )
                    )),
                    UnifiedAgentMessage(agentMessage: AgentMessage(
                        id: "4",
                        content: "Build completed successfully",
                        type: .system,
                        timestamp: Date(),
                        metadata: AgentMessageMetadata(
                            worktree: "feature-ui",
                            workflow: nil,
                            containerId: "abc123",
                            exitCode: 0,
                            duration: 12.5
                        )
                    ))
                ],
                style: .compact,
                theme: .dark,
                isProcessing: false
            )
            .frame(height: 150)
        }
        
        // Terminal style
        VStack(alignment: .leading) {
            Text("Terminal Style")
                .font(.headline)
            
            UnifiedMessageBubbleView(
                message: UnifiedAgentMessage(agentMessage: AgentMessage(
                    id: "5",
                    content: "$ zig build\n> Building project...\n> Success!",
                    type: .system,
                    timestamp: Date(),
                    metadata: nil
                )),
                style: .terminal,
                theme: .dark
            )
        }
    }
    .padding()
    .background(DesignSystem.Colors.background)
    .frame(width: 800, height: 600)
}