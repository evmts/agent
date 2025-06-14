import SwiftUI
import SwiftDown
import UserNotifications

struct VimPromptView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                DesignSystem.Colors.background(for: appState.currentTheme)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Bar
                    promptHeaderBar
                    
                    // Main Content Area (split view)
                    HSplitView {
                        // Left Pane: Vim Buffer
                        VimBufferView(
                            content: Binding(
                                get: { appState.promptState.currentPromptContent },
                                set: { core.handleEvent(.promptContentUpdated($0)) }
                            ),
                            title: "Prompt Buffer",
                            status: "VIM",
                            theme: appState.currentTheme
                        )
                        
                        // Right Pane: Live Preview
                        MarkdownPreviewView(
                            content: appState.promptState.currentPromptContent,
                            title: "Live Preview",
                            core: core,
                            appState: appState
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Chat Messages Area
                    promptChatArea
                    
                    // Input Area
                    promptInputArea
                }
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }
    
    // MARK: - Header Bar
    private var promptHeaderBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Left side - Session Navigation
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Previous session button
                Button(action: {
                    if appState.promptState.currentConversationIndex > 0 {
                        core.handleEvent(.promptSelectConversation(appState.promptState.currentConversationIndex - 1))
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(appState.promptState.currentConversationIndex == 0 ? DesignSystem.Colors.textTertiary(for: appState.currentTheme).opacity(0.3) : DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Previous session (⌘[)")
                .disabled(appState.promptState.currentConversationIndex == 0)
                
                // Session indicator
                VStack(alignment: .leading, spacing: 1) {
                    Text("prompt")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    
                    Text("\(appState.promptState.currentConversationIndex + 1)/\(appState.promptState.conversations.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                
                // Next/New session button
                Button(action: {
                    if appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 {
                        core.handleEvent(.promptSelectConversation(appState.promptState.currentConversationIndex + 1))
                    } else {
                        core.handleEvent(.promptNewConversation)
                    }
                }) {
                    Image(systemName: appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 ? "chevron.right" : "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help(appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 ? "Next session (⌘])" : "New session (⌘N)")
            }
            
            Spacer()
            
            // Center - Current Prompt Status
            VStack(alignment: .center, spacing: 1) {
                Text("prompt engineering")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                
                Text("\(appState.promptState.currentPromptContent.components(separatedBy: .newlines).count) lines")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 0.5)
                    )
            )
            
            Spacer()
            
            // Right side - Status and Actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Processing indicator
                if appState.promptState.isProcessing {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignSystem.Colors.warning)
                            .frame(width: 6, height: 6)
                        
                        Text("processing")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                }
                
                // Sync indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignSystem.Colors.success)
                        .frame(width: 6, height: 6)
                    
                    Text("synced")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(
            DesignSystem.Colors.surface(for: appState.currentTheme)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Chat Messages Area
    private var promptChatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.md) {
                    // Welcome message if empty
                    if appState.promptState.currentConversation?.messages.isEmpty ?? true {
                        promptWelcomeView
                            .padding(.top, DesignSystem.Spacing.lg)
                    }
                    
                    // Chat message bubbles
                    ForEach(appState.promptState.currentConversation?.messages ?? []) { message in
                        PromptMessageBubbleView(
                            message: message,
                            theme: appState.currentTheme
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                        .id(message.id)
                    }
                    
                    // Processing indicator
                    if appState.promptState.isProcessing {
                        PromptProcessingIndicatorView(theme: appState.currentTheme)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                    }
                    
                    // Bottom spacing
                    Spacer(minLength: DesignSystem.Spacing.lg)
                }
                .padding(.vertical, DesignSystem.Spacing.md)
            }
            .frame(height: 200) // Fixed height for chat area
            .scrollIndicators(.never)
            .background(DesignSystem.Colors.backgroundSecondary(for: appState.currentTheme))
            .onChange(of: appState.promptState.currentConversation?.messages.count) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let lastMessage = appState.promptState.currentConversation?.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Welcome View
    private var promptWelcomeView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Minimal logo
            Circle()
                .fill(DesignSystem.Colors.textTertiary(for: appState.currentTheme).opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                )
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("prompt engineering")
                    .font(DesignSystem.Typography.titleMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Text("chat to refine • vim buffer to edit • preview to review")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 300)
        .multilineTextAlignment(.center)
    }
    
    // MARK: - Input Area
    private var promptInputArea: some View {
        VStack(spacing: 0) {
            // Separator
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3))
            
            HStack(spacing: DesignSystem.Spacing.md) {
                // Prompt Chat Input
                VimChatInputView(
                    onMessageSent: { message in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            core.handleEvent(.promptMessageSent(message))
                        }
                    },
                    onMessageUpdated: { message in
                        core.handleEvent(.promptMessageSent(message))
                    },
                    onNavigateUp: {
                        print("Navigate up - not implemented")
                    },
                    onNavigateDown: {
                        print("Navigate down - not implemented")
                    },
                    onPreviousChat: {
                        if appState.promptState.currentConversationIndex > 0 {
                            core.handleEvent(.promptSelectConversation(appState.promptState.currentConversationIndex - 1))
                        }
                    },
                    onNextChat: {
                        if appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 {
                            core.handleEvent(.promptSelectConversation(appState.promptState.currentConversationIndex + 1))
                        } else {
                            core.handleEvent(.promptNewConversation)
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 0.5)
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
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    
                    HStack(spacing: 4) {
                        Text("⌘[]")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme).opacity(0.6))
                        Text("nav")
                            .font(.system(size: 9))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                }
                .opacity(0.7)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
        }
    }
}

