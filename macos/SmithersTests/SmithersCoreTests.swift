import Testing
import Foundation
@testable import Smithers

@Suite @MainActor struct SmithersCoreTests {
    @Test func callbacksInvokedInOrder() async throws {
        let chat = ChatModel()
        let core = try SmithersCore(chat: chat)

        chat.appendUserMessage("Hello")
        core.sendChatMessage("Hello")

        // Wait up to 2s for assistant to appear and stream to complete (CI-safe).
        let start = Date()
        while Date().timeIntervalSince(start) < 2.0 {
            if chat.messages.contains(where: { $0.role == .assistant }) && chat.isStreaming == false { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(chat.messages.contains { $0.role == .user })
        let assistant = chat.messages.last { $0.role == .assistant }
        #expect(assistant != nil)
        #expect(assistant!.text.count > 0)
        #expect(chat.isStreaming == false)
    }
}
