# Context: chat-persistence-sqlite

## Ticket
Add chat persistence (SQLite via GRDB) and wire to ChatModel.

---

## 1. Zig Storage Schema (MUST match exactly)

**File:** `src/storage.zig` lines 305-345

```sql
-- sessions table (lines 321-328)
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  thread_id TEXT,
  title TEXT,
  workspace_path TEXT,
  created_at INTEGER NOT NULL,   -- unix timestamp
  updated_at INTEGER NOT NULL    -- unix timestamp
);

-- messages table (lines 329-338)
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  turn_id TEXT,
  role TEXT NOT NULL,
  kind TEXT NOT NULL,
  content TEXT NOT NULL,
  metadata_json TEXT,
  timestamp INTEGER NOT NULL     -- unix timestamp
);

-- Indexes (lines 340-342)
CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
CREATE INDEX IF NOT EXISTS idx_sessions_workspace ON sessions(workspace_path);
```

**Zig storage pragmas** (lines 101-103):
```
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
```

**DB path (from spec):** `~/Library/Application Support/Smithers/smithers.db`

---

## 2. Current Swift Models (need extension)

**ChatMessage.swift** (`macos/Sources/Features/Chat/Models/ChatMessage.swift`):
```swift
struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Equatable { case user; case assistant }
    let id: UUID
    let role: Role
    var text: String
    var isStreaming: Bool
}
```
**Gap:** No `sessionId`, `turnId`, `kind`, `metadataJson`, `timestamp` fields. Uses `UUID` (must convert to/from TEXT for SQLite).

**ChatModel.swift** (`macos/Sources/Features/Chat/Models/ChatModel.swift`):
```swift
@Observable @MainActor final class ChatModel {
    var messages: [ChatMessage] = []
    var isStreaming: Bool = false
    private var streamingIndex: Int? = nil
    var deltaCountThisTurn: Int = 0
}
```
**Gap:** No sessions array, no selectedSession, no persistence hooks. Pure in-memory.

---

## 3. AppModel Wiring

**AppModel.swift** (`macos/Sources/App/AppModel.swift`):
```swift
@Observable @MainActor final class AppModel {
    var theme: AppTheme = .dark
    var workspaceName: String = "Smithers"
    let windowCoordinator = WindowCoordinator()
    let chat = ChatModel()
    private(set) var core: SmithersCore?
    init() {
        do { self.core = try SmithersCore(chat: chat) } catch { self.core = nil }
    }
    func sendChatMessage(_ text: String) {
        chat.appendUserMessage(text)
        core?.sendChatMessage(text)
    }
}
```
**Integration point:** AppModel.init() should open DB, load sessions. `sendChatMessage` should persist.

---

## 4. Xcode Project Structure

**No GRDB dependency exists.** Must add via Xcode SPM (File > Add Package Dependencies > `https://github.com/groue/GRDB.swift`).

**No SPM package references** in current pbxproj. This will be the first SPM dependency.

**Chat/Models group** exists on disk (`macos/Sources/Features/Chat/Models/`) with ChatMessage.swift and ChatModel.swift, but the Xcode pbxproj has a flat Chat group with only Views listed. The Models files ARE in the Sources build phase (lines 200-201) and compile fine — they just aren't in a "Models" folder group in the project navigator. New files need:
1. PBXFileReference entry
2. PBXBuildFile entry in app Sources phase
3. PBXBuildFile entry in test Sources phase (for test files)
4. Group membership

**Test target:** SmithersTests (lines 207-220). Uses Swift Testing framework (`@Suite`, `@Test`, `#expect`). Tests bundle into the app (`TEST_HOST`). Swift 6.0 strict concurrency.

---

## 5. V1 Reference Patterns

### JJSnapshotStore (v1 GRDB pattern — `prototype0/Smithers/JJSnapshotStore.swift`)
```swift
import GRDB

@MainActor class JJSnapshotStore {
    private var dbQueue: DatabaseQueue?

    func setup() throws {
        let dbPath = dbDir.appendingPathComponent("snapshots.db").path
        var config = Configuration()
        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_tables") { db in
            try db.create(table: "snapshots", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("changeId", .text).notNull()
                // ...
            }
        }
        try migrator.migrate(dbQueue!)
    }
}
```

### V1 Debounced Persistence (`prototype0/Smithers/WorkspaceState.swift`):
```swift
private func scheduleChatHistoryPersist() {
    guard !suppressChatHistoryPersistence else { return }
    chatHistoryPersistTask?.cancel()
    chatHistoryPersistTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1s debounce
        guard let self, !Task.isCancelled else { return }
        let messages = self.chatMessages
        DispatchQueue.global(qos: .utility).async {
            ChatHistoryStore.saveHistory(messages, for: root)
        }
    }
}
```

