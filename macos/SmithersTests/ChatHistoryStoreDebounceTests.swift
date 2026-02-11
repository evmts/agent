import XCTest
@testable import Smithers

final class ChatHistoryStoreDebounceTests: XCTestCase {
    func testDebouncerBatchesWithinMaxDelay() async throws {
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        let tmp = tmpRoot.appendingPathComponent("smithers-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        let dbURL = tmp.appendingPathComponent("db.sqlite")
        let store = try ChatHistoryStore(databaseURL: dbURL)

        let sess = try store.createSession(title: "Debounce", workspacePath: nil)

        // Enqueue 3 messages quickly
        for i in 0..<3 {
            let rec = ChatHistoryStore.MessageRecord(
                id: UUID(), sessionId: sess.id, turnId: nil,
                role: "assistant", kind: "text", content: "m\(i)", metadataJSON: nil,
                timestamp: Int64(Date().timeIntervalSince1970)
            )
            store.enqueueSaveMessage(rec)
        }
        // Wait less than maxDelay, more than minDelay
        try await Task.sleep(nanoseconds: 900_000_000)

        let loaded = try store.loadMessages(sessionId: sess.id)
        XCTAssertEqual(loaded.count, 3, "All enqueued messages should flush, not just last one")
    }
}

