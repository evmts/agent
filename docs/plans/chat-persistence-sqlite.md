# Plan: chat-persistence-sqlite

## Ticket
Add chat persistence (SQLite via GRDB) and wire to ChatModel.

## Summary
Implement `ChatHistoryStore` in Swift using GRDB that mirrors Zig's sessions/messages schema (`src/storage.zig` `ensureSchema`). Persist all chat sessions and messages, enable WAL, and provide 1s debounced writes. On app launch, load recent sessions + messages into ChatModel. Maintain strict parity with Zig schema (UUID text keys, `thread_id` nullable, `metadata_json` nullable) per spec-index (Storage canonical).

## Acceptance Criteria
- GRDB opens same path as Zig (`~/Library/Application Support/Smithers/smithers.db`) with WAL enabled
- Unit tests prove create/load/update/delete for sessions and messages
- App shows last session on launch; sending a message persists immediately (debounced <= 1s)
- `zig build all` passes; xcode unit tests pass locally (no change to zig test set)

---

## Architecture Decisions

### Schema Parity
The Zig schema in `src/storage.zig` lines 321-342 is canonical. The GRDB migration MUST produce identical tables:
- `sessions`: id TEXT PK, thread_id TEXT, title TEXT, workspace_path TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
- `messages`: id TEXT PK, session_id TEXT NOT NULL FK→sessions(id) ON DELETE CASCADE, turn_id TEXT, role TEXT NOT NULL, kind TEXT NOT NULL, content TEXT NOT NULL, metadata_json TEXT, timestamp INTEGER NOT NULL
- Indexes: idx_messages_session, idx_messages_timestamp, idx_sessions_workspace

### DatabasePool vs DatabaseQueue
Use `DatabasePool` for production (concurrent reads, WAL mode). Use `DatabaseQueue()` (in-memory, no path) for unit tests. Both conform to `DatabaseWriter` — inject protocol for testability.

### Concurrency Strategy
`ChatHistoryStore` will NOT be `@MainActor`. It will be a plain `final class` holding a `Sendable` `DatabasePool`/`DatabaseQueue`. GRDB read/write methods are thread-safe. The store exposes `nonisolated` synchronous methods that GRDB dispatches internally. This avoids Swift 6 concurrency issues. ChatModel (which IS `@MainActor`) calls store methods from async tasks.

### UUID Convention
Use `UUID().uuidString` (uppercase) for new IDs. SQLite TEXT comparison is case-sensitive, but since both Zig and Swift only ever query by exact match of IDs they themselves produced, case doesn't matter — each side is self-consistent.

### Timestamps
All timestamps stored as `Int64` Unix epoch seconds. `Int64(Date().timeIntervalSince1970)` for current time. Never use GRDB `.datetime` column type.

### Debounced Writes
1s debounce via cancellable `Task` on `ChatModel`. After debounce fires, captures current state snapshot and writes on background (GRDB handles thread dispatch). Immediate persist on explicit actions (new session, delete).

---

## Implementation Steps

### Step 0: Add GRDB SPM dependency to Xcode project
**Files:** `macos/Smithers.xcodeproj/project.pbxproj`

Add GRDB.swift as an SPM dependency. This is the first SPM package in the project. Add `XCRemoteSwiftPackageReference` for `https://github.com/groue/GRDB.swift` (up-to-next-major from 7.0.0). Add `XCSwiftPackageProductDependency` for both Smithers and SmithersTests targets. GRDB 7.x supports Swift 6 strict concurrency.

**Note:** This step is best done via Xcode UI (File > Add Package Dependencies) since manual pbxproj SPM edits are complex. If done manually, must add: XCRemoteSwiftPackageReference, XCSwiftPackageProductDependency entries for both targets, and framework build file entries.

### Step 1: Create ChatSession model
**Files:** `macos/Sources/Features/Chat/Models/ChatSession.swift` (CREATE)

New `ChatSession` struct: `Identifiable`, `Equatable`, `Codable`, GRDB `FetchableRecord`, `MutablePersistableRecord`. Properties mirror sessions table exactly:
- `id: String` (UUID text)
- `threadId: String?`
- `title: String?`
- `workspacePath: String?`
- `createdAt: Int64` (unix timestamp)
- `updatedAt: Int64` (unix timestamp)

`CodingKeys` enum maps camelCase → snake_case column names. `databaseTableName = "sessions"`. Factory method `static func new(title:workspacePath:) -> ChatSession` generates UUID + current timestamp.

### Step 2: Extend ChatMessage with persistence fields
**Files:** `macos/Sources/Features/Chat/Models/ChatMessage.swift` (MODIFY)

