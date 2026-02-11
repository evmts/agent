# Plan: chat-streaming-bridge

## Summary

Wire Swift chat composer to libsmithers C API and render streaming assistant deltas live. The Zig infrastructure is fully ready (codex_client stub, App routing, C API header). This ticket implements the Swift side: SmithersCore FFI bridge, ChatModel @Observable state, and ChatWindowRootView bindings.

## Current State

### Ready (No Changes Needed)
- `include/libsmithers.h` — Events `SMITHERS_EVENT_CHAT_DELTA=13`, `SMITHERS_EVENT_TURN_COMPLETE=14` defined
- `src/codex_client.zig` — Streaming stub emits 3 deltas ("Thinking… ", "Okay. ", "Done.") on background thread, tested
- `src/App.zig` — Routes `chat_send` → `codex.streamChat()`, calls `wakeup` callback
- `src/lib.zig` — C API exports tested (payload conversion for all 12 action variants)
- `src/config.zig` — `RuntimeConfig` with `ActionFn` + `WakeupFn` callback signatures
- `macos/Sources/Features/Chat/Views/ChatComposerZone.swift` — Return/Shift+Return handling correct, `onSend: (String) -> Void` fires with trimmed text
- Design tokens, theme, window chrome — all in place

### Needs Work (This Ticket)
- `macos/Sources/Ghostty/SmithersCore.swift` — Smoke test only → full FFI bridge
- `macos/Sources/App/AppModel.swift` — Missing `chatModel` and `core`
- `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` — 12 hardcoded mock bubbles, stubbed `onSend`
- `macos/Sources/App/SmithersApp.swift` — Calls `SmithersCoreBridge.smokeInitAndFree()` → needs removal

## Architecture Decisions

1. **SmithersCore owns smithers_app_t** — Single instance created by AppModel, held for app lifetime. Follows Ghostty Unmanaged callback pattern exactly.
2. **Callbacks dispatch to main thread** — Zig `codex_client.streamChat` calls action callback from background thread. Callback body uses `DispatchQueue.main.async` for @MainActor safety.
3. **ChatModel is @Observable @MainActor** — Messages array mutated on main thread only. SwiftUI fine-grained tracking: only views reading `messages` re-render on delta.
4. **No DispatchQueue in SmithersCore** — SmithersCore is `@MainActor`. The C callback closure (not @MainActor) dispatches to main. SmithersCore methods called from main thread only.
5. **String bridging: ptr+len, NOT NUL-terminated** — `smithers_string_s` uses `(ptr, len)`. Swift→Zig: `withCString` + `utf8.count`. Zig→Swift: `UnsafeBufferPointer(start:count:)`.

## Implementation Steps

### Step 0: Create ChatModel (new file)

**Files:** `macos/Sources/Features/Chat/Models/ChatModel.swift` (NEW)

Create `@Observable @MainActor final class ChatModel` with:
- `Message` struct: `id: UUID`, `role: Role` (.user/.assistant), `text: String`, `isStreaming: Bool`
- `messages: [Message]` — private(set)
- `isTurnInProgress: Bool` — private(set)
- `addUserMessage(_ text: String)` — appends user message
- `startAssistantMessage()` — appends empty streaming assistant message, sets isTurnInProgress
- `appendDelta(_ text: String)` — guards last message is streaming assistant, appends text
- `completeTurn()` — flips isStreaming false, sets isTurnInProgress false

This is a pure value-state class with no dependencies. Tests can be written immediately.

### Step 1: Write ChatModel unit tests (TDD)

**Files:** `macos/SmithersTests/ChatModelTests.swift` (NEW)

Test cases:
- `addUserMessage` appends message with `.user` role, isStreaming false
- `startAssistantMessage` appends empty `.assistant` message with isStreaming true, sets isTurnInProgress
- `appendDelta` accumulates text on streaming assistant message
- Multiple `appendDelta` calls concatenate correctly (validates ≥2 delta scenario)
- `completeTurn` sets isStreaming false and isTurnInProgress false
- `appendDelta` on non-streaming message is no-op (safety)
- `completeTurn` with no messages is safe (no crash)
- `appendDelta` with empty string is no-op or safe

