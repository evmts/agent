import Foundation

// Stub OpenAI service - not connecting to backend
struct OpenAIMessage {
    let role: String
    let content: String
}

class OpenAIService {
    init() throws {
        throw OpenAIError.notConfigured
    }

    func sendChatMessage(messages: [OpenAIMessage], model: String, temperature: Double) async throws -> String {
        throw OpenAIError.notConfigured
    }

    func convertToOpenAIMessages(_ messages: [PromptMessage]) -> [OpenAIMessage] {
        return messages.map { OpenAIMessage(role: $0.type == .user ? "user" : "assistant", content: $0.content) }
    }
}

enum OpenAIError: Error {
    case notConfigured
}
