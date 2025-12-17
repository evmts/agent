import Foundation

/// HTTP client for communicating with the Agent backend
actor AgentClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: String) {
        self.baseURL = URL(string: baseURL)!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Session Management

    func createSession(title: String? = nil, parentID: String? = nil) async throws -> Session {
        var request = makeRequest(path: "/session", method: "POST")
        let body = CreateSessionRequest(title: title, parentID: parentID)
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func listSessions() async throws -> [Session] {
        let request = makeRequest(path: "/session", method: "GET")
        return try await perform(request)
    }

    func getSession(id: String) async throws -> Session {
        let request = makeRequest(path: "/session/\(id)", method: "GET")
        return try await perform(request)
    }

    func updateSession(id: String, title: String? = nil, archived: Bool? = nil) async throws -> Session {
        var request = makeRequest(path: "/session/\(id)", method: "PATCH")
        let body = UpdateSessionRequest(title: title, archived: archived)
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func deleteSession(id: String) async throws {
        let request = makeRequest(path: "/session/\(id)", method: "DELETE")
        _ = try await session.data(for: request)
    }

    // MARK: - Messages

    func listMessages(sessionID: String, limit: Int? = nil) async throws -> [MessageWithParts] {
        var path = "/session/\(sessionID)/message"
        if let limit = limit {
            path += "?limit=\(limit)"
        }
        let request = makeRequest(path: path, method: "GET")
        return try await perform(request)
    }

    func getMessage(sessionID: String, messageID: String) async throws -> MessageWithParts {
        let request = makeRequest(path: "/session/\(sessionID)/message/\(messageID)", method: "GET")
        return try await perform(request)
    }

    /// Send a message and receive SSE events
    func sendMessage(
        sessionID: String,
        text: String,
        agent: String? = nil,
        model: ModelInfo? = nil,
        system: String? = nil
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = makeRequest(path: "/session/\(sessionID)/message", method: "POST")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

                    let body = PromptRequest(
                        parts: [TextPartInput(type: "text", text: text)],
                        messageID: nil,
                        model: model,
                        agent: agent,
                        noReply: nil,
                        system: system,
                        tools: nil
                    )
                    request.httpBody = try encoder.encode(body)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw AgentClientError.invalidResponse
                    }

                    var currentEvent: String?
                    var dataLines: [String] = []

                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        } else if line.isEmpty && currentEvent != nil {
                            // End of event
                            let dataString = dataLines.joined(separator: "\n")
                            if let data = dataString.data(using: .utf8),
                               let event = try? decoder.decode(AgentEvent.self, from: data) {
                                continuation.yield(event)
                            }
                            currentEvent = nil
                            dataLines = []
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Session Actions

    func abortSession(id: String) async throws {
        let request = makeRequest(path: "/session/\(id)/abort", method: "POST")
        _ = try await session.data(for: request)
    }

    func forkSession(id: String, messageID: String? = nil) async throws -> Session {
        var request = makeRequest(path: "/session/\(id)/fork", method: "POST")
        if let messageID = messageID {
            let body = ["messageID": messageID]
            request.httpBody = try encoder.encode(body)
        }
        return try await perform(request)
    }

    // MARK: - Global Events

    func subscribeToEvents() -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = makeRequest(path: "/global/event", method: "GET")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw AgentClientError.invalidResponse
                    }

                    var currentEvent: String?
                    var dataLines: [String] = []

                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        } else if line.isEmpty && currentEvent != nil {
                            let dataString = dataLines.joined(separator: "\n")
                            if let data = dataString.data(using: .utf8),
                               let event = try? decoder.decode(AgentEvent.self, from: data) {
                                continuation.yield(event)
                            }
                            currentEvent = nil
                            dataLines = []
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Health & Info

    func checkHealth() async throws -> HealthResponse {
        let request = makeRequest(path: "/health", method: "GET")
        return try await perform(request)
    }

    func listAgents() async throws -> [AgentInfo] {
        let request = makeRequest(path: "/agent", method: "GET")
        return try await perform(request)
    }

    // MARK: - Helpers

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return try decoder.decode(T.self, from: data)
    }
}

enum AgentClientError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        }
    }
}
