import SwiftUI
import AppKit

struct ModernChatView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var selectedModel = AIModel.plueCore
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Professional background
                DesignSystem.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Professional Header Bar
                    professionalHeaderBar
                    
                    // Enhanced Chat Messages Area
                    enhancedChatMessagesArea
                    
                    // Redesigned Input Area
                    enhancedInputArea
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }
    
    // MARK: - Professional Header Bar
    private var professionalHeaderBar: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // Left side - Chat Navigation with professional styling
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Previous chat button
                Button(action: {
                    if appState.chatState.currentConversationIndex > 0 {
                        core.handleEvent(.chatSelectConversation(appState.chatState.currentConversationIndex - 1))
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: DesignSystem.IconSize.medium, weight: .medium))
                }
                .buttonStyle(IconButtonStyle(size: DesignSystem.IconSize.medium))
                .help("Previous chat (⌘[)")
                .disabled(appState.chatState.currentConversationIndex == 0)
                .opacity(appState.chatState.currentConversationIndex == 0 ? 0.4 : 1.0)
                
                // Professional chat indicator
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversation")
                        .font(DesignSystem.Typography.labelSmall)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    Text("\(appState.chatState.currentConversationIndex + 1) of \(appState.chatState.conversations.count)")
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                // Next/New chat button
                Button(action: {
                    if appState.chatState.currentConversationIndex < appState.chatState.conversations.count - 1 {
                        core.handleEvent(.chatSelectConversation(appState.chatState.currentConversationIndex + 1))
                    } else {
                        core.handleEvent(.chatNewConversation)
                    }
                }) {
                    Image(systemName: appState.chatState.currentConversationIndex < appState.chatState.conversations.count - 1 ? "chevron.right" : "plus")
                        .font(.system(size: DesignSystem.IconSize.medium, weight: .medium))
                }
                .buttonStyle(IconButtonStyle(size: DesignSystem.IconSize.medium))
                .help(appState.chatState.currentConversationIndex < appState.chatState.conversations.count - 1 ? "Next chat (⌘])" : "New chat (⌘N)")
            }
            
            Spacer()
            
            // Center - Enhanced Model Picker
            enhancedModelPicker
            
            Spacer()
            
            // Right side - Professional Actions
            HStack(spacing: DesignSystem.Spacing.md) {
                // Enhanced status indicator
                StatusIndicator(
                    status: appState.openAIAvailable ? .online : .warning,
                    text: appState.openAIAvailable ? "AI Connected" : "Mock Mode"
                )
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(IconButtonStyle(size: DesignSystem.IconSize.medium))
                .help("Export conversation")
                
                Button(action: {}) {
                    Image(systemName: "trash")
                }
                .buttonStyle(IconButtonStyle(size: DesignSystem.IconSize.medium))
                .help("Clear conversation")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.lg)
        .background(
            DesignSystem.Colors.surface
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(DesignSystem.Colors.border)
                        .opacity(0.6),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Enhanced Model Picker
    private var enhancedModelPicker: some View {
        Menu {
            ForEach(AIModel.allCases, id: \.self) { model in
                Button(action: {
                    withAnimation(DesignSystem.Animation.smooth) {
                        selectedModel = model
                    }
                }) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Circle()
                            .fill(model.statusColor)
                            .frame(width: 10, height: 10)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                                .font(DesignSystem.Typography.labelMedium)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Text(model.description)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        if selectedModel == model {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: DesignSystem.IconSize.small))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Circle()
                    .fill(selectedModel.statusColor)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Model")
                        .font(DesignSystem.Typography.labelSmall)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    Text(selectedModel.name)
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: DesignSystem.IconSize.small))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .secondarySurface()
            .primaryBorder()
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .frame(maxWidth: 240)
    }
    
    // MARK: - Enhanced Chat Messages Area  
    private var enhancedChatMessagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.lg) {
                    // Enhanced welcome message
                    if appState.chatState.currentConversation?.messages.isEmpty ?? true {
                        enhancedWelcomeView
                            .padding(.top, DesignSystem.Spacing.massive)
                    }
                    
                    // Professional message bubbles
                    ForEach(appState.chatState.currentConversation?.messages ?? []) { message in
                        ProfessionalMessageBubbleView(message: message)
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .id(message.id)
                            .contentTransition()
                    }
                    
                    // Enhanced typing indicator
                    if appState.chatState.isGenerating {
                        ProfessionalTypingIndicatorView()
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                    }
                    
                    // Bottom spacing for better scrolling
                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
                .padding(.vertical, DesignSystem.Spacing.lg)
            }
            .scrollIndicators(.never)
            .background(DesignSystem.Colors.backgroundSecondary)
            .onChange(of: appState.chatState.currentConversation?.messages.count) { _ in
                withAnimation(DesignSystem.Animation.smooth) {
                    if let lastMessage = appState.chatState.currentConversation?.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Enhanced Welcome View
    private var enhancedWelcomeView: some View {
        VStack(spacing: DesignSystem.Spacing.xxxl) {
            // Professional logo with enhanced styling
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accentGradient)
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)
                    .opacity(0.3)
                
                Circle()
                    .fill(DesignSystem.Colors.surface)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(DesignSystem.Colors.primary)
                    )
            }
            
            VStack(spacing: DesignSystem.Spacing.md) {
                Text("How can I help you today?")
                    .font(DesignSystem.Typography.headlineSmall)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Ask me anything about your code, debug issues, or start a conversation. I'm here to help with your development workflow.")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            // Enhanced suggested prompts
            VStack(spacing: DesignSystem.Spacing.sm) {
                professionalSuggestionButton("Explain this code", icon: "doc.text.magnifyingglass")
                professionalSuggestionButton("Help me debug an issue", icon: "ladybug.fill")
                professionalSuggestionButton("Write a function for...", icon: "curlybraces")
                professionalSuggestionButton("Review my implementation", icon: "checkmark.seal.fill")
            }
        }
        .frame(maxWidth: 500)
        .multilineTextAlignment(.center)
    }
    
    private func professionalSuggestionButton(_ text: String, icon: String) -> some View {
        Button(action: {
            withAnimation(DesignSystem.Animation.smooth) {
                core.handleEvent(.chatMessageSent(text))
            }
        }) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: DesignSystem.IconSize.medium, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .frame(width: DesignSystem.IconSize.large)
                
                Text(text)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: DesignSystem.IconSize.small))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .secondarySurface()
            .primaryBorder()
        }
        .buttonStyle(PlainButtonStyle())
        .hoverEffect()
        .frame(maxWidth: 400)
    }
    
    // MARK: - Enhanced Input Area
    private var enhancedInputArea: some View {
        VStack(spacing: 0) {
            // Professional separator
            Rectangle()
                .frame(height: 1)
                .foregroundColor(DesignSystem.Colors.border)
                .opacity(0.8)
            
            HStack(spacing: DesignSystem.Spacing.lg) {
                // Enhanced attachment button
                Button(action: {}) {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(IconButtonStyle(size: DesignSystem.IconSize.medium))
                .help("Attach file (⌘O)")
                
                // Professional Vim Chat Input with enhanced styling
                VStack(spacing: DesignSystem.Spacing.xs) {
                    VimChatInputView(
                        onMessageSent: { message in
                            withAnimation(DesignSystem.Animation.smooth) {
                                core.handleEvent(.chatMessageSent(message))
                            }
                        },
                        onMessageUpdated: { message in
                            core.handleEvent(.chatMessageSent(message))
                        },
                        onNavigateUp: {
                            print("Navigate up - not implemented in core yet")
                        },
                        onNavigateDown: {
                            print("Navigate down - not implemented in core yet")
                        },
                        onPreviousChat: {
                            if appState.chatState.currentConversationIndex > 0 {
                                core.handleEvent(.chatSelectConversation(appState.chatState.currentConversationIndex - 1))
                            }
                        },
                        onNextChat: {
                            if appState.chatState.currentConversationIndex < appState.chatState.conversations.count - 1 {
                                core.handleEvent(.chatSelectConversation(appState.chatState.currentConversationIndex + 1))
                            } else {
                                core.handleEvent(.chatNewConversation)
                            }
                        }
                    )
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .secondarySurface()
                    .primaryBorder()
                }
                .frame(maxWidth: .infinity)
                
                // Professional help indicator
                VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xs) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(":w")
                            .font(DesignSystem.Typography.monoSmall)
                            .foregroundColor(DesignSystem.Colors.primary)
                        Text("send")
                            .font(DesignSystem.Typography.labelSmall)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("⌘[/⌘]")
                            .font(DesignSystem.Typography.monoSmall)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        Text("navigate")
                            .font(DesignSystem.Typography.labelSmall)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .opacity(0.8)
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.surface)
        }
    }
    
}