// MARK: - Supporting Views

struct PromptMessageBubbleView: View {
    let message: PromptMessage
    let theme: DesignSystem.Theme
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.type == .user {
                Spacer(minLength: 100)
                userMessageView
            } else {
                systemMessageView
                Spacer(minLength: 100)
            }
        }
    }
    
    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: 12) {
                Text(message.content)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DesignSystem.Colors.primary)
                    )
                    .textSelection(.enabled)
                
                // User avatar
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 1)
                    )
                    .overlay(
                        Text("U")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.primary)
                    )
            }
            
            Text(formatTime(message.timestamp))
                .font(.system(size: 9))
                .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                .padding(.trailing, 36)
        }
    }
    
    private var systemMessageView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                // Assistant avatar
                Circle()
                    .fill(messageAvatarColor)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(DesignSystem.Colors.border(for: theme).opacity(0.3), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: messageAvatarIcon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    )
                
                Text(message.content)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(messageTextColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(messageBackgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(DesignSystem.Colors.border(for: theme).opacity(0.3), lineWidth: 0.5)
                            )
                    )
                    .textSelection(.enabled)
            }
            
            Text(formatTime(message.timestamp))
                .font(.system(size: 9))
                .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                .padding(.leading, 36)
        }
    }
    
    private var messageAvatarColor: Color {
        switch message.type {
        case .system: return DesignSystem.Colors.textTertiary(for: theme).opacity(0.6)
        case .assistant: return DesignSystem.Colors.accent
        case .user: return DesignSystem.Colors.primary
        }
    }
    
    private var messageAvatarIcon: String {
        switch message.type {
        case .system: return "info.circle"
        case .assistant: return "doc.text"
        case .user: return "person"
        }
    }
    
    private var messageTextColor: Color {
        DesignSystem.Colors.textPrimary(for: theme)
    }
    
    private var messageBackgroundColor: Color {
        DesignSystem.Colors.surface(for: theme)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct PromptProcessingIndicatorView: View {
    let theme: DesignSystem.Theme
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Assistant avatar
            Circle()
                .fill(DesignSystem.Colors.accent)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(DesignSystem.Colors.border(for: theme).opacity(0.3), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "doc.text")
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
                    .fill(DesignSystem.Colors.surface(for: theme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DesignSystem.Colors.border(for: theme).opacity(0.3), lineWidth: 0.5)
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

struct VimBufferView: View {
    @Binding var content: String
    let title: String
    let status: String
    let theme: DesignSystem.Theme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                    
                    Text("vim-mode editing")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                }
                
                Spacer()
                
                Text(status)
                    .font(DesignSystem.Typography.monoSmall)
                    .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface(for: theme))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(DesignSystem.Colors.border(for: theme).opacity(0.3)),
                alignment: .bottom
            )
            
            // We will replace this with a real Vim component later.
            // For now, TextEditor simulates the buffer.
            TextEditor(text: $content)
                .font(DesignSystem.Typography.monoMedium)
                .padding(DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.backgroundSecondary(for: theme))
                .scrollContentBackground(.hidden)
        }
    }
}

struct MarkdownPreviewView: View {
    let content: String
    let title: String
    let core: PlueCoreInterface
    let appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("live markdown")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                
                Spacer()
                
                Text("PREVIEW")
                    .font(DesignSystem.Typography.monoSmall)
                    .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
                alignment: .bottom
            )

            // Use the SwiftDown component for rendering
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack {
                    Spacer()
                    
                    // Minimal empty state
                    VStack(spacing: 12) {
                        Circle()
                            .fill(DesignSystem.Colors.textTertiary(for: appState.currentTheme).opacity(0.1))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "doc.text")
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                            )
                        
                        VStack(spacing: 4) {
                            Text("empty")
                                .font(DesignSystem.Typography.labelMedium)
                                .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                            
                            Text("start typing to see preview")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                        }
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.backgroundSecondary(for: appState.currentTheme))
            } else {
                SwiftDownEditor(text: .constant(content))
                    .disabled(true)
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.backgroundSecondary(for: appState.currentTheme))
            }
        }
    }
}

#Preview {
    VimPromptView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}