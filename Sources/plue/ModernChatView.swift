import SwiftUI
import AppKit

// MARK: - Navigation Direction
enum NavigationDirection {
    case up
    case down
}

struct ModernChatView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var selectedModel = AIModel.plueCore
    @State private var inputText: String = ""
    @State private var activeMessageId: String? = nil
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
    
    // MARK: - Minimal Header Bar (Ghostty-inspired)
    private var professionalHeaderBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Left side - Minimal Chat Navigation
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Previous chat button
                Button(action: {
                    if appState.promptState.currentConversationIndex > 0 {
                        core.handleEvent(.promptSelectConversation(appState.promptState.currentConversationIndex - 1))
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(appState.promptState.currentConversationIndex == 0 ? DesignSystem.Colors.textTertiary.opacity(0.3) : DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Previous chat (⌘[)")
                .disabled(appState.promptState.currentConversationIndex == 0)
                
                // Minimal chat indicator
                VStack(alignment: .leading, spacing: 1) {
                    Text("chat")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    Text("\(appState.promptState.currentConversationIndex + 1)/\(appState.promptState.conversations.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                // Next/New chat button
                Button(action: {
                    if appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 {
                        core.handleEvent(.promptSelectConversation(appState.promptState.currentConversationIndex + 1))
                    } else {
                        core.handleEvent(.promptNewConversation)
                    }
                }) {
                    Image(systemName: appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 ? "chevron.right" : "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 ? "Next chat (⌘])" : "New chat (⌘N)")
            }
            
            Spacer()
            
            // Center - Enhanced Model Picker
            enhancedModelPicker
            
            Spacer()
            
            // Right side - Minimal Actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Minimal status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.openAIAvailable ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                        .frame(width: 6, height: 6)
                    
                    Text(appState.openAIAvailable ? "ai" : "mock")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Export conversation")
                
                Button(action: {}) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear conversation")
                
                // Theme toggle button
                Button(action: {
                    core.handleEvent(.themeToggled)
                }) {
                    Image(systemName: appState.currentTheme == .dark ? "sun.max" : "moon")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle theme")
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
                    if appState.promptState.currentConversation?.messages.isEmpty ?? true {
                        enhancedWelcomeView
                            .padding(.top, DesignSystem.Spacing.massive)
                    }
                    
                    // Professional message bubbles with enhanced animations
                    if let messages = appState.promptState.currentConversation?.messages {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            ProfessionalMessageBubbleView(
                                message: message,
                                isActive: activeMessageId == message.id,
                                theme: appState.currentTheme
                            )
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                            .animation(
                                DesignSystem.Animation.messageAppear.delay(Double(index) * DesignSystem.Animation.staggerDelay),
                                value: messages.count
                            )
                        }
                    }
                    
                    // Enhanced typing indicator with smooth appearance
                    if appState.promptState.isProcessing {
                        ProfessionalTypingIndicatorView()
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                                removal: .opacity.combined(with: .scale(scale: 0.8))
                            ))
                            .animation(DesignSystem.Animation.messageAppear, value: appState.promptState.isProcessing)
                    }
                    
                    // Bottom spacing for better scrolling
                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
                .padding(.vertical, DesignSystem.Spacing.lg)
            }
            .scrollIndicators(.never)
            .background(DesignSystem.Colors.backgroundSecondary)
            .onChange(of: appState.promptState.currentConversation?.messages.count) { _ in
                withAnimation(DesignSystem.Animation.smooth) {
                    if let lastMessage = appState.promptState.currentConversation?.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Minimal Welcome View (Ghostty-inspired)
    private var enhancedWelcomeView: some View {
        VStack(spacing: DesignSystem.Spacing.xxl) {
            // Minimal logo
            Circle()
                .fill(DesignSystem.Colors.textTertiary.opacity(0.1))
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "terminal")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                )
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("ready")
                    .font(DesignSystem.Typography.titleMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("type a message to start")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Minimal suggested prompts
            VStack(spacing: 6) {
                minimalSuggestionButton("explain code", icon: "doc.text")
                minimalSuggestionButton("debug issue", icon: "ladybug")
                minimalSuggestionButton("write function", icon: "curlybraces")
                minimalSuggestionButton("review code", icon: "checkmark")
            }
        }
        .frame(maxWidth: 500)
        .multilineTextAlignment(.center)
    }
    
    private func minimalSuggestionButton(_ text: String, icon: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                core.handleEvent(.promptMessageSent(text))
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
    
    // MARK: - Simplified Chat Input - Clean and Apple-like
    private var enhancedInputArea: some View {
        VStack(spacing: 0) {
            // Floating input at bottom with subtle gradient fade
            HStack(spacing: 12) {
                TextField("Message", text: $inputText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.08))
                    )
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: {
                    withAnimation(DesignSystem.Animation.socialInteraction) {
                        sendMessage()
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(inputText.isEmpty ? .white.opacity(0.3) : DesignSystem.Colors.primary)
                        .scaleEffect(inputText.isEmpty ? 0.9 : 1.0)
                        .rotationEffect(.degrees(inputText.isEmpty ? 0 : 360))
                        .animation(DesignSystem.Animation.buttonPress, value: inputText.isEmpty)
                }
                .disabled(inputText.isEmpty)
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(inputText.isEmpty ? 0.95 : 1.0)
                .animation(DesignSystem.Animation.plueStandard, value: inputText.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                // Subtle gradient fade at bottom
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: DesignSystem.Colors.backgroundSecondary(for: appState.currentTheme), location: 0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                .offset(y: -50)
            )
        }
    }
    
    // Simple send function
    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        
        withAnimation(DesignSystem.Animation.plueStandard) {
            core.handleEvent(.promptMessageSent(message))
        }
        
        inputText = ""
    }
    
    // MARK: - Navigation and Editing Logic
    
    private func navigateMessages(direction: NavigationDirection) {
        guard let conversation = appState.promptState.currentConversation else { return }
        let messages = conversation.messages
        
        if let currentActiveId = activeMessageId,
           let currentIndex = messages.firstIndex(where: { $0.id == currentActiveId }) {
            // Navigate from current active message
            switch direction {
            case .up:
                if currentIndex > 0 {
                    activeMessageId = messages[currentIndex - 1].id
                }
            case .down:
                if currentIndex < messages.count - 1 {
                    activeMessageId = messages[currentIndex + 1].id
                }
            }
        } else {
            // No active message, start from the most recent
            switch direction {
            case .up:
                activeMessageId = messages.last?.id
            case .down:
                activeMessageId = messages.first?.id
            }
        }
    }
    
    private func editActiveMessage() {
        guard let activeId = activeMessageId,
              let message = appState.promptState.currentConversation?.messages.first(where: { $0.id == activeId })
        else { return }
        
        // Load message content into input field for editing
        inputText = message.content
    }
    
}

// MARK: - Professional Message Bubble View

struct ProfessionalMessageBubbleView: View {
    let message: PromptMessage
    let isActive: Bool
    let theme: DesignSystem.Theme
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.type == .user {
                Spacer(minLength: 100)
                professionalUserMessageView
            } else {
                professionalAssistantMessageView
                Spacer(minLength: 100)
            }
        }
        .background(
            // Highlight active message
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .fill(isActive ? DesignSystem.Colors.primary.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                        .stroke(isActive ? DesignSystem.Colors.primary.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .animation(DesignSystem.Animation.quick, value: isActive)
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
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .fill(DesignSystem.Colors.surface(for: theme))
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
    let message: PromptMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.type == .user {
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
    let message: PromptMessage
    let onAIMessageTapped: ((PromptMessage) -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.type == .user {
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
                        if message.type != .user {
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
// Sample messages removed - using actual PromptMessage data from core state instead

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