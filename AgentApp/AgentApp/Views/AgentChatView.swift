import SwiftUI

struct AgentChatView: View {
    let appState: PlueAppState
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HSplitView {
            // Sidebar with conversations
            ConversationSidebar(appState: appState)
                .frame(minWidth: 200, maxWidth: 280)

            // Main chat area
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            if let conversation = appState.agentState.currentConversation {
                                ForEach(conversation.messages) { message in
                                    MessageBubble(message: message, theme: appState.currentTheme)
                                        .id(message.id)
                                }
                            }

                            if appState.agentState.isProcessing {
                                TypingIndicator(theme: appState.currentTheme)
                                    .id("typing")
                            }
                        }
                        .padding(DesignSystem.Spacing.lg)
                    }
                    .onChange(of: appState.agentState.currentConversation?.messages.count) { _, _ in
                        withAnimation {
                            if let lastMessage = appState.agentState.currentConversation?.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: appState.agentState.isProcessing) { _, isProcessing in
                        if isProcessing {
                            withAnimation {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input area
                ChatInputBar(
                    text: $inputText,
                    isProcessing: appState.agentState.isProcessing,
                    theme: appState.currentTheme,
                    onSend: sendMessage
                )
                .focused($isInputFocused)
            }
        }
        .onAppear {
            isInputFocused = true
        }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let message = inputText
        inputText = ""
        PlueCore.shared.handleEvent(.agentMessageSent(message))
    }
}

// MARK: - Conversation Sidebar

struct ConversationSidebar: View {
    let appState: PlueAppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(DesignSystem.Typography.titleSmall)
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))

                Spacer()

                Button {
                    PlueCore.shared.handleEvent(.agentNewConversation)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("New conversation")
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))

            Divider()

            // Conversation list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(appState.agentState.conversations.enumerated()), id: \.element.id) { index, conversation in
                        ConversationRow(
                            conversation: conversation,
                            isSelected: index == appState.agentState.currentConversationIndex,
                            theme: appState.currentTheme
                        )
                        .onTapGesture {
                            // TODO: Add selectConversation event
                        }
                    }
                }
                .padding(DesignSystem.Spacing.xs)
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
    }
}

struct ConversationRow: View {
    let conversation: AgentConversation
    let isSelected: Bool
    let theme: DesignSystem.Theme

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 14))
                .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary(for: theme))

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.messages.first?.content.prefix(30) ?? "New conversation")
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                    .lineLimit(1)

                Text(formatDate(conversation.updatedAt))
                    .font(DesignSystem.Typography.labelSmall)
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                .fill(isSelected ? DesignSystem.Colors.primary.opacity(0.1) : Color.clear)
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: AgentMessage
    let theme: DesignSystem.Theme

    var isUser: Bool { message.type == .user }
    var isSystem: Bool { message.type == .system }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            if !isUser {
                Avatar(type: isSystem ? .system : .assistant, theme: theme)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: DesignSystem.Spacing.xs) {
                Text(roleLabel)
                    .font(DesignSystem.Typography.labelSmall)
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))

                Text(message.content)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                    .textSelection(.enabled)
                    .padding(DesignSystem.Spacing.md)
                    .background(bubbleBackground)
                    .cornerRadius(DesignSystem.CornerRadius.lg)
            }

            if isUser {
                Avatar(type: .user, theme: theme)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var roleLabel: String {
        switch message.type {
        case .user: return "You"
        case .assistant: return "Agent"
        case .system: return "System"
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            DesignSystem.Colors.primary.opacity(0.15)
        } else if isSystem {
            DesignSystem.Colors.surface(for: theme).opacity(0.5)
        } else {
            DesignSystem.Colors.surface(for: theme)
        }
    }
}

struct Avatar: View {
    enum AvatarType {
        case user, assistant, system
    }

    let type: AvatarType
    let theme: DesignSystem.Theme

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 32, height: 32)

            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(iconColor)
        }
    }

    private var iconName: String {
        switch type {
        case .user: return "person.fill"
        case .assistant: return "brain"
        case .system: return "info.circle"
        }
    }

    private var backgroundColor: Color {
        switch type {
        case .user: return DesignSystem.Colors.primary.opacity(0.2)
        case .assistant: return DesignSystem.Colors.accent.opacity(0.2)
        case .system: return DesignSystem.Colors.surface(for: theme)
        }
    }

    private var iconColor: Color {
        switch type {
        case .user: return DesignSystem.Colors.primary
        case .assistant: return DesignSystem.Colors.accent
        case .system: return DesignSystem.Colors.textSecondary(for: theme)
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    let theme: DesignSystem.Theme
    @State private var animationPhase = 0

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Avatar(type: .assistant, theme: theme)

            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DesignSystem.Colors.textSecondary(for: theme))
                        .frame(width: 6, height: 6)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .animation(
                            Animation.easeInOut(duration: 0.4)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                            value: animationPhase
                        )
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface(for: theme))
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .onAppear {
                animationPhase = 1
            }

            Spacer()
        }
    }
}

// MARK: - Chat Input Bar

struct ChatInputBar: View {
    @Binding var text: String
    let isProcessing: Bool
    let theme: DesignSystem.Theme
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            TextField("Type a message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.bodyMedium)
                .lineLimit(1...5)
                .onSubmit {
                    if !isProcessing {
                        onSend()
                    }
                }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing
                        ? DesignSystem.Colors.textTertiary
                        : DesignSystem.Colors.primary
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface(for: theme))
    }
}
