# Testing Strategy

## 15. Testing Strategy

### 15.1 Unit tests (swift test)

Run with `swift test` or `zig build unit-test`. No Xcode project needed.

**SmithersModelsTests:**
- FileItem lazy loading and tree mutation
- ChatMessage serialization/deserialization
- DiffModels parsing
- JJModels parsing
- Preference defaults and validation

**SmithersServicesTests:**
- JJService output parsing (mock `jj` output strings)
- CommitStyleDetector analysis
- SkillScanner discovery (mock filesystem)
- ChatHistoryStore round-trip serialization
- JSONRPCTransport message framing (mock pipes)
- SmithersCtlInterpreter command parsing

**SmithersEditorTests:**
- SupportedLanguages extension mapping
- BracketMatcher pair finding
- Fuzzy search scoring

### 15.2 Integration tests

Tests that require running services or UI frameworks. Still run via `swift test` but may need `@MainActor` isolation.

- CodexService: mock transport, verify event stream
- JJSnapshotStore: in-memory SQLite database
- SearchService: mock ripgrep output

### 15.3 UI tests (XCUITest)

Run with `zig build ui-test`. Requires the Xcode project and UI test target.

**Chat window tests:**
- Launch app, verify chat window appears
- Send a message, verify it appears in the message list
- Create new chat, verify session appears in sidebar
- Switch sidebar modes

**Workspace panel tests:**
- Open a directory, verify file tree populates
- Select a file, verify editor content
- Open command palette, search for file, open it
- Verify tab bar shows opened files

**Cross-window tests:**
- Click "Open Editor" in chat, verify workspace panel appears
- Verify AI file change opens workspace panel (if preference enabled)

**Screenshot capture:** Use `XCTAttachment` to capture screenshots for visual review. Extract from `.xcresult` via `xcrun xcresulttool`.

### 15.4 Playwright end-to-end tests (web app)

Playwright tests are a **primary reason** the web app exists. They exercise the full libsmithers Zig core end-to-end through the web UI, providing comprehensive integration coverage without requiring XCUITest or a macOS simulator.

**Run:** `zig build playwright` (starts HTTP server, runs Playwright, tears down).

**Test suites** in `web/tests/e2e/`:
- Chat: send message, receive streaming response, verify message rendering
- Slash commands, @mentions, steer mode
- File tree: open workspace, browse, open file in Monaco editor
- Editor: edit, save, verify persistence
- Terminal: xterm.js terminal, run command, verify output via PTY WebSocket
- Agents: spawn, monitor, verify completion
- JJ: VCS operations, snapshots, undo
- Skills: activation, skill-modified prompts

**Three layers of testing:**
1. **Zig unit tests** (`zig build test`) — fast, no external deps
2. **Playwright e2e** (`zig build playwright`) — full stack through web UI
3. **XCUITest** (`zig build ui-test`) — native macOS UI tests

The mock/replay infrastructure (section 15.5) is used by all three layers.

### 15.5 Mock / replay infrastructure

Since the app depends heavily on `codex-app-server`, tests need to work without a live AI backend:

- **MockCodexTransport** — Implements the same interface as `JSONRPCTransport` but reads from recorded session files. Records are JSON arrays of `{request, response, delay}` tuples.
- **Recording mode** — When `SMITHERS_RECORD_CODEX=1` environment variable is set, `JSONRPCTransport` writes all messages to a session file alongside normal operation.
- **Replay mode** — `MockCodexTransport` plays back recorded sessions with realistic timing (compressed by 10x for test speed). Used in both unit tests and XCUITests.
- **Stub mode** — For simple tests that don't need full conversations, `StubCodexService` returns canned responses for specific method calls.

### 15.5 Enterprise quality standards

This is production software built for enterprise use. Quality expectations:

- **Comprehensive error handling.** Every async operation has error handling with user-visible feedback. No silent failures. Errors are categorized (recoverable vs fatal) and presented appropriately (toast for transient, alert for blocking).
- **Structured logging.** Use `os_log` with subsystem `com.smithers` and categories per domain (e.g., `.codex`, `.jj`, `.editor`, `.terminal`). Log levels: `.debug` for internal state, `.info` for user actions, `.error` for failures, `.fault` for invariant violations. Logs are viewable via Console.app and captured in crash reports.
- **Crash reporting.** Integrate crash symbolication. Catch and report `fatalError` / `preconditionFailure` paths.
- **Performance monitoring.** Use `os_signpost` for key operations (file open, tree parse, message send, jj status refresh). Measure and track cold launch time, time-to-first-chat, syntax highlight latency.
- **Memory management.** Profile with Instruments regularly. No retain cycles in the model graph. Weak references for delegates and coordinators. Large content (file bodies, chat images) loaded lazily and released when tabs close.
- **Accessibility.** Every interactive element has an accessibility identifier, label, and role. VoiceOver must be able to navigate the full app. This is not optional — it's required for enterprise customers.

### 15.6 CI/CD (GitHub Actions)

**GitHub Actions** with macOS runners for the full build + test pipeline:

- **Zig tests:** `zig build test` — runs on every PR, fast
- **Swift tests:** `zig build xcode-test` — requires macOS runner
- **Playwright e2e:** `zig build playwright` — starts HTTP server, runs Playwright tests against real libsmithers
- **Native UI tests:** `zig build ui-test` — XCUITest on macOS runner
- **Web build:** `zig build web` — ensures web app compiles
- **Rust submodules:** Built as part of `zig build test` (Codex + JJ are linked in)

The full CI pipeline validates the entire polyglot monorepo: Zig, Rust (via cargo), Swift (via xcodebuild), and TypeScript/SolidJS (via pnpm + Playwright).