// MARK: - Professional Message Bubble View

struct ProfessionalMessageBubbleView: View {
    let message: CoreMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isUser {
                Spacer(minLength: 100)
                professionalUserMessageView
            } else {
                professionalAssistantMessageView
                Spacer(minLength: 100)
            }
        }
    }
    
    private var professionalUserMessageView: some View {
        VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .bottom, spacing: DesignSystem.Spacing.md) {
                Text(message.content)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .fill(DesignSystem.Colors.primaryGradient)
                    )
                    .textSelection(.enabled)
                
                // Enhanced user avatar
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 1)
                    )
                    .overlay(
                        Text("YOU")
                            .font(DesignSystem.Typography.captionMedium)
                            .foregroundColor(DesignSystem.Colors.primary)
                    )
            }
            
            Text(formatTime(message.timestamp))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .padding(.trailing, 44)
        }
    }
    
    private var professionalAssistantMessageView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                // Enhanced assistant avatar
                Circle()
                    .fill(DesignSystem.Colors.accentGradient)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: DesignSystem.IconSize.medium))
                            .foregroundColor(.white)
                    )
                
                Text(message.content)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .fill(DesignSystem.Colors.surface)
                    )
                    .primaryBorder()
                    .textSelection(.enabled)
            }
            
            Text(formatTime(message.timestamp))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .padding(.leading, 44)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Professional Typing Indicator

