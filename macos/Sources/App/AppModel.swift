import Foundation
import Observation
import OSLog

@Observable @MainActor
final class AppModel {
    var theme: AppTheme = .dark
    // Stub workspace name per spec §5.3.1 (replaced when workspace opens)
    var workspaceName: String = "Smithers"
    let windowCoordinator = WindowCoordinator()
    private let logger = Logger(subsystem: "com.smithers", category: "app")

    // Chat + Core
    let chat = ChatModel()
    private(set) var core: SmithersCore?
    private(set) var history: ChatHistoryStore?
    private var currentSessionId: UUID?

    init() {
        // Initialize core bridge; keep UI responsive even if it fails.
        do {
            self.history = try ChatHistoryStore()
        } catch {
            self.logger.error("ChatHistoryStore init failed: \(String(describing: error), privacy: .public)")
            self.history = nil
        }
        do {
            let core = try SmithersCore(chat: chat)
            // Wire persistence hooks
            core.onAssistantDelta = { [weak self] _ in
                guard self != nil else { return }
                // Defer persisting until completion to avoid excessive writes; snapshot at turn end
            }
            core.onTurnComplete = { [weak self] in
                guard let self, let last = self.chat.messages.last, last.role == .assistant else { return }
                self.persist(.assistant, text: last.text)
            }
            self.core = core
        } catch { self.core = nil }
        // Load or create session and preload messages
        Task { @MainActor [weak self] in
            guard let self, let store = self.history else { return }
            if let sess = try? store.latestSession() {
                self.currentSessionId = sess.id
                let msgs = (try? store.loadMessages(sessionId: sess.id)) ?? []
                for m in msgs {
                    if let role = Self.mapRole(m.role) {
                        self.chat.messages.append(.init(id: m.id, role: role, text: m.content, isStreaming: false))
                    } else {
                        self.logger.warning("Skipping message with unknown role: \(m.role, privacy: .public)")
                    }
                }
            } else if let created = try? store.createSession(title: nil, workspacePath: nil) {
                self.currentSessionId = created.id
            }
        }
    }

    func sendChatMessage(_ text: String) {
        chat.appendUserMessage(text)
        core?.sendChatMessage(text)
        persist(.user, text: text)
    }

    private func persist(_ role: ChatMessage.Role, text: String) {
        guard let store = history, let sessionId = currentSessionId else { return }
        let roleStr = (role == .user) ? "user" : "assistant"
        let timestamp = Int64(Date().timeIntervalSince1970)
        Task { // inherit @MainActor to avoid sending non-Sendable references
            let rec = ChatHistoryStore.MessageRecord(
                id: UUID(), sessionId: sessionId, turnId: nil,
                role: roleStr, kind: "text", content: text, metadataJSON: nil,
                timestamp: timestamp
            )
            store.enqueueSaveMessage(rec)
            try? store.touchSession(sessionId)
        }
    }

    private static func mapRole(_ raw: String) -> ChatMessage.Role? {
        switch raw {
        case "user": return .user
        case "assistant": return .assistant
        case "command", "status", "system":
            // No dedicated UI bubble yet; treat as assistant-like elsewhere. Skip for now.
            return .assistant
        default: return nil
        }
    }
}