### Step 2: Rewrite SmithersCore FFI bridge

**Files:** `macos/Sources/Ghostty/SmithersCore.swift` (MODIFY — full rewrite)

Replace `SmithersCoreBridge` enum with `SmithersCore` class:

```swift
@MainActor
final class SmithersCore {
    private let app: smithers_app_t
    var onChatDelta: ((String) -> Void)?
    var onTurnComplete: (() -> Void)?

    enum SmithersError: Error { case initFailed }

    init() throws { ... }  // Unmanaged pattern, install action callback
    func sendChat(_ message: String) { ... }  // smithers_app_action(CHAT_SEND)
    deinit { smithers_app_free(app) }
}
```

Key patterns (Ghostty reference):
- `Unmanaged.passUnretained(self).toOpaque()` as userdata
- Action callback: C closure extracts `SmithersCore` via `Unmanaged.fromOpaque().takeUnretainedValue()`
- `DispatchQueue.main.async` inside callback for thread safety
- Switch on tag: `SMITHERS_EVENT_CHAT_DELTA` → extract UTF-8 string from (data, len), call `onChatDelta`
- Switch on tag: `SMITHERS_EVENT_TURN_COMPLETE` → call `onTurnComplete`
- `sendChat`: `message.withCString` → build `smithers_string_s(ptr:len:)` → `smithers_app_action(app, SMITHERS_ACTION_CHAT_SEND, payload)`

### Step 3: Write SmithersCore callback integration test

**Files:** `macos/SmithersTests/SmithersTests.swift` (MODIFY — add test)

Add test that creates SmithersCore with real libsmithers, sends a chat message, and verifies:
- ≥2 `onChatDelta` callbacks received
- 1 `onTurnComplete` callback received
- Delta text is non-empty
- All callbacks arrive on main thread

Uses XCTest expectation with 2-second timeout (Zig stub takes ~30ms total).

### Step 4: Wire AppModel to SmithersCore + ChatModel

**Files:** `macos/Sources/App/AppModel.swift` (MODIFY)

Add to AppModel:
- `let chatModel = ChatModel()`
- `private(set) var core: SmithersCore?` (optional — init can fail)
- In `init()`: create `SmithersCore()`, wire callbacks:
  - `core.onChatDelta = { [weak self] text in self?.chatModel.appendDelta(text) }`
  - `core.onTurnComplete = { [weak self] in self?.chatModel.completeTurn() }`
- `func sendChatMessage(_ text: String)`:
  - `chatModel.addUserMessage(text)`
  - `chatModel.startAssistantMessage()`
  - `core?.sendChat(text)`

### Step 5: Update SmithersApp entry point

**Files:** `macos/Sources/App/SmithersApp.swift` (MODIFY)

- Remove `SmithersCoreBridge.smokeInitAndFree()` call from `init()`
- Remove `didValidateLink` guard (SmithersCore now created by AppModel, validated by tests)
- AppModel's init creates SmithersCore — no separate smoke check needed

### Step 6: Wire ChatWindowRootView to live data

**Files:** `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` (MODIFY)

Changes:
1. **MessagesZone** — replace hardcoded `ForEach(0..<12)` with `ForEach(appModel.chatModel.messages)`. Each message renders UserBubble or AssistantBubble based on `message.role`. Streaming indicator (ellipsis or cursor) shown when `message.isStreaming`.
2. **onSend closure** — replace `{ _ in /* stub */ }` with `{ text in appModel.sendChatMessage(text) }`
3. **MessagesZone** needs `@Environment(AppModel.self)` to read chatModel
4. **ScrollView auto-scroll** — `ScrollViewReader` + `.onChange(of: appModel.chatModel.messages.count)` scrolls to bottom on new message
5. **Empty state** — when messages is empty, show placeholder text (simple, not full welcome screen yet)
6. Keep UserBubble and AssistantBubble structs mostly unchanged (accept `text: String` parameter)

