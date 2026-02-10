# Testing Strategy

## 15. Testing Strategy

### 15.1 Unit Tests (swift test)

Zig: `zig build test`. Swift: `swift test` (if SwiftPM targets exist) or `xcodebuild test` (Xcode project).

**SmithersModelsTests:** FileItem lazy loading+tree mutation; ChatMessage serialization; DiffModels/JJModels parsing; Preference defaults+validation

**SmithersServicesTests:** JJService output parsing (mock strings); CommitStyleDetector; SkillScanner (mock fs); ChatHistoryStore round-trip; JSONRPCTransport framing (for JSON-RPC providers); SmithersCtlInterpreter parsing

**SmithersEditorTests:** SupportedLanguages ext mapping; BracketMatcher; fuzzy search scoring

### 15.2 Integration Tests

Require running services/UI frameworks. Still `swift test`, may need `@MainActor`.

CodexService (mock transport, verify events); JJSnapshotStore (in-mem SQLite); SearchService (mock ripgrep)

### 15.3 UI Tests (XCUITest)

`zig build ui-test` (once wired) or `xcodebuild test` with UI test scheme. Requires Xcode project+UI test target.

**Chat:** Launch → verify window; send msg → verify in list; new chat → verify in sidebar; switch modes
**Workspace:** Open dir → verify tree; select file → verify editor; cmd palette → search/open; verify tab bar
**Cross-window:** Click "Open Editor" → verify panel; AI file change → opens panel (if pref enabled)
**Screenshots:** `XCTAttachment` for visual review. Extract from `.xcresult` via `xcrun xcresulttool`.

### 15.4 Playwright E2E (Web App)

**Primary reason web app exists** — exercises full libsmithers Zig core e2e via web UI. Comprehensive integration without XCUITest/macOS sim.

**Run (once wired):** `zig build playwright` (start HTTP server → run tests → teardown)

**Suites** (`web/tests/e2e/`):
Chat (send, stream, render); slash cmds, @mentions, steer; file tree (open workspace, browse, Monaco); editor (edit, save, persist); terminal (xterm.js, run cmd, PTY WS); agents (spawn, monitor, complete); JJ (ops, snapshots, undo); skills (activate, modified prompts)

**Three layers:**
1. Zig unit (`zig build test`) — fast, no deps
2. Playwright e2e (`zig build playwright` once wired) — full stack via web
3. XCUITest (`zig build ui-test` once wired) — native macOS UI

Mock/replay (§15.5) used by all three.

### 15.5 Mock/Replay Infrastructure

App depends on `codex-app-server`, tests work without live AI:

- **MockJSONRPCTransport** — Same interface as `JSONRPCTransport`, reads recorded sessions for JSON-RPC providers. Records = JSON `{request, response, delay}` arrays.
- **Recording** — `SMITHERS_RECORD_PROVIDER=1` env → `JSONRPCTransport` writes session file during normal op.
- **Replay** — `MockJSONRPCTransport` plays back w/ realistic timing (10x compressed). Used in unit+XCUITests.
- **Stub** — For in-process Codex, use `StubCodexService` or libsmithers event fixtures.

### 15.6 Enterprise Quality Standards

Production software for enterprise:

- **Error handling:** Every async op has handling w/ user feedback. No silent fails. Categorize (recoverable/fatal), present appropriately (toast transient, alert blocking).
- **Logging:** `os_log`, subsystem `com.smithers`, categories per domain (`.codex`, `.jj`, `.editor`, `.terminal`). Levels: `.debug` internal, `.info` user actions, `.error` fails, `.fault` invariant violations. Viewable via Console.app, captured in crash reports.
- **Crash reporting:** Integrate symbolication. Catch/report `fatalError`/`preconditionFailure`.
- **Performance:** `os_signpost` for key ops (file open, tree parse, msg send, jj refresh). Track cold launch, time-to-first-chat, syntax highlight latency.
- **Memory:** Profile w/ Instruments. No retain cycles in model graph. Weak refs for delegates/coordinators. Large content (file bodies, images) lazy loaded, released on tab close.
- **Accessibility:** Every element has identifier, label, role. VoiceOver navigates full app. NOT optional — enterprise requirement.

### 15.7 CI/CD (GitHub Actions)

macOS runners, full pipeline:

- **Zig:** `zig build test` — every PR, fast
- **Swift:** `zig build xcode-test` (once wired) or `xcodebuild test` — macOS runner
- **Playwright e2e:** `zig build playwright` (once wired) — HTTP server + real libsmithers
- **Native UI:** `zig build ui-test` (once wired) — XCUITest, macOS runner
- **Web build:** `zig build web` (once wired) — compile check
- **Rust submodules:** Built in `zig build test` (Codex+JJ linked)

Validates polyglot monorepo: Zig, Rust (cargo), Swift (xcodebuild), TypeScript/SolidJS (pnpm+Playwright).
