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

    init() {
        // Initialize core bridge; keep UI responsive even if it fails.
        do { self.core = try SmithersCore(chat: chat) } catch { self.core = nil }
    }

    func sendChatMessage(_ text: String) {
        chat.appendUserMessage(text)
        core?.sendChatMessage(text)
    }
}