struct ProfessionalTypingIndicatorView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            // Enhanced assistant avatar
            Circle()
                .fill(DesignSystem.Colors.accentGradient)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: DesignSystem.IconSize.medium))
                        .foregroundColor(.white)
                )
            
            // Professional typing animation
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DesignSystem.Colors.primary.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.3 : 0.7)
                        .opacity(animationPhase == index ? 1.0 : 0.4)
                        .animation(
                            DesignSystem.Animation.smooth
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .fill(DesignSystem.Colors.surface)
            )
            .primaryBorder()
            
            Spacer()
        }
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Core Message Bubble View
struct CoreMessageBubbleView: View {
    let message: CoreMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isUser {
                Spacer(minLength: 80)
                userMessageView
            } else {
                assistantMessageView
                Spacer(minLength: 80)
            }
        }
    }
    
    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.blue)
                    )
                    .textSelection(.enabled)
                
                // User avatar
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("You")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                    )
            }
            
            Text(formatTime(message.timestamp))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.trailing, 40)
        }
    }
    
    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Assistant avatar
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "cpu")
                            .font(.system(size: 14))
                            .foregroundColor(.blue.opacity(0.7))
                    )
                
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                    )
                    .textSelection(.enabled)
            }
            
            Text(formatTime(message.timestamp))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 40)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Legacy Message Bubble View
struct MessageBubbleView: View {
    let message: ChatMessage
    let onAIMessageTapped: ((ChatMessage) -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isUser {
                Spacer(minLength: 80)
                userMessageView
            } else {
                assistantMessageView
                Spacer(minLength: 80)
            }
        }
    }
    
    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.blue)
                    )
                    .textSelection(.enabled)
                
                // User avatar
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("You")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                    )
            }
            
            Text(formatTime(message.timestamp))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.trailing, 40)
        }
    }
    
    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Assistant avatar
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "cpu")
                            .font(.system(size: 14))
                            .foregroundColor(.blue.opacity(0.7))
                    )
                
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                    )
                    .textSelection(.enabled)
                    .onTapGesture {
                        if !message.isUser {
                            print("MessageBubbleView: AI message tapped")
                            onAIMessageTapped?(message)
                        }
                    }
            }
            
            Text(formatTime(message.timestamp))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 40)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Typing Indicator
struct TypingIndicatorView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Assistant avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "cpu")
                        .font(.system(size: 14))
                        .foregroundColor(.blue.opacity(0.7))
                )
            
            // Typing dots
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
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

// MARK: - Sample Data
private let sampleMessages: [ChatMessage] = [
    ChatMessage(
        id: UUID(),
        content: "Hello! I'm your Plue Assistant. How can I help you with your coding projects today?",
        isUser: false,
        timestamp: Date().addingTimeInterval(-300)
    ),
    ChatMessage(
        id: UUID(),
        content: "Can you help me understand how this Zig and Swift integration works?",
        isUser: true,
        timestamp: Date().addingTimeInterval(-200)
    ),
    ChatMessage(
        id: UUID(),
        content: "Absolutely! The integration works by creating a C-compatible library in Zig that exports functions Swift can call. Here's how it works:\n\n1. **Zig Core**: We define exported functions with `export fn`\n2. **C Headers**: We create `.h` files that Swift can import\n3. **Swift Wrapper**: We wrap the C calls in safe Swift classes\n4. **UI Integration**: SwiftUI calls the Swift wrapper which calls Zig\n\nThis pattern gives us the performance of Zig with the native UI experience of SwiftUI. Would you like me to explain any specific part in more detail?",
        isUser: false,
        timestamp: Date().addingTimeInterval(-100)
    )
]

// MARK: - AI Model Configuration
enum AIModel: String, CaseIterable {
    case plueCore = "plue-core"
    case gpt4 = "gpt-4"
    case claude = "claude-3.5-sonnet"
    case local = "local-llm"
    
    var name: String {
        switch self {
        case .plueCore:
            return "Plue Core"
        case .gpt4:
            return "GPT-4"
        case .claude:
            return "Claude 3.5 Sonnet"
        case .local:
            return "Local LLM"
        }
    }
    
    var description: String {
        switch self {
        case .plueCore:
            return "Built-in Zig core engine"
        case .gpt4:
            return "OpenAI's most capable model"
        case .claude:
            return "Anthropic's latest model"
        case .local:
            return "Locally hosted model"
        }
    }
    
    var statusColor: LinearGradient {
        switch self {
        case .plueCore:
            return LinearGradient(
                colors: [Color.green.opacity(0.8), Color.blue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .gpt4:
            return LinearGradient(
                colors: [Color.green.opacity(0.8), Color.green.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .claude:
            return LinearGradient(
                colors: [Color.orange.opacity(0.8), Color.red.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .local:
            return LinearGradient(
                colors: [Color.purple.opacity(0.8), Color.indigo.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

#Preview {
    ModernChatView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 800, height: 600)
}