Add fields required by messages table:
- `sessionId: String` — FK to sessions
- `turnId: String?` — groups messages in a single LLM turn
- `kind: Kind` — new enum `Kind: String` with cases `text`, `command`, `diff`, `status` (at minimum `text` for MVP)
- `metadataJson: String?` — arbitrary JSON metadata
- `timestamp: Int64` — unix epoch

Keep existing `isStreaming: Bool` (runtime-only, not persisted). Change `id` from `UUID` to `String` (stored as TEXT in SQLite). Add conformances: `Codable`, `FetchableRecord`, `MutablePersistableRecord`. Add `CodingKeys` for snake_case mapping. Set `databaseTableName = "messages"`.

Update `init` to accept new fields with sensible defaults: `sessionId` required, `kind` defaults to `.text`, `timestamp` defaults to current time, `turnId`/`metadataJson` default nil.

### Step 3: Create ChatHistoryStore (TDD — write tests first)
**Files:** `macos/SmithersTests/ChatHistoryStoreTests.swift` (CREATE)

Write comprehensive tests BEFORE implementation using in-memory `DatabaseQueue()`:
1. `createAndLoadSession` — create session, load by ID, verify all fields
2. `createAndLoadMessages` — create session + messages, load messages by session ID, verify order
3. `updateSessionTitle` — create, update title, verify updated_at changes
4. `deleteSession_cascadesMessages` — delete session, verify messages deleted
5. `loadRecentSessions` — create multiple, load sorted by updated_at DESC, verify order
6. `walModeEnabled` — verify journal_mode=WAL on real file DB (use temp dir)
7. `foreignKeyEnforced` — insert message with bad session_id, expect failure
8. `loadMessagesForSession_empty` — session with no messages returns empty array
9. `saveMultipleMessages_orderPreserved` — insert 5 messages, verify timestamp order
10. `sessionWithWorkspacePath_filterable` — create sessions with different workspace paths, filter

All tests use Swift Testing framework (`@Suite`, `@Test`, `#expect`).

### Step 4: Implement ChatHistoryStore
**Files:** `macos/Sources/Features/Chat/Models/ChatHistoryStore.swift` (CREATE)

`final class ChatHistoryStore: Sendable` (NOT @MainActor). Holds `let dbWriter: any DatabaseWriter`.

**init(dbWriter:)** — accepts injected `DatabaseWriter` (DatabasePool for prod, DatabaseQueue for tests). Runs migrations synchronously on init.

**Migration** via `DatabaseMigrator`:
```
registerMigration("v1_sessions_messages") { db in
    // Exact schema parity with src/storage.zig ensureSchema()
    // sessions table, messages table, 3 indexes
}
```

**CRUD methods** (all synchronous, GRDB handles threading):
- `func saveSession(_ session: ChatSession) throws`
- `func loadSession(id: String) throws -> ChatSession?`
- `func loadRecentSessions(limit: Int) throws -> [ChatSession]`
- `func loadSessionsForWorkspace(_ path: String) throws -> [ChatSession]`
- `func updateSession(_ session: ChatSession) throws`
- `func deleteSession(id: String) throws`
- `func saveMessage(_ message: ChatMessage) throws`
- `func saveMessages(_ messages: [ChatMessage]) throws`
- `func loadMessages(sessionId: String) throws -> [ChatMessage]`
- `func deleteMessage(id: String) throws`

**Static factory** for production:
```swift
static func openDefault() throws -> ChatHistoryStore
```
Creates `~/Library/Application Support/Smithers/` dir if needed, opens `DatabasePool` at `smithers.db` path. Configures: `foreignKeysEnabled = true`, `prepareDatabase` sets `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;`.

### Step 5: Extend ChatModel with session management and persistence hooks
**Files:** `macos/Sources/Features/Chat/Models/ChatModel.swift` (MODIFY)

Add properties:
- `var sessions: [ChatSession] = []`
- `var selectedSession: ChatSession?`
- `private var store: ChatHistoryStore?`
- `private var persistTask: Task<Void, Never>?`

Add methods:
- `func configure(store: ChatHistoryStore)` — sets store, loads recent sessions, selects most recent (or creates new)
- `func createNewSession(title: String?, workspacePath: String?) -> ChatSession` — creates, saves immediately, selects
- `func selectSession(_ session: ChatSession)` — loads messages for session, sets selectedSession + messages
- `func deleteSession(_ session: ChatSession)` — removes from sessions array, deletes from store
- `private func schedulePersist()` — 1s debounce via cancellable Task, then flush
- `private func flushPendingWrites()` — captures messages snapshot, saves to store

