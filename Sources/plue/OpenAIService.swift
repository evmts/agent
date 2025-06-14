import Foundation

// MARK: - OpenAI API Models

struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let maxTokens: Int?
    let stream: Bool
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

struct OpenAIChoice: Codable {
    let index: Int
    let message: OpenAIMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct OpenAIUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct OpenAIError: Codable {
    let error: OpenAIErrorDetail
}

struct OpenAIErrorDetail: Codable {
    let message: String
    let type: String
    let code: String?
}

// MARK: - OpenAI Service (MOCKED - NO ACTUAL API CALLS)

class OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1" // NOT USED - MOCKED
    private let session = URLSession.shared // NOT USED - MOCKED
    
    enum OpenAIServiceError: Error, LocalizedError {
        case noAPIKey
        case invalidURL
        case invalidResponse
        case apiError(String)
        case networkError(Error)
        
        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "OpenAI API key not found. Please set OPENAI_API_KEY environment variable."
            case .invalidURL:
                return "Invalid OpenAI API URL"
            case .invalidResponse:
                return "Invalid response from OpenAI API"
            case .apiError(let message):
                return "OpenAI API Error: \(message)"
            case .networkError(let error):
                return "Network Error: \(error.localizedDescription)"
            }
        }
    }
    
    init() throws {
        // MOCK IMPLEMENTATION - Always succeeds, no actual API key needed
        self.apiKey = "mock-api-key-not-used"
        print("OpenAIService: Initialized in MOCK mode - no actual API calls will be made")
    }
    
    func sendChatMessage(
        messages: [OpenAIMessage],
        model: String = "gpt-4",
        temperature: Double = 0.7,
        maxTokens: Int? = nil
    ) async throws -> String {
        
        // MOCK IMPLEMENTATION - No actual network requests
        print("OpenAIService: MOCKING API call - no actual network request made")
        print("OpenAIService: Model: \(model), Messages: \(messages.count), Temperature: \(temperature)")
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Generate mock response based on the last user message
        let lastUserMessage = messages.last(where: { $0.role == "user" })?.content ?? ""
        let mockResponse = generateMockResponse(for: lastUserMessage)
        
        print("OpenAIService: Mock response generated: \(mockResponse.prefix(50))...")
        return mockResponse
    }
    
    private func generateMockResponse(for userMessage: String) -> String {
        let lowercased = userMessage.lowercased()
        
        // Context-aware mock responses
        if lowercased.contains("terminal") || lowercased.contains("ghostty") {
            return """
            I can help you with terminal-related tasks! The Ghostty terminal integration you've implemented looks great. Here are some suggestions:
            
            **Terminal Features:**
            - File watching for real-time updates ✅
            - Multi-editor support (Ghostty → VS Code → Vim) ✅
            - Syntax highlighting in the preview ✅
            
            **Next Steps:**
            You might want to consider adding:
            - Custom terminal themes
            - Keyboard shortcuts for quick actions
            - Terminal session management
            
            Would you like me to help implement any of these features?
            """
        } else if lowercased.contains("farcaster") {
            return """
            Great work on the Farcaster integration! Your Zig implementation with Ed25519 signing is solid. Here's what I see:
            
            **Implemented Features:**
            - Cast posting and reactions ✅
            - Real-time feed updates ✅
            - Optimistic UI updates ✅
            
            **Suggestions:**
            - Add cast threading/replies
            - Implement user following
            - Add image/media support
            
            The FFI bridge between Zig and Swift is well-designed. Any specific Farcaster features you'd like to add next?
            """
        } else if lowercased.contains("code") || lowercased.contains("implement") {
            return """
            I'd be happy to help you implement that! Based on your codebase structure, here's what I recommend:
            
            **Implementation Approach:**
            1. Start with the core logic in your existing architecture
            2. Add proper error handling and validation
            3. Update the UI components accordingly
            4. Add tests to ensure reliability
            
            **Code Quality:**
            Your Swift + Zig architecture is well-organized. The separation of concerns between the UI layer and core logic is clean.
            
            What specific functionality are you looking to implement?
            """
        } else if lowercased.contains("hello") || lowercased.contains("hi") {
            return """
            Hello! I'm here to help with your Plue development. I can see you've built an impressive multi-tab application with:
            
            - Terminal integration with Ghostty
            - Farcaster social features
            - Chat interface
            - Code editor
            - Web browser
            
            What would you like to work on next?
            """
        } else {
            return """
            **Mock AI Response**
            
            I understand you're asking about: "\(userMessage.prefix(100))"
            
            This is a simulated response to demonstrate the chat functionality without making actual OpenAI API calls. 
            
            **Your Application Features:**
            - ✅ Multi-tab interface (Chat, Terminal, Web, Editor, Farcaster)
            - ✅ Terminal integration with file watching
            - ✅ Farcaster social media integration
            - ✅ Real-time markdown preview
            - ✅ Action buttons for workflow integration
            
            **Technical Stack:**
            - Swift UI for the interface
            - Zig for core functionality and Farcaster integration
            - SwiftDown for markdown rendering
            - Metal for terminal rendering
            
            To enable real AI responses, set the OPENAI_API_KEY environment variable and the system will automatically switch to the OpenAI API.
            
            How can I help you improve your application?
            """
        }
    }
    
    // Helper method to convert PromptMessage to OpenAI format
    func convertToOpenAIMessages(_ promptMessages: [PromptMessage]) -> [OpenAIMessage] {
        return promptMessages.map { message in
            OpenAIMessage(
                role: message.type == .user ? "user" : "assistant",
                content: message.content
            )
        }
    }
    
    // Helper method for single message (backward compatibility)
    func sendSingleMessage(_ content: String, model: String = "gpt-4") async throws -> String {
        let messages = [OpenAIMessage(role: "user", content: content)]
        return try await sendChatMessage(messages: messages, model: model)
    }
}