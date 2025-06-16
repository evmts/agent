import SwiftUI

// MARK: - Unified Message Protocol
protocol UnifiedMessage: Identifiable {
    var id: String { get }
    var content: String { get }
    var timestamp: Date { get }
    var senderType: MessageSenderType { get }
    var metadata: MessageMetadata? { get }
}

// MARK: - Message Configuration
enum MessageSenderType {
    case user
    case assistant
    case system
    case workflow
    case error
    
    var avatarIcon: String {
        switch self {
        case .user: return "person"
        case .assistant: return "brain.head.profile"
        case .system: return "info.circle"
        case .workflow: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle"
        }
    }
    
    var defaultAvatarText: String {
        switch self {
        case .user: return "U"
        case .assistant: return "AI"
        case .system: return "S"
        case .workflow: return "W"
        case .error: return "!"
        }
    }
}

struct MessageMetadata {
    let worktree: String?
    let workflow: String?
    let containerId: String?
    let exitCode: Int?
    let duration: TimeInterval?
    let promptSnapshot: String?
    
    static let empty = MessageMetadata(
        worktree: nil,
        workflow: nil,
        containerId: nil,
        exitCode: nil,
        duration: nil,
        promptSnapshot: nil
    )
}

// MARK: - Message Style Configuration
struct MessageBubbleStyle {
    // Avatar configuration
    let avatarSize: CGFloat
    let avatarStyle: AvatarStyle
    
    // Bubble configuration
    let bubbleCornerRadius: CGFloat
    let bubblePadding: EdgeInsets
    let maxBubbleWidth: CGFloat?
    
    // Typography
    let contentFont: Font
    let timestampFont: Font
    let metadataFont: Font
    
    // Spacing
    let avatarSpacing: CGFloat
    let timestampSpacing: CGFloat
    let metadataSpacing: CGFloat
    
    // Colors
    let userBubbleBackground: Color
    let assistantBubbleBackground: Color
    let systemBubbleBackground: Color
    let errorBubbleBackground: Color
    
    // Animation
    let showAnimations: Bool
    let animationDuration: Double
    
    enum AvatarStyle {
        case icon
        case text
        case iconWithText
        case custom(Image)
    }
    
    // Preset styles
    static let professional = MessageBubbleStyle(
        avatarSize: 36,
        avatarStyle: .iconWithText,
        bubbleCornerRadius: DesignSystem.CornerRadius.lg,
        bubblePadding: EdgeInsets(
            top: DesignSystem.Spacing.md,
            leading: DesignSystem.Spacing.lg,
            bottom: DesignSystem.Spacing.md,
            trailing: DesignSystem.Spacing.lg
        ),
        maxBubbleWidth: nil,
        contentFont: DesignSystem.Typography.bodyMedium,
        timestampFont: DesignSystem.Typography.caption,
        metadataFont: DesignSystem.Typography.caption,
        avatarSpacing: DesignSystem.Spacing.md,
        timestampSpacing: DesignSystem.Spacing.xs,
        metadataSpacing: DesignSystem.Spacing.xs,
        userBubbleBackground: DesignSystem.Colors.primary,
        assistantBubbleBackground: DesignSystem.Colors.surface,
        systemBubbleBackground: DesignSystem.Colors.surface,
        errorBubbleBackground: DesignSystem.Colors.error.opacity(0.1),
        showAnimations: true,
        animationDuration: 0.2
    )
    
    static let compact = MessageBubbleStyle(
        avatarSize: 28,
        avatarStyle: .text,
        bubbleCornerRadius: 12,
        bubblePadding: EdgeInsets(
            top: 8,
            leading: 12,
            bottom: 8,
            trailing: 12
        ),
        maxBubbleWidth: nil,
        contentFont: DesignSystem.Typography.bodyMedium,
        timestampFont: .system(size: 9),
        metadataFont: .system(size: 9),
        avatarSpacing: 12,
        timestampSpacing: 4,
        metadataSpacing: 4,
        userBubbleBackground: DesignSystem.Colors.primary,
        assistantBubbleBackground: DesignSystem.Colors.surface,
        systemBubbleBackground: DesignSystem.Colors.surface,
        errorBubbleBackground: DesignSystem.Colors.error.opacity(0.1),
        showAnimations: false,
        animationDuration: 0
    )
    
