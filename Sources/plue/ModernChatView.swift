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
                // Native macOS background with material
                Rectangle()
                    .fill(DesignSystem.Colors.background(for: appState.currentTheme))
                    .background(DesignSystem.Materials.regular)
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
    
    // MARK: - Native macOS Header Bar
    private var professionalHeaderBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Left side - Chat Navigation with native styling
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Previous chat button
                Button(action: {
                    if appState.promptState.currentConversationIndex > 0 {
                        core.handleEvent(.promptSelectConversation(appState.promptState.currentConversationIndex - 1))
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(appState.promptState.currentConversationIndex == 0 ? DesignSystem.Colors.textTertiary(for: appState.currentTheme) : DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Previous chat (⌘[)")
                .disabled(appState.promptState.currentConversationIndex == 0)
                .opacity(appState.promptState.currentConversationIndex == 0 ? 0.5 : 1.0)
                
                // Native macOS-style chat indicator
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversation \(appState.promptState.currentConversationIndex + 1)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("\(appState.promptState.conversations.count) total")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(DesignSystem.Colors.border(for: appState.currentTheme), lineWidth: 0.5)
                        )
                )
                
                // Next/New chat button with native styling
                Button(action: {
                    if appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 {
                        core.handleEvent(.promptSelectConversation(appState.promptState.currentConversationIndex + 1))
                    } else {
                        core.handleEvent(.promptNewConversation)
                    }
                }) {
                    Image(systemName: appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 ? "chevron.right" : "plus.circle")
                        .font(.system(size: 11, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
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
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            ZStack {
                // Material background for native feel
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                // Subtle overlay
                DesignSystem.Colors.surface(for: appState.currentTheme).opacity(0.3)
            }
            .overlay(
                Divider()
                    .background(DesignSystem.Colors.border(for: appState.currentTheme)),
                alignment: .bottom
            )
        )
    }
    
    // MARK: - Native macOS Model Picker
    private var enhancedModelPicker: some View {
        Menu {
            ForEach(AIModel.allCases, id: \.self) { model in
                Button(action: {
                    withAnimation(DesignSystem.Animation.plueStandard) {
                        selectedModel = model
                    }
                }) {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .font(.system(size: 13))
                                
                                Text(model.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                            }
                        } icon: {
                            Circle()
                                .fill(model.statusColor)
                                .frame(width: 8, height: 8)
                        }
                        
                        Spacer()
                        
                        if selectedModel == model {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(selectedModel.statusColor)
                    .frame(width: 8, height: 8)
                
                Text(selectedModel.name)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(DesignSystem.Colors.border(for: appState.currentTheme), lineWidth: 0.5)
                    )
            )
        }
        .menuStyle(BorderlessButtonMenuStyle())
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
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
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
                withAnimation(DesignSystem.Animation.plueStandard) {
                    if let lastMessage = appState.promptState.currentConversation?.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Native macOS Welcome View
    private var enhancedWelcomeView: some View {
        VStack(spacing: DesignSystem.Spacing.xxl) {
            // Native macOS icon style
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.primary.opacity(0.2),
                                DesignSystem.Colors.primary.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 72, height: 72)
                
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 32, weight: .regular, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Welcome to Plue")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    .accessibilityIdentifier(AccessibilityIdentifiers.chatWelcomeTitle)
                
                Text("Start a conversation to begin")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
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
            withAnimation(DesignSystem.Animation.buttonPress) {
                inputText = text
                isInputFocused = true
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(DesignSystem.Colors.primary)
                    .frame(width: 20)
                
                Text(text.capitalized)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignSystem.Materials.regular)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.surface(for: appState.currentTheme).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(DesignSystem.Colors.border(for: appState.currentTheme), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: 320)
    }
    
    // MARK: - Native macOS Chat Input
    private var enhancedInputArea: some View {
        VStack(spacing: 0) {
            // Native macOS input field
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    // Attachment button
                    Button(action: {}) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Attach file")
                    
                    // Input field with native styling
                    TextField("Message", text: $inputText, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13))
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .accessibilityIdentifier(AccessibilityIdentifiers.chatInputField)
                        .onSubmit {
                            if !inputText.isEmpty {
                                sendMessage()
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isInputFocused ? DesignSystem.Colors.primary : DesignSystem.Colors.border(for: appState.currentTheme),
                                    lineWidth: isInputFocused ? 1 : 0.5
                                )
                        )
                )
                .animation(.easeInOut(duration: 0.15), value: isInputFocused)
                
                // Native macOS send button
                Button(action: {
                    withAnimation(DesignSystem.Animation.buttonPress) {
                        sendMessage()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(inputText.isEmpty ? 
                                DesignSystem.Colors.surface(for: appState.currentTheme) : 
                                DesignSystem.Colors.primary
                            )
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(inputText.isEmpty ? 
                                DesignSystem.Colors.textTertiary(for: appState.currentTheme) : 
                                .white
                            )
                    }
                }
                .disabled(inputText.isEmpty)
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier(AccessibilityIdentifiers.chatSendButton)
                .help("Send message (⏎)")
                .opacity(inputText.isEmpty ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: inputText.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                // Native macOS toolbar-style background
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    
                    DesignSystem.Colors.background(for: appState.currentTheme)
                        .opacity(0.8)
                }
                .overlay(
                    Divider()
                        .background(DesignSystem.Colors.border(for: appState.currentTheme)),
                    alignment: .top
                )
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

// ProfessionalMessageBubbleView has been replaced by UnifiedMessageBubbleView with .professional style

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
                            DesignSystem.Animation.plueStandard
                                .repeatForever()
                                .delay(Double(index) * 0.15),
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
                            Animation.easeInOut(duration: 0.4)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
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