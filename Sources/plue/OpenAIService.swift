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

// MARK: - OpenAI Service

class OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private let session = URLSession.shared
    
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
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], 
              !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }
        self.apiKey = apiKey
    }
    
    func sendChatMessage(
        messages: [OpenAIMessage],
        model: String = "gpt-4",
        temperature: Double = 0.7,
        maxTokens: Int? = nil
    ) async throws -> String {
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw OpenAIServiceError.invalidURL
        }
        
        let request = OpenAIRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false
        )
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw OpenAIServiceError.networkError(error)
        }
        
        do {
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIServiceError.invalidResponse
            }
            
            if httpResponse.statusCode == 200 {
                let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                
                guard let firstChoice = openAIResponse.choices.first else {
                    throw OpenAIServiceError.invalidResponse
                }
                
                return firstChoice.message.content
                
            } else {
                // Try to parse error response
                if let errorResponse = try? JSONDecoder().decode(OpenAIError.self, from: data) {
                    throw OpenAIServiceError.apiError(errorResponse.error.message)
                } else {
                    throw OpenAIServiceError.apiError("HTTP \(httpResponse.statusCode)")
                }
            }
            
        } catch let error as OpenAIServiceError {
            throw error
        } catch {
            throw OpenAIServiceError.networkError(error)
        }
    }
    
    // Helper method to convert CoreMessage to OpenAI format
    func convertToOpenAIMessages(_ coreMessages: [CoreMessage]) -> [OpenAIMessage] {
        return coreMessages.map { message in
            OpenAIMessage(
                role: message.isUser ? "user" : "assistant",
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