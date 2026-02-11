import Foundation
import GRDB
import OSLog

// ChatHistoryStore — GRDB-backed chat persistence layer.
// Mirrors Zig schema in src/storage.zig ensureSchema():
// sessions(id TEXT PK, thread_id TEXT NULL, title TEXT NULL, workspace_path TEXT NULL,
//          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
// messages(id TEXT PK, session_id TEXT NOT NULL FK→sessions(id) ON DELETE CASCADE,
//          turn_id TEXT NULL, role TEXT NOT NULL, kind TEXT NOT NULL, content TEXT NOT NULL,
//          metadata_json TEXT NULL, timestamp INTEGER NOT NULL)
// Indexes: idx_messages_session, idx_messages_timestamp, idx_sessions_workspace

final class ChatHistoryStore {
    enum StoreError: Error { case openFailed }

    private let dbPool: DatabasePool
    private let logger = Logger(subsystem: "com.smithers", category: "storage")
    private let debounce: Debouncer

    // Default path per spec: ~/Library/Application Support/Smithers/smithers.db
    static func defaultDatabaseURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport.appendingPathComponent("Smithers", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("smithers.db")
    }

    init(databaseURL: URL? = nil) throws {
        let url = try databaseURL ?? Self.defaultDatabaseURL()
        if let custom = databaseURL {
            let dir = custom.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL;")
            try db.execute(sql: "PRAGMA synchronous=NORMAL;")
            try db.execute(sql: "PRAGMA foreign_keys=ON;")
        }
        self.dbPool = try DatabasePool(path: url.path, configuration: config)
        self.debounce = Debouncer(minDelay: .milliseconds(300), maxDelay: .seconds(1))
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS sessions (
                  id TEXT PRIMARY KEY,
                  thread_id TEXT,
                  title TEXT,
                  workspace_path TEXT,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL
                );
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS messages (
                  id TEXT PRIMARY KEY,
                  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                  turn_id TEXT,
                  role TEXT NOT NULL,
                  kind TEXT NOT NULL,
                  content TEXT NOT NULL,
                  metadata_json TEXT,
                  timestamp INTEGER NOT NULL
                );
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_sessions_workspace ON sessions(workspace_path);")
        }
        try migrator.migrate(dbPool)
    }

    // MARK: Records
    struct SessionRecord: Equatable {
        let id: UUID
        var threadId: String?
        var title: String?
        var workspacePath: String?
        var createdAt: Int64
        var updatedAt: Int64
    }

    struct MessageRecord: Equatable {
        let id: UUID
        let sessionId: UUID
        var turnId: String?
        let role: String
        let kind: String
        var content: String
        var metadataJSON: String?
        var timestamp: Int64
    }

    // MARK: Sessions
    func latestSession() throws -> SessionRecord? {
        try dbPool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM sessions ORDER BY updated_at DESC LIMIT 1")
            if let r = row, let srec = Self.sessionFromRow(r) { return srec }
            return nil
        }
    }

    func createSession(title: String?, workspacePath: String?) throws -> SessionRecord {
        let id = UUID()
        let now = Self.now()
        try dbPool.write { db in
            try db.execute(sql: "INSERT INTO sessions(id, thread_id, title, workspace_path, created_at, updated_at) VALUES (?,?,?,?,?,?)",
                           arguments: [id.uuidString, nil, title, workspacePath, now, now])
        }
        return .init(id: id, threadId: nil, title: title, workspacePath: workspacePath, createdAt: now, updatedAt: now)
    }

    func touchSession(_ id: UUID) throws {
        let now = Self.now()
        try dbPool.write { db in
            try db.execute(sql: "UPDATE sessions SET updated_at=? WHERE id=?", arguments: [now, id.uuidString])
        }
    }

    func loadAllSessions() throws -> [SessionRecord] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM sessions ORDER BY updated_at DESC")
            return rows.compactMap(Self.sessionFromRow)
        }
    }

    func updateSession(_ id: UUID, title: String?) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE sessions SET title = ?, updated_at = ? WHERE id = ?",
                           arguments: [title, Self.now(), id.uuidString])
        }
    }

    func updateMessage(id: UUID, newContent: String, metadataJSON: String?, timestamp: Int64) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE messages SET content = ?, metadata_json = ?, timestamp = ? WHERE id = ?",
                           arguments: [newContent, metadataJSON, timestamp, id.uuidString])
        }
    }

    func deleteMessage(id: UUID) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM messages WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: Messages
    func loadMessages(sessionId: UUID) throws -> [MessageRecord] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC", arguments: [sessionId.uuidString])
            return rows.compactMap(Self.messageFromRow)
        }
    }

    func enqueueSaveMessage(_ msg: MessageRecord) {
        guard let args = StatementArguments([msg.id.uuidString as Any, msg.sessionId.uuidString as Any, msg.turnId as Any, msg.role as Any, msg.kind as Any, msg.content as Any, msg.metadataJSON as Any, msg.timestamp as Any]) else {
            logger.error("Failed to build SQL args for message \(msg.id.uuidString, privacy: .public)")
            return
        }
        let debouncer = self.debounce
        Task.detached { [dbPool, debouncer, args] in
            await debouncer.schedule {
                try dbPool.write { db in
                    try db.execute(sql: "INSERT OR REPLACE INTO messages(id, session_id, turn_id, role, kind, content, metadata_json, timestamp) VALUES (?,?,?,?,?,?,?,?)",
                                   arguments: args)
                }
            }
        }
    }
    
    func deleteSession(_ id: UUID) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM sessions WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: Helpers
    private static func now() -> Int64 { Int64(Date().timeIntervalSince1970) }

    private static func sessionFromRow(_ row: Row) -> SessionRecord? {
        let idStr: String = row["id"]
        guard let uuid = UUID(uuidString: idStr) else {
            Logger(subsystem: "com.smithers", category: "storage").error("Invalid session UUID: \(idStr, privacy: .public)")
            return nil
        }
        return .init(
            id: uuid,
            threadId: row["thread_id"],
            title: row["title"],
            workspacePath: row["workspace_path"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func messageFromRow(_ row: Row) -> MessageRecord? {
        let idStr: String = row["id"]; let sessStr: String = row["session_id"]
        guard let mid = UUID(uuidString: idStr), let sid = UUID(uuidString: sessStr) else {
            Logger(subsystem: "com.smithers", category: "storage").error("Invalid message/session UUID: \(idStr, privacy: .public) / \(sessStr, privacy: .public)")
            return nil
        }
        let turnId: String? = row["turn_id"]
        let role: String = row["role"]
        let kind: String = row["kind"]
        let content: String = row["content"]
        let metadata: String? = row["metadata_json"]
        let ts: Int64 = row["timestamp"]
        return MessageRecord(id: mid, sessionId: sid, turnId: turnId, role: role, kind: kind, content: content, metadataJSON: metadata, timestamp: ts)
    }
}

// Simple async/await debouncer with max wait and batching.

actor Debouncer {
    private let minDelay: Duration
    private let maxDelay: Duration
    private var scheduled: Task<Void, Never>? = nil
    private var firstAt: ContinuousClock.Instant? = nil
    private var ops: [@Sendable () throws -> Void] = []
    private let logger = Logger(subsystem: "com.smithers", category: "storage")

    init(minDelay: Duration, maxDelay: Duration) {
        self.minDelay = minDelay
        self.maxDelay = maxDelay
    }

    func schedule(operation: @escaping @Sendable () throws -> Void) {
        ops.append(operation)
        guard scheduled == nil else { return }
        let now = ContinuousClock.now
        if firstAt == nil { firstAt = now }
        let elapsed = firstAt.map { $0.duration(to: now) } ?? .zero
        let remaining: Duration = elapsed >= maxDelay ? .zero : maxDelay - elapsed
        let delay: Duration = elapsed >= maxDelay ? .zero : min(minDelay, remaining)
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            await self?.flush()
        }
    }

    private func flush() {
        let current = ops
        ops.removeAll()
        firstAt = nil
        scheduled = nil
        for op in current {
            do { try op() } catch {
                logger.error("Debounced operation failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