    static let minimal = MessageBubbleStyle(
        avatarSize: 24,
        avatarStyle: .icon,
        bubbleCornerRadius: 8,
        bubblePadding: EdgeInsets(
            top: 6,
            leading: 10,
            bottom: 6,
            trailing: 10
        ),
        maxBubbleWidth: 400,
        contentFont: .system(size: 13),
        timestampFont: .system(size: 9),
        metadataFont: .system(size: 9),
        avatarSpacing: 8,
        timestampSpacing: 2,
        metadataSpacing: 2,
        userBubbleBackground: DesignSystem.Colors.primary.opacity(0.9),
        assistantBubbleBackground: DesignSystem.Colors.surface,
        systemBubbleBackground: DesignSystem.Colors.textTertiary.opacity(0.1),
        errorBubbleBackground: DesignSystem.Colors.error.opacity(0.1),
        showAnimations: false,
        animationDuration: 0
    )
}

// MARK: - Unified Message Bubble View
struct UnifiedMessageBubbleView<Message: UnifiedMessage>: View {
    let message: Message
    let style: MessageBubbleStyle
    let isActive: Bool
    let theme: DesignSystem.Theme
    let onTap: ((Message) -> Void)?
    
    init(
        message: Message,
        style: MessageBubbleStyle = .professional,
        isActive: Bool = false,
        theme: DesignSystem.Theme = .dark,
        onTap: ((Message) -> Void)? = nil
    ) {
        self.message = message
        self.style = style
        self.isActive = isActive
        self.theme = theme
        self.onTap = onTap
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.senderType == .user {
                Spacer(minLength: 100)
                userMessageView
            } else {
                assistantMessageView
                Spacer(minLength: 100)
            }
        }
        .background(activeHighlight)
        .animation(style.showAnimations ? .easeInOut(duration: style.animationDuration) : nil, value: isActive)
    }
    
    // MARK: - User Message View
    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: style.timestampSpacing) {
            HStack(alignment: .bottom, spacing: style.avatarSpacing) {
                messageBubble(isUser: true)
                avatarView(for: .user)
            }
            
            timestampView
                .padding(.trailing, style.avatarSize + style.avatarSpacing)
        }
    }
    
    // MARK: - Assistant/System Message View
    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: style.timestampSpacing) {
            HStack(alignment: .top, spacing: style.avatarSpacing) {
                avatarView(for: message.senderType)
                messageBubble(isUser: false)
            }
            
            VStack(alignment: .leading, spacing: style.metadataSpacing) {
                timestampView
                
                if let metadata = message.metadata {
                    metadataView(metadata)
                }
            }
            .padding(.leading, style.avatarSize + style.avatarSpacing)
        }
    }
    
    // MARK: - Message Bubble
    private func messageBubble(isUser: Bool) -> some View {
        Text(message.content)
            .font(style.contentFont)
            .foregroundColor(textColor(for: message.senderType, isUser: isUser))
            .padding(style.bubblePadding)
            .frame(maxWidth: style.maxBubbleWidth, alignment: isUser ? .trailing : .leading)
            .background(
                RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                    .fill(bubbleBackground(for: message.senderType))
                    .overlay(
                        Group {
                            if !isUser && message.senderType != .user {
                                RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                                    .stroke(borderColor(for: message.senderType), lineWidth: 0.5)
                            }
                        }
                    )
            )
            .textSelection(.enabled)
            .onTapGesture {
                onTap?(message)
            }
    }
    
    // MARK: - Avatar View
    private func avatarView(for senderType: MessageSenderType) -> some View {
        Group {
            switch style.avatarStyle {
            case .icon:
                Circle()
                    .fill(avatarBackground(for: senderType))
                    .frame(width: style.avatarSize, height: style.avatarSize)
                    .overlay(
                        Image(systemName: senderType.avatarIcon)
                            .font(.system(size: style.avatarSize * 0.4, weight: .medium))
                            .foregroundColor(avatarForeground(for: senderType))
                    )
                
            case .text:
                Circle()
                    .fill(avatarBackground(for: senderType))
                    .frame(width: style.avatarSize, height: style.avatarSize)
                    .overlay(
                        Text(senderType.defaultAvatarText)
                            .font(.system(size: style.avatarSize * 0.35, weight: .medium))
                            .foregroundColor(avatarForeground(for: senderType))
                    )
                
            case .iconWithText:
                Circle()
                    .fill(avatarBackground(for: senderType))
                    .frame(width: style.avatarSize, height: style.avatarSize)
                    .overlay(
                        Group {
                            if senderType == .user {
                                Text("YOU")
                                    .font(.system(size: style.avatarSize * 0.25, weight: .medium))
                                    .foregroundColor(avatarForeground(for: senderType))
                            } else {
                                Image(systemName: senderType.avatarIcon)
                                    .font(.system(size: style.avatarSize * 0.4, weight: .medium))
                                    .foregroundColor(avatarForeground(for: senderType))
                            }
                        }
                    )
                
            case .custom(let image):
                Circle()
                    .fill(avatarBackground(for: senderType))
                    .frame(width: style.avatarSize, height: style.avatarSize)
                    .overlay(
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: style.avatarSize * 0.6, height: style.avatarSize * 0.6)
                    )
            }
        }
        .overlay(
            Circle()
                .stroke(avatarBorder(for: senderType), lineWidth: 1)
        )
    }
    
    // MARK: - Timestamp View
    private var timestampView: some View {
        Text(formatTime(message.timestamp))
            .font(style.timestampFont)
            .foregroundColor(DesignSystem.Colors.textTertiary)
    }
    
    // MARK: - Metadata View
    private func metadataView(_ metadata: MessageMetadata) -> some View {
        HStack(spacing: 4) {
            if let worktree = metadata.worktree {
                Text("•")
                    .font(style.metadataFont)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                
                Text(worktree)
                    .font(style.metadataFont.monospaced())
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            
            if let duration = metadata.duration {
                Text("•")
                    .font(style.metadataFont)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                
                Text("\(String(format: "%.1fs", duration))")
                    .font(style.metadataFont)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            
            if let exitCode = metadata.exitCode {
                Text("•")
                    .font(style.metadataFont)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                
                Text("exit: \(exitCode)")
                    .font(style.metadataFont)
                    .foregroundColor(exitCode == 0 ? DesignSystem.Colors.success : DesignSystem.Colors.error)
            }
        }
    }
    
    // MARK: - Active Highlight
    private var activeHighlight: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
            .fill(isActive ? DesignSystem.Colors.primary.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(isActive ? DesignSystem.Colors.primary.opacity(0.3) : Color.clear, lineWidth: 1)
            )
    }
    
    // MARK: - Color Helpers
    private func bubbleBackground(for senderType: MessageSenderType) -> Color {
        switch senderType {
        case .user:
            return style.userBubbleBackground
        case .assistant:
            return style.assistantBubbleBackground
        case .system:
            return style.systemBubbleBackground
        case .workflow:
            return DesignSystem.Colors.success.opacity(0.1)
        case .error:
            return style.errorBubbleBackground
        }
    }
    
    private func textColor(for senderType: MessageSenderType, isUser: Bool) -> Color {
        if isUser {
            return .white
        }
        
        switch senderType {
        case .error:
            return DesignSystem.Colors.error
        case .workflow:
            return DesignSystem.Colors.success
        default:
            return DesignSystem.Colors.textPrimary(for: theme)
        }
    }
    
    private func avatarBackground(for senderType: MessageSenderType) -> Color {
        switch senderType {
        case .user:
            return DesignSystem.Colors.primary.opacity(0.1)
        case .assistant:
            return DesignSystem.Colors.accent
        case .system:
            return DesignSystem.Colors.textTertiary.opacity(0.6)
        case .workflow:
            return DesignSystem.Colors.success
        case .error:
            return DesignSystem.Colors.error
        }
    }
    
    private func avatarForeground(for senderType: MessageSenderType) -> Color {
        switch senderType {
        case .user:
            return DesignSystem.Colors.primary
        case .assistant, .system, .workflow, .error:
            return .white
        }
    }
    
    private func avatarBorder(for senderType: MessageSenderType) -> Color {
        switch senderType {
        case .user:
            return DesignSystem.Colors.primary.opacity(0.3)
        default:
            return DesignSystem.Colors.border.opacity(0.3)
        }
    }
    
    private func borderColor(for senderType: MessageSenderType) -> Color {
        switch senderType {
        case .error:
            return DesignSystem.Colors.error.opacity(0.3)
        case .workflow:
            return DesignSystem.Colors.success.opacity(0.3)
        default:
            return DesignSystem.Colors.border.opacity(0.3)
        }
    }
    
    // MARK: - Helpers
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Message Adapters
// These adapters allow existing message types to work with the unified view

extension PromptMessage: UnifiedMessage {
    var senderType: MessageSenderType {
        switch type {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .system
        }
    }
    
    var metadata: MessageMetadata? {
        MessageMetadata(
            worktree: nil,
            workflow: nil,
            containerId: nil,
            exitCode: nil,
            duration: nil,
            promptSnapshot: promptSnapshot
        )
    }
}

// Wrapper for AgentMessage to conform to UnifiedMessage
struct UnifiedAgentMessage: UnifiedMessage {
    let agentMessage: AgentMessage
    
    var id: String { agentMessage.id }
    var content: String { agentMessage.content }
    var timestamp: Date { agentMessage.timestamp }
    
    var senderType: MessageSenderType {
        switch agentMessage.type {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .system
        case .workflow: return .workflow
        case .error: return .error
        }
    }
    
    var metadata: MessageMetadata? {
        guard let agentMetadata = agentMessage.metadata else { return nil }
        return MessageMetadata(
            worktree: agentMetadata.worktree,
            workflow: agentMetadata.workflow,
            containerId: agentMetadata.containerId,
            exitCode: agentMetadata.exitCode,
            duration: agentMetadata.duration,
            promptSnapshot: nil  // AgentMessageMetadata doesn't have this field
        )
    }
}

// MARK: - Preview
#Preview("Message Styles") {
    VStack(spacing: 20) {
        // Professional style
        VStack(alignment: .leading, spacing: 8) {
            Text("Professional Style")
                .font(.headline)
            
            UnifiedMessageBubbleView(
                message: PromptMessage(
                    id: "1",
                    content: "Hello! How can I help you today?",
                    type: .assistant,
                    timestamp: Date(),
                    promptSnapshot: nil
                ),
                style: .professional
            )
            
            UnifiedMessageBubbleView(
                message: PromptMessage(
                    id: "2",
                    content: "I need help with SwiftUI",
                    type: .user,
                    timestamp: Date(),
                    promptSnapshot: nil
                ),
                style: .professional
            )
        }
        
        // Compact style
        VStack(alignment: .leading, spacing: 8) {
            Text("Compact Style")
                .font(.headline)
            
            UnifiedMessageBubbleView(
                message: UnifiedAgentMessage(agentMessage: AgentMessage(
                    id: "3",
                    content: "Running workflow: Build & Test",
                    type: .workflow,
                    timestamp: Date(),
                    metadata: AgentMessageMetadata(
                        worktree: "feature-branch",
                        workflow: "build-test",
                        containerId: nil,
                        exitCode: 0,
                        duration: 3.5
                    )
                )),
                style: .compact
            )
        }
        
        // Minimal style with error
        VStack(alignment: .leading, spacing: 8) {
            Text("Minimal Style")
                .font(.headline)
            
            UnifiedMessageBubbleView(
                message: UnifiedAgentMessage(agentMessage: AgentMessage(
                    id: "4",
                    content: "Build failed: Missing dependency",
                    type: .error,
                    timestamp: Date(),
                    metadata: AgentMessageMetadata(
                        worktree: "main",
                        workflow: nil,
                        containerId: nil,
                        exitCode: 1,
                        duration: nil
                    )
                )),
                style: .minimal
            )
        }
    }
    .padding()
    .background(DesignSystem.Colors.background)
    .frame(width: 600, height: 500)
}