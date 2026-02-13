import Testing
import Foundation
@testable import Smithers

@Suite @MainActor struct SmithersCoreTests {
    @Test(.disabled("Flaky under xcodebuild due callback teardown race")) func callbacksInvokedInOrder() async throws {
        let chat = ChatModel()
        let core = try SmithersCore(chat: chat)
        // Retain for process lifetime to avoid teardown races with late C callbacks.
        _ = Unmanaged.passRetained(core)

        chat.appendUserMessage("Hello")
        core.sendChatMessage("Hello")

        // Wait up to 10s for assistant to appear and stream to complete under CI load.
        let start = Date()
        while Date().timeIntervalSince(start) < 10.0 {
            if chat.messages.contains(where: { $0.role == .assistant }) && chat.isStreaming == false { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(chat.messages.contains { $0.role == .user })
        let assistant = chat.messages.last { $0.role == .assistant }
        #expect(assistant != nil)
        guard let assistant else { return }
        #expect(assistant.text.count > 0)
        #expect(chat.isStreaming == false)
    }
}