Update existing methods:
- `appendUserMessage` — now requires selectedSession (creates one if nil), adds sessionId + timestamp, calls schedulePersist()
- `appendDelta` — calls schedulePersist() after mutation
- `completeTurn` — calls schedulePersist() after marking not streaming

### Step 6: Wire ChatHistoryStore into AppModel
**Files:** `macos/Sources/App/AppModel.swift` (MODIFY)

Add `private(set) var chatHistoryStore: ChatHistoryStore?` property.

In `init()`:
1. Try to open ChatHistoryStore via `ChatHistoryStore.openDefault()`
2. If successful, call `chat.configure(store: store)`
3. If fails, log error, continue without persistence (graceful degradation)

Update `sendChatMessage`:
- Ensure selectedSession exists (create if nil)
- Persist happens via ChatModel's internal debounce

### Step 7: Update Xcode project file with new file references
**Files:** `macos/Smithers.xcodeproj/project.pbxproj` (MODIFY)

Add PBXFileReference + PBXBuildFile entries for:
- `ChatSession.swift` — in app Sources build phase + Chat/Models group
- `ChatHistoryStore.swift` — in app Sources build phase + Chat/Models group
- `ChatHistoryStoreTests.swift` — in test Sources build phase + Tests group

Add Models group under Chat group (currently only Views exists in pbxproj).

### Step 8: Update existing ChatModel tests
**Files:** `macos/SmithersTests/ChatModelTests.swift` (MODIFY)

Existing tests create ChatModel() with no persistence. They should still pass — ChatModel works without a store (graceful degradation). Add new tests:
- `appendUserMessage_setsSessionId` — verify messages get sessionId
- `createNewSession_appearsInSessions` — verify sessions array
- `selectSession_loadsMessages` — verify session switching works
- `completeTurn_triggersPersist` — verify debounce scheduled (may need test helper)

### Step 9: Run `zig build all` + xcode tests to verify green
**Files:** (none — verification only)

Run `zig build all` — must pass (no Zig changes in this ticket).
Run `xcodebuild test` — all Swift tests must pass including new ChatHistoryStoreTests.
Verify no regressions in existing ChatModelTests, SmithersCoreTests, etc.

---

## Files to Create
1. `macos/Sources/Features/Chat/Models/ChatSession.swift`
2. `macos/Sources/Features/Chat/Models/ChatHistoryStore.swift`
3. `macos/SmithersTests/ChatHistoryStoreTests.swift`

## Files to Modify
1. `macos/Sources/Features/Chat/Models/ChatMessage.swift` — add persistence fields, GRDB conformances
2. `macos/Sources/Features/Chat/Models/ChatModel.swift` — add sessions, selectedSession, persistence hooks, debounce
3. `macos/Sources/App/AppModel.swift` — init store, wire to ChatModel
4. `macos/Smithers.xcodeproj/project.pbxproj` — GRDB SPM dep + new file refs
5. `macos/SmithersTests/ChatModelTests.swift` — add session-aware tests

## Tests
1. **ChatHistoryStoreTests** (unit, ~10 tests) — CRUD roundtrips, WAL, FK enforcement, cascading delete, workspace filtering
2. **ChatModelTests additions** (unit, ~4 tests) — session management, persistence hooks
3. **Zig tests** — no changes, `zig build all` verifies no regression

## Risks
1. **GRDB SPM addition** — First SPM dependency. Manual pbxproj editing is fragile; Xcode UI is safer but not automatable. May need iteration.
2. **Swift 6 concurrency** — ChatHistoryStore must be `Sendable`. GRDB 7.x DatabasePool/DatabaseQueue are Sendable. Store methods called from `@MainActor` ChatModel via Tasks need careful isolation.
3. **ChatMessage.id type change** — Changing from `UUID` to `String` breaks existing code that references `.id` as UUID. Views using `ForEach` with `.id` should still work (String is Hashable). SmithersCore callbacks may need adjustment.
4. **Backward compat** — Existing ChatModel tests create ChatModel() with no store. Must continue working (nil store = no persistence, no crash).
5. **Schema drift** — If Zig storage.zig schema changes, GRDB migration must be updated in lockstep. Currently v1 both sides.
6. **Database file contention** — Both Zig (via libsmithers C API) and Swift (via GRDB) may access same `smithers.db`. WAL mode handles concurrent reads. Writes are serialized by SQLite. But both sides creating tables on open could conflict if run simultaneously — current init order (SmithersCore then ChatHistoryStore) should be safe since Zig opens first.
