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
                // Background
                Color(NSColor.controlBackgroundColor)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Bar
                    headerBar
                    
                    // Chat Messages Area
                    chatMessagesArea
                    
                    // Input Area
                    inputArea
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        HStack {
            // Left side - Chat Navigation
            HStack(spacing: 8) {
                // Previous chat button
                Button(action: {
                    if appState.chatState.currentConversationIndex > 0 {
                        core.handleEvent(.chatSelectConversation(appState.chatState.currentConversationIndex - 1))
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Previous chat (^H)")
                .disabled(appState.chatState.currentConversationIndex == 0)
                
                // Chat indicator
                Text("Chat \(appState.chatState.currentConversationIndex + 1) of \(appState.chatState.conversations.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                // Next/New chat button
                Button(action: {
                    if appState.chatState.currentConversationIndex < appState.chatState.conversations.count - 1 {
                        core.handleEvent(.chatSelectConversation(appState.chatState.currentConversationIndex + 1))
                    } else {
                        core.handleEvent(.chatNewConversation)
                    }
                }) {
                    Image(systemName: appState.chatState.currentConversationIndex < appState.chatState.conversations.count - 1 ? "chevron.right" : "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(appState.chatState.currentConversationIndex < appState.chatState.conversations.count - 1 ? "Next chat (^L)" : "New chat (^L)")
            }
            
            Spacer()
            
            // Center - Model Picker
            modelPicker
            
            Spacer()
            
            // Right side - Actions
            HStack(spacing: 12) {
                // OpenAI Status Indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.openAIAvailable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(appState.openAIAvailable ? "OpenAI" : "Mock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Export conversation")
                
                Button(action: {}) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear conversation")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Color(NSColor.controlBackgroundColor)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(NSColor.separatorColor))
                        .opacity(0.6),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Model Picker
    private var modelPicker: some View {
        Menu {
            ForEach(AIModel.allCases, id: \.self) { model in
                Button(action: {
                    selectedModel = model
                }) {
                    HStack {
                        Circle()
                            .fill(model.statusColor)
                            .frame(width: 8, height: 8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(model.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        if selectedModel == model {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(selectedModel.statusColor)
                    .frame(width: 8, height: 8)
                
                Text(selectedModel.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            )
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .frame(maxWidth: 200)
    }
    
    // MARK: - Chat Messages Area
    private var chatMessagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Welcome message at top
                    if appState.chatState.currentConversation?.messages.isEmpty ?? true {
                        welcomeView
                            .padding(.top, 60)
                    }
                    
                    // Messages
                    ForEach(appState.chatState.currentConversation?.messages ?? []) { message in
                        CoreMessageBubbleView(message: message)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .id(message.id)
                    }
                    
                    // Typing indicator
                    if appState.chatState.isGenerating {
                        TypingIndicatorView()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    
                    // Bottom spacing
                    Spacer(minLength: 20)
                }
            }
            .scrollIndicators(.never)
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: appState.chatState.currentConversation?.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    if let lastMessage = appState.chatState.currentConversation?.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Welcome View
    private var welcomeView: some View {
        VStack(spacing: 24) {
            // Logo/Icon
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.1),
                            Color.purple.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "cpu")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.blue.opacity(0.7))
                )
            
            VStack(spacing: 12) {
                Text("How can I help you today?")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("Ask me anything about your code, or start a conversation.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Suggested prompts
            VStack(spacing: 8) {
                suggestionButton("Explain this code")
                suggestionButton("Help me debug an issue")
                suggestionButton("Write a function for...")
                suggestionButton("Review my implementation")
            }
        }
        .frame(maxWidth: 400)
    }
    
    private func suggestionButton(_ text: String) -> some View {
        Button(action: {
            core.handleEvent(.chatMessageSent(text))
        }) {
            HStack {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered in
            NSCursor.pointingHand.push()
            if !isHovered {
                NSCursor.pop()
            }
        }
    }
    
    // MARK: - Input Area (Vim Buffer)
    private var inputArea: some View {
        VStack(spacing: 0) {
            // Separator line
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(NSColor.separatorColor))
                .opacity(0.6)
            
            HStack(spacing: 16) {
                // Attachment button
                Button(action: {}) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Attach file")
                
                // Vim Chat Input
                VimChatInputView(
                    onMessageSent: { message in
                        core.handleEvent(.chatMessageSent(message))
                    },
                    onMessageUpdated: { message in
                        // For now, treat updates as new messages
                        // TODO: Implement proper message update in core
                        core.handleEvent(.chatMessageSent(message))
                    },
                    onNavigateUp: {
                        // TODO: Add navigation events to core
                        print("Navigate up - not implemented in core yet")
                    },
                    onNavigateDown: {
                        // TODO: Add navigation events to core
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
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                
                // Help indicator
                VStack(alignment: .leading, spacing: 2) {
                    Text(":w to send")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("^K up • ^J down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("^H prev • ^L next")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(Color(NSColor.controlBackgroundColor))
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