### Step 7: Add Xcode project references

**Files:** `macos/Smithers.xcodeproj/project.pbxproj` (MODIFY)

Add file references for:
- `macos/Sources/Features/Chat/Models/ChatModel.swift` → Smithers target
- `macos/SmithersTests/ChatModelTests.swift` → SmithersTests target

Create `Models` group under `Features/Chat/` group.

### Step 8: Verify green build

Run `zig build all` and `xcodebuild test` to verify:
- Zig tests still pass (no Zig changes, but verify)
- Swift tests pass (new ChatModel + SmithersCore callback tests)
- App builds and launches correctly
- No UI regressions (window chrome, tokens, sidebar intact)
- Streaming works end-to-end: type → Return → user bubble → streaming assistant bubble → finalized

## Dependency Order

```
Step 0 (ChatModel)
    ↓
Step 1 (ChatModel tests) ← TDD: tests written after model, run against it
    ↓
Step 2 (SmithersCore rewrite) ← depends on nothing new
    ↓
Step 3 (SmithersCore tests) ← depends on Step 2
    ↓
Step 4 (AppModel wiring) ← depends on Steps 0 + 2
    ↓
Step 5 (SmithersApp cleanup) ← depends on Step 4 (SmithersCoreBridge removed)
    ↓
Step 6 (ChatWindowRootView) ← depends on Step 4 (chatModel on AppModel)
    ↓
Step 7 (Xcode pbxproj) ← depends on Steps 0 + 1 (new files exist)
    ↓
Step 8 (verify green) ← depends on all above
```

Note: Steps 0-1 and 2-3 are independent pairs that could be done in parallel, but sequential is clearer and safer.

## Files Summary

### New Files
- `macos/Sources/Features/Chat/Models/ChatModel.swift` — @Observable chat state
- `macos/SmithersTests/ChatModelTests.swift` — ChatModel unit tests

### Modified Files
- `macos/Sources/Ghostty/SmithersCore.swift` — Full rewrite: FFI bridge with Unmanaged callbacks
- `macos/Sources/App/AppModel.swift` — Add chatModel + core + sendChatMessage
- `macos/Sources/App/SmithersApp.swift` — Remove smoke test call
- `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` — Live data binding
- `macos/Smithers.xcodeproj/project.pbxproj` — New file references

### Unchanged Files (verified ready)
- `include/libsmithers.h` — C API events defined
- `src/codex_client.zig` — Streaming stub with test
- `src/App.zig` — Routes chat_send to codex
- `src/lib.zig` — C API exports
- `macos/Sources/Features/Chat/Views/ChatComposerZone.swift` — Return key handling correct
- All design system tokens/theme files

## Risks

1. **Xcode pbxproj merge conflicts** — Adding files to pbxproj is fragile. Use `xcodebuild -list` to verify targets after editing. If pbxproj edit fails, fall back to opening Xcode and adding files via GUI.
2. **Thread safety of Unmanaged pattern** — The `Unmanaged.passUnretained(self)` reference is captured by the C callback closure. If SmithersCore is deallocated while Zig background thread is still running, this is a use-after-free. Mitigation: SmithersCore lives on AppModel (app lifetime), and the Zig stub completes in ~30ms. Production Codex will need proper cancellation on deinit.
3. **C enum bridging** — Swift imports `smithers_action_tag_e` values as global `Int32` constants, not a Swift enum. The switch statement must use `case SMITHERS_EVENT_CHAT_DELTA:` syntax (no dot prefix). Must test this compiles correctly.
4. **smithers_string_s pointer lifetime** — `withCString` provides a pointer valid only within the closure. Zig's `performAction` copies/uses the message synchronously before spawning the background thread, so this is safe for the stub. Document this assumption.
5. **ScrollView auto-scroll jank** — Rapid delta appends (~30ms apart) may cause scroll animation stacking. Use `scrollTo(id, anchor: .bottom)` without animation for streaming, with animation only for user-initiated scrolls.
