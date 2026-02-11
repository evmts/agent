import Foundation
import Observation

@Observable @MainActor
final class AppModel {
    var theme: AppTheme = .dark
    // Stub workspace name per spec §5.3.1 (replaced when workspace opens)
    var workspaceName: String = "Smithers"
    let windowCoordinator = WindowCoordinator()

    // Chat + Core
    let chat = ChatModel()
    private(set) var core: SmithersCore?
    private(set) var history: ChatHistoryStore?

    init() {
        // Initialize core bridge; keep UI responsive even if it fails.
        do {
            self.history = try ChatHistoryStore()
        } catch {
            self.history = nil
        }
        do {
            let core = try SmithersCore(chat: chat)
            // Wire persistence hooks
            core.onAssistantDelta = { [weak self] _ in
                guard let self else { return }
                // Defer persisting until completion to avoid excessive writes; snapshot at turn end
            }
            core.onTurnComplete = { [weak self] in
                guard let self, let last = self.chat.messages.last, last.role == .assistant else { return }
                self.persist(.assistant, text: last.text)
            }
            self.core = core
        } catch { self.core = nil }
        // Load last session messages if any (non-blocking)
        Task { @MainActor [weak self] in
            guard let self, let store = self.history else { return }
            if let sess = try? store.latestSession() {
                let msgs = (try? store.loadMessages(sessionId: sess.id)) ?? []
                for m in msgs {
                    let role: ChatMessage.Role = (m.role == "user") ? .user : .assistant
                    self.chat.messages.append(.init(id: m.id, role: role, text: m.content, isStreaming: false))
                }
            } else {
                // No session: create one upfront for persistence continuity
                _ = try? store.createSession(title: nil, workspacePath: nil)
            }
        }
    }

    func sendChatMessage(_ text: String) {
        chat.appendUserMessage(text)
        core?.sendChatMessage(text)
        persist(.user, text: text)
    }

    private func persist(_ role: ChatMessage.Role, text: String) {
        guard let store = history else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            // Ensure we have (or create) a current session id
            let current: ChatHistoryStore.SessionRecord
            if let s = try? store.latestSession() { current = s }
            else { current = try (store.createSession(title: nil, workspacePath: nil)) }
            let rec = ChatHistoryStore.MessageRecord(
                id: UUID(), sessionId: current.id, turnId: nil,
                role: role == .user ? "user" : "assistant",
                kind: "text", content: text, metadataJSON: nil,
                timestamp: Int64(Date().timeIntervalSince1970)
            )
            store.enqueueSaveMessage(rec)
            try? store.touchSession(current.id)
        }
    }
}
