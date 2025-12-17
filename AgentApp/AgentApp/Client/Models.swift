import Foundation

// MARK: - Session

struct Session: Codable, Identifiable {
    let id: String
    let projectID: String
    let directory: String
    let title: String
    let version: String
    let time: SessionTime
    let parentID: String?
    let summary: SessionSummary?
    let revert: RevertInfo?

    var formattedDate: String {
        let date = Date(timeIntervalSince1970: time.created)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct SessionTime: Codable {
    let created: Double
    let updated: Double
    let archived: Double?
}

struct SessionSummary: Codable {
    let changed: Int
    let added: Int
    let removed: Int
}

struct RevertInfo: Codable {
    let version: Int
    let count: Int
}

// MARK: - Message

struct Message: Codable, Identifiable {
    let id: String
    let sessionID: String
    let role: String
    let time: MessageTime

    // User message fields
    var agent: String?
    var model: ModelInfo?
    var system: String?
    var tools: [String: Bool]?

    // Assistant message fields
    var parentID: String?
    var modelID: String?
    var providerID: String?
    var mode: String?
    var path: PathInfo?
    var cost: Double?
    var tokens: TokenInfo?
    var finish: String?
    var error: String?

    init(
        id: String,
        sessionID: String,
        role: String,
        time: MessageTime,
        agent: String? = nil,
        model: ModelInfo? = nil,
        system: String? = nil,
        tools: [String: Bool]? = nil,
        parentID: String? = nil,
        modelID: String? = nil,
        providerID: String? = nil,
        mode: String? = nil,
        path: PathInfo? = nil,
        cost: Double? = nil,
        tokens: TokenInfo? = nil,
        finish: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.time = time
        self.agent = agent
        self.model = model
        self.system = system
        self.tools = tools
        self.parentID = parentID
        self.modelID = modelID
        self.providerID = providerID
        self.mode = mode
        self.path = path
        self.cost = cost
        self.tokens = tokens
        self.finish = finish
        self.error = error
    }
}

struct MessageTime: Codable {
    let created: Double
    let updated: Double
    var stopped: Double?
    var completed: Double?
    var firstToken: Double?

    init(
        created: Double,
        updated: Double,
        stopped: Double? = nil,
        completed: Double? = nil,
        firstToken: Double? = nil
    ) {
        self.created = created
        self.updated = updated
        self.stopped = stopped
        self.completed = completed
        self.firstToken = firstToken
    }
}

struct MessageWithParts: Codable, Identifiable {
    let info: Message
    let parts: [Part]

    var id: String { info.id }
}

// MARK: - Part

struct Part: Codable, Identifiable {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String

    // Text/Reasoning
    var text: String?
    var time: PartTime?

    // Tool execution
    var tool: String?
    var state: ToolState?

    // Files
    var mime: String?
    var url: String?
    var filename: String?

    init(
        id: String,
        sessionID: String,
        messageID: String,
        type: String,
        text: String? = nil,
        time: PartTime? = nil,
        tool: String? = nil,
        state: ToolState? = nil,
        mime: String? = nil,
        url: String? = nil,
        filename: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.messageID = messageID
        self.type = type
        self.text = text
        self.time = time
        self.tool = tool
        self.state = state
        self.mime = mime
        self.url = url
        self.filename = filename
    }
}

struct PartTime: Codable {
    let created: Double
    let updated: Double
}

struct ToolState: Codable {
    let status: String
    let input: [String: AnyCodable]?
    let output: String?
    let title: String?
    let progress: ToolProgress?
}

struct ToolProgress: Codable {
    let current: Int
    let total: Int
    let description: String?
}

// MARK: - Model & Token Info

struct ModelInfo: Codable {
    let id: String
    let provider: String?
}

struct PathInfo: Codable {
    let prompt: Int
    let completion: Int
}

struct TokenInfo: Codable {
    let input: Int
    let output: Int
    let cache: CacheInfo?
}

struct CacheInfo: Codable {
    let read: Int
    let write: Int
}

// MARK: - Requests

struct CreateSessionRequest: Codable {
    let title: String?
    let parentID: String?
}

struct UpdateSessionRequest: Codable {
    let title: String?
    let archived: Bool?
}

struct PromptRequest: Codable {
    let parts: [TextPartInput]
    let messageID: String?
    let model: ModelInfo?
    let agent: String?
    let noReply: Bool?
    let system: String?
    let tools: [String: Bool]?
}

struct TextPartInput: Codable {
    let type: String
    let text: String
}

struct FilePartInput: Codable {
    let type: String
    let mime: String
    let url: String
    let filename: String?
}

// MARK: - Events

struct AgentEvent: Codable {
    let type: String
    let properties: EventProperties
}

struct EventProperties: Codable {
    // Session events
    let session: Session?

    // Message events
    let info: Message?
    let parts: [Part]?

    // Part events
    let id: String?
    let sessionID: String?
    let messageID: String?
    let partType: String?
    let text: String?
    let tool: String?
    let state: ToolState?

    enum CodingKeys: String, CodingKey {
        case session, info, parts
        case id, sessionID, messageID
        case partType = "type"
        case text, tool, state
    }
}

// MARK: - Other

struct HealthResponse: Codable {
    let status: String
    let agentConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case agentConfigured = "agent_configured"
    }
}

struct AgentInfo: Codable {
    let name: String
    let description: String?
    let tools: [String]?
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