### V1 GRDB Record Model (`prototype0/Smithers/JJModels.swift`):
```swift
struct Snapshot: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "snapshots"
    var id: Int64?
    let changeId: String
    // ...
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

---

## 6. GRDB Key Patterns for Implementation

### DatabasePool vs DatabaseQueue
- **Use `DatabasePool`** for production (WAL by default, concurrent reads)
- **Use `DatabaseQueue()`** (no path = in-memory) for unit tests
- Both conform to `DatabaseWriter` protocol — inject via protocol for testability

### Schema Migration
```swift
var migrator = DatabaseMigrator()
#if DEBUG
migrator.eraseDatabaseOnSchemaChange = true
#endif
migrator.registerMigration("v1_sessions_messages") { db in
    try db.create(table: "sessions") { t in
        t.primaryKey("id", .text)
        t.column("thread_id", .text)
        t.column("title", .text)
        t.column("workspace_path", .text)
        t.column("created_at", .integer).notNull()
        t.column("updated_at", .integer).notNull()
    }
    try db.create(table: "messages") { t in
        t.primaryKey("id", .text)
        t.column("session_id", .text).notNull()
            .indexed()
            .references("sessions", onDelete: .cascade)
        t.column("turn_id", .text)
        t.column("role", .text).notNull()
        t.column("kind", .text).notNull()
        t.column("content", .text).notNull()
        t.column("metadata_json", .text)
        t.column("timestamp", .integer).notNull()
    }
    try db.create(index: "idx_messages_timestamp", on: "messages", columns: ["timestamp"])
    try db.create(index: "idx_sessions_workspace", on: "sessions", columns: ["workspace_path"])
}
try migrator.migrate(dbWriter)
```

### Record Types
```swift
struct SessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sessions"
    let id: String           // UUID().uuidString
    var threadId: String?    // snake_case columns mapped via CodingKeys
    var title: String?
    var workspacePath: String?
    var createdAt: Int64     // Unix timestamp
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, title
        case threadId = "thread_id"
        case workspacePath = "workspace_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

### Debounced Writes
```swift
private var persistTask: Task<Void, Never>?

func schedulePersist() {
    persistTask?.cancel()
    persistTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self else { return }
        await self.flushPendingWrites()
    }
}
```

### Testing with In-Memory DB
```swift
@Suite @MainActor struct ChatHistoryStoreTests {
    @Test func roundTrip() throws {
        let store = try ChatHistoryStore(dbWriter: DatabaseQueue())
        let session = SessionRecord(id: UUID().uuidString, ...)
        try store.saveSession(session)
        let loaded = try store.loadSession(id: session.id)
        #expect(loaded?.title == session.title)
    }
}
```

---

## 7. Gotchas & Pitfalls

1. **GRDB not yet added to Xcode project.** This is the first SPM dependency. Must add via Xcode UI or manually edit pbxproj. Recommend Xcode UI (File > Add Package Dependencies) since manual pbxproj SPM edits are complex and fragile.

2. **Column naming mismatch.** Zig uses `snake_case` columns (`created_at`, `thread_id`). Swift GRDB Codable records use `camelCase` properties by default. MUST use `CodingKeys` enum to map. Without this, GRDB silently creates wrong column names or fails to decode.

3. **Timestamps as integers.** Zig schema stores `created_at`/`updated_at`/`timestamp` as `INTEGER` (Unix epoch). Don't use GRDB's `.datetime` column type (which stores ISO8601 strings). Use `.integer` and convert in Swift.

4. **UUID as TEXT.** Both Zig and Swift use `TEXT PRIMARY KEY` for IDs. Swift `UUID().uuidString` produces uppercase hex (e.g., `"A1B2C3D4-..."`). Zig generates lowercase. Decide on one convention (lowercase recommended for compat). Use `UUID().uuidString.lowercased()` or just pass through as-is since SQLite TEXT comparison is case-sensitive.

5. **Swift 6 strict concurrency.** `DatabasePool`/`DatabaseQueue` are `Sendable`. GRDB read/write closures are `@Sendable`. Ensure `ChatHistoryStore` is either `@MainActor` or an `actor` to satisfy Swift 6 concurrency checking. The v1 pattern of `DispatchQueue.global` won't compile under Swift 6 strict — use GRDB's built-in async methods instead.

---

## 8. Open Questions

1. **ChatSession model — new file or extend ChatModel?** Spec says `ChatModel` has `sessions: [ChatSession]` and `selectedSession`. The current `ChatModel` has zero session concept. Need to add `ChatSession` struct (new file) and extend `ChatModel` with session management.

2. **ChatMessage kind field.** Zig schema has `kind TEXT NOT NULL` (text/code/tool-call/etc per spec). Current Swift `ChatMessage` has no `kind`. Need to add an enum that maps to the string values. For MVP, at least `text` kind must work.

3. **GRDB addition strategy.** Adding via Xcode SPM UI creates `Package.resolved` and modifies pbxproj automatically. Alternatively, could use a local package. Recommend Xcode SPM for consistency with spec ("Swift deps via Xcode SPM").
