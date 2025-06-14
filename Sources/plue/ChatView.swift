import SwiftUI
import AppKit

struct ChatView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var promptHistory: [String] = []
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Main content area
            VStack(spacing: 0) {
                // Top input field
                HStack {
                    MacTextField(text: $inputText, placeholder: "Enter your prompt...", onEnter: sendMessage)
                        .frame(height: 40)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                
                Divider()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                // Chat output area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
                    .onChange(of: messages.count) { _ in
                        if let lastMessage = messages.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            Divider()
                .background(Color(red: 0.2, green: 0.2, blue: 0.25))
            
            // Right sidebar - Prompt History
            VStack(alignment: .leading, spacing: 0) {
                Text("Prompt History")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.75))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(promptHistory.enumerated().reversed()), id: \.offset) { index, prompt in
                            PromptHistoryCard(prompt: prompt, index: promptHistory.count - index)
                                .onTapGesture {
                                    inputText = prompt
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
            .frame(width: 300)
            .background(Color(red: 0.08, green: 0.08, blue: 0.09))
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
        .onAppear {
            // Add some sample data
            addSampleData()
            // Focus the input field when the view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }
    
    private func sendMessage() {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        
        // Add user message
        let userMessage = ChatMessage(
            id: UUID(),
            content: trimmedInput,
            isUser: true,
            timestamp: Date()
        )
        messages.append(userMessage)
        
        // Add to history
        promptHistory.append(trimmedInput)
        
        // Clear input
        inputText = ""
        
        // Generate AI response using core (temporarily using mock response)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let responseContent = "Legacy ChatView response for: \(trimmedInput)"
            
            let aiResponse = ChatMessage(
                id: UUID(),
                content: responseContent,
                isUser: false,
                timestamp: Date()
            )
            messages.append(aiResponse)
        }
    }
    
    private func generateAIResponse(for input: String) -> String {
        return """
        I understand you want to: \(input)
        
        Let me break this down:
        • Analyzing your request
        • Checking available resources
        • Preparing implementation plan
        
        Status: Ready to proceed
        Estimated time: 2-3 minutes
        
        Would you like me to continue with this approach?
        """
    }
    
    private func addSampleData() {
        let samplePrompts = [
            "Create a new SwiftUI view for user profiles",
            "Implement core data persistence layer",
            "Add dark mode support to the app",
            "Write unit tests for the network layer",
            "Optimize app performance and memory usage"
        ]
        
        let sampleMessages = [
            ChatMessage(id: UUID(), content: "Welcome to your AI coding assistant. How can I help you today?", isUser: false, timestamp: Date().addingTimeInterval(-300)),
            ChatMessage(id: UUID(), content: "Show me the current project structure", isUser: true, timestamp: Date().addingTimeInterval(-240)),
            ChatMessage(id: UUID(), content: "Here's your current project structure:\n\n```\nSources/\n├── plue/\n│   ├── main.swift\n│   └── ContentView.swift\n└── Package.swift\n```\n\nThe project is set up as a Swift Package with SwiftUI support.", isUser: false, timestamp: Date().addingTimeInterval(-180))
        ]
        
        promptHistory = samplePrompts
        messages = sampleMessages
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
}

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar/Icon
            Circle()
                .fill(message.isUser ? 
                      Color(red: 0.0, green: 0.48, blue: 1.0) : 
                      Color(red: 0.2, green: 0.8, blue: 0.4))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: message.isUser ? "person.fill" : "cpu")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.isUser ? "You" : "AI Assistant")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(message.isUser ? 
                                       Color(red: 0.0, green: 0.48, blue: 1.0) : 
                                       Color(red: 0.2, green: 0.8, blue: 0.4))
                    
                    Spacer()
                    
                    Text(formatTimestamp(message.timestamp))
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                }
                
                Text(message.content)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.2, green: 0.2, blue: 0.25), lineWidth: 0.5)
                )
        )
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct PromptHistoryCard: View {
    let prompt: String
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(index)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
                
                Spacer()
                
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
            }
            
            Text(prompt)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(red: 0.25, green: 0.25, blue: 0.3), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered in
            // Add hover effect if needed
        }
    }
}

struct MacTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onEnter: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        textField.backgroundColor = NSColor.controlBackgroundColor
        textField.textColor = NSColor.labelColor
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: MacTextField
        
        init(_ parent: MacTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onEnter()
                return true
            }
            return false
        }
    }
}

#Preview {
    ChatView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}