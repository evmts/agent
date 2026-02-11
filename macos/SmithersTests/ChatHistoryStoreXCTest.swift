import XCTest
@testable import Smithers

final class ChatHistoryStoreXCTest: XCTestCase {
    func testCRUDRoundTrip() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("smithers-tests-")
        let dbURL = tmpDir.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        let store = try ChatHistoryStore(databaseURL: dbURL)

        // Create session
        let sess = try store.createSession(title: "Test", workspacePath: "/w")
        XCTAssertEqual(sess.title, "Test")

        // Save message (debounced)
        let msg = ChatHistoryStore.MessageRecord(
            id: UUID(), sessionId: sess.id, turnId: nil,
            role: "user", kind: "text", content: "Hello",
            metadataJSON: nil, timestamp: Int64(Date().timeIntervalSince1970)
        )
        store.enqueueSaveMessage(msg)
        // Allow debounce to flush (max 1s configured)
        let exp = expectation(description: "debounced write")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        // Load
        let loaded = try store.loadMessages(sessionId: sess.id)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "Hello")

        // Touch and latest
        try store.touchSession(sess.id)
        let latest = try store.latestSession()
        XCTAssertEqual(latest?.id, sess.id)

        // Delete session cascades
        try store.deleteSession(sess.id)
        let after = try store.loadMessages(sessionId: sess.id)
        XCTAssertTrue(after.isEmpty)
    }
}

