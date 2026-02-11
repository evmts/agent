import Testing
@testable import Smithers

@Suite struct ChatHistoryStoreTests {
    @Test func open_migrates_and_crud_roundtrip() throws {
        // Use a temp db under /tmp to avoid touching user AppSupport.
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        let tmp = tmpRoot.appendingPathComponent("smithers-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbURL = tmp.appendingPathComponent("db.sqlite")
        let store = try ChatHistoryStore(databaseURL: dbURL)

        // Create session
        let sess = try store.createSession(title: "Test", workspacePath: "/w")
        #expect(sess.title == "Test")

        // Save message (debounced write); force flush by waiting max 1.1s
        let msg = ChatHistoryStore.MessageRecord(
            id: UUID(), sessionId: sess.id, turnId: nil,
            role: "user", kind: "text", content: "Hello",
            metadataJSON: nil, timestamp: Int64(Date().timeIntervalSince1970)
        )
        store.enqueueSaveMessage(msg)
        try await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s

        // Load
        let loaded = try store.loadMessages(sessionId: sess.id)
        #expect(loaded.count == 1)
        #expect(loaded.first?.content == "Hello")

        // Touch session and verify latestSession returns it
        try store.touchSession(sess.id)
        let latest = try store.latestSession()
        #expect(latest?.id == sess.id)

        // Delete session cascades messages
        try store.deleteSession(sess.id)
        let after = try store.loadMessages(sessionId: sess.id)
        #expect(after.isEmpty)
    }
}
