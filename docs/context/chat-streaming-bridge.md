# Research Context: chat-streaming-bridge

## Ticket Summary

Wire Swift chat composer to libsmithers C API and render streaming assistant deltas live.

## Current State

### Zig Side (READY — all infrastructure exists)

**`src/codex_client.zig`** — Streaming stub emits 3 fixed deltas ("Thinking… ", "Okay. ", "Done.") on background thread with 10ms spacing, then `event_turn_complete`. Has passing test validating ≥2 deltas + 1 complete.

**`src/App.zig:51-63`** — `performAction()` routes `chat_send` to `codex.streamChat(self.runtime, cs.message)`, then calls `runtime.wakeup`. All other actions fall through.

**`include/libsmithers.h:39-60`** — Event tags:
- `SMITHERS_EVENT_CHAT_DELTA = 13` — data=UTF-8 bytes, len=byte count
- `SMITHERS_EVENT_TURN_COMPLETE = 14` — data=NULL, len=0

**`src/config.zig:6-14`** — Callback signatures:
```zig
pub const WakeupFn = *const fn (userdata: ?*anyopaque) callconv(.c) void;
pub const ActionFn = *const fn (userdata: ?*anyopaque, tag: capi.smithers_action_tag_e, data: ?[*]const u8, len: usize) callconv(.c) void;
```

**`src/lib.zig:40-44`** — C export `smithers_app_action()` converts C payload → Zig payload → `app.performAction()`.

### Swift Side (NEEDS WORK)

**`macos/Sources/Ghostty/SmithersCore.swift`** — Currently a smoke test only (creates + frees app). Must become the real FFI bridge with Unmanaged callbacks.

**`macos/Sources/App/AppModel.swift`** — Minimal stub: `theme`, `workspaceName`, `windowCoordinator`. Must gain `chatModel` and `SmithersCore` instance.

**`macos/Sources/Features/Chat/Views/ChatWindowRootView.swift:19`** — Composer `onSend` is stubbed: `ChatComposerZone(onSend: { _ in /* stub */ })`. MessagesZone renders 12 hardcoded mock bubbles.

**`macos/Sources/Features/Chat/Views/ChatComposerZone.swift`** — Already handles Return/Shift+Return correctly via NSTextView subclass. `onSend: (String) -> Void` callback fires with trimmed text and clears input.

## Key Files to Modify

| File | What Changes |
|------|-------------|
| `macos/Sources/Ghostty/SmithersCore.swift` | Full rewrite: own `smithers_app_t`, install callbacks, Unmanaged pattern |
| `macos/Sources/App/AppModel.swift` | Add `chatModel: ChatModel`, `core: SmithersCore` |
| `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` | Bind MessagesZone to `chatModel.messages`, wire `onSend` |
| NEW: `macos/Sources/Features/Chat/Models/ChatModel.swift` | @Observable with messages array, appendDelta, completeTurn |
| `macos/SmithersTests/SmithersTests.swift` | Add C API + callback test |
| NEW: `macos/SmithersTests/ChatModelTests.swift` | Unit test ChatModel append/complete |

## Reference Patterns

### Ghostty Unmanaged Callback Pattern (FOLLOW THIS)

From `../smithers/ghostty/macos/Sources/Ghostty/Ghostty.App.swift`:

**Setup (lines 60-70):**
```swift
var runtime_cfg = ghostty_runtime_config_s(
    userdata: Unmanaged.passUnretained(self).toOpaque(),
    wakeup_cb: { userdata in App.wakeup(userdata) },
    action_cb: { app, target, action in App.action(app!, target: target, action: action) },
    // ...
)
```

**Recovery (lines 424-431):**
```swift
static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
    let state = Unmanaged<App>.fromOpaque(userdata!).takeUnretainedValue()
    DispatchQueue.main.async { state.appTick() }
}
```

**Key rules:**
- `passUnretained` (not `passRetained`) — Swift object lifetime managed by SwiftUI
- `takeUnretainedValue()` in callbacks — no ownership transfer
- `DispatchQueue.main.async` for UI updates from any-thread callbacks

### v1 Chat Streaming Pattern (REFERENCE)

From `prototype0/Smithers/CodexService.swift`:
- Delta events carry only the delta text, not accumulated
- Swift accumulates by mutating `ChatMessage.kind = .text(text + delta)`
- `isStreaming: Bool` flag on message, flipped false on turn complete
- Messages stored as `[ChatMessage]` in `@Published` array, mutated in-place

### SmithersKit C API (Swift sees these types via xcframework)

```c
// Types Swift imports from SmithersKit:
smithers_app_t              // opaque *
smithers_config_s           // { runtime: smithers_runtime_config_s }
smithers_runtime_config_s   // { wakeup, action, userdata }
smithers_action_tag_e       // enum: SMITHERS_ACTION_CHAT_SEND=0, ..., SMITHERS_EVENT_CHAT_DELTA=13, SMITHERS_EVENT_TURN_COMPLETE=14
smithers_action_payload_u   // union: .chat_send = smithers_string_s
smithers_string_s           // { ptr: *u8, len: size_t }

smithers_app_new(config)    // -> smithers_app_t?
smithers_app_free(app)      // void
smithers_app_action(app, tag, payload)  // void
```

## Implementation Design

### SmithersCore (FFI Bridge)

```swift
@MainActor
final class SmithersCore {
    private let app: smithers_app_t
    var onChatDelta: ((String) -> Void)?
    var onTurnComplete: (() -> Void)?

    init() throws {
        var cfg = smithers_config_s(runtime: smithers_runtime_config_s(
            wakeup: nil,
            action: { userdata, tag, data, len in
                let core = Unmanaged<SmithersCore>.fromOpaque(userdata!).takeUnretainedValue()
                // CRITICAL: callbacks come from background thread
                // Must dispatch to main for @MainActor safety
                let tagVal = tag
                switch tagVal {
                case SMITHERS_EVENT_CHAT_DELTA:
                    if let d = data, len > 0 {
                        let text = String(bytes: UnsafeBufferPointer(start: d.assumingMemoryBound(to: UInt8.self), count: len), encoding: .utf8) ?? ""
                        DispatchQueue.main.async { core.onChatDelta?(text) }
                    }
                case SMITHERS_EVENT_TURN_COMPLETE:
                    DispatchQueue.main.async { core.onTurnComplete?() }
                default: break
                }
            },
            userdata: Unmanaged.passUnretained(self).toOpaque()
        ))
        guard let h = smithers_app_new(&cfg) else { throw SmithersError.initFailed }
        self.app = h
    }

    func sendChat(_ message: String) {
        message.withCString { cStr in
            var payload = smithers_action_payload_u()
            payload.chat_send = smithers_string_s(ptr: UnsafeRawPointer(cStr)?.assumingMemoryBound(to: UInt8.self), len: message.utf8.count)
            smithers_app_action(app, SMITHERS_ACTION_CHAT_SEND, payload)
        }
    }

    deinit { smithers_app_free(app) }
}
```

### ChatModel (@Observable)

```swift
@Observable @MainActor
final class ChatModel {
    struct Message: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
        var isStreaming: Bool
        enum Role { case user, assistant }
    }

    private(set) var messages: [Message] = []
    private(set) var isTurnInProgress: Bool = false

    func addUserMessage(_ text: String) {
        messages.append(Message(role: .user, text: text, isStreaming: false))
    }

    func startAssistantMessage() {
        messages.append(Message(role: .assistant, text: "", isStreaming: true))
        isTurnInProgress = true
    }

    func appendDelta(_ text: String) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant,
              messages[lastIndex].isStreaming else { return }
        messages[lastIndex].text += text
    }

    func completeTurn() {
        guard let lastIndex = messages.indices.last else { return }
        messages[lastIndex].isStreaming = false
        isTurnInProgress = false
    }
}
```

## Gotchas / Pitfalls

### 1. Thread Safety — callbacks from Zig background thread
The Zig `codex_client.streamChat` spawns `std.Thread.spawn` and calls the action callback from that thread. Swift's `@MainActor` isolation means ALL UI state mutations must happen on main thread. The callback closure MUST use `DispatchQueue.main.async` (Ghostty pattern).

### 2. String lifetime in withCString
When calling `smithers_app_action`, the `smithers_string_s.ptr` points to memory owned by the `withCString` closure. The Zig side copies/uses the data synchronously in `performAction` before spawning the background thread, so this is safe. But if Zig ever stores the pointer for later use, this would be a use-after-free.

### 3. Unmanaged self-reference before init completes
`Unmanaged.passUnretained(self).toOpaque()` in the `smithers_config_s` must reference `self` — but `self.app` hasn't been set yet. The config struct is constructed before `smithers_app_new` is called, so the userdata is set correctly. The app handle is stored after init returns. This is fine because callbacks won't fire until `smithers_app_action` is called.

### 4. smithers_action_tag_e Swift enum bridging
In Swift, the C enum `smithers_action_tag_e` values are imported as global constants (e.g., `SMITHERS_EVENT_CHAT_DELTA`), NOT as a Swift enum. Switch on the raw value: `switch tag { case SMITHERS_EVENT_CHAT_DELTA: ... }`.

### 5. UnsafeRawPointer → UInt8 pointer cast for string data
The callback's `data` parameter is `const void*` (Swift: `UnsafeRawPointer?`). To create a String: `String(bytes: UnsafeBufferPointer(start: data!.assumingMemoryBound(to: UInt8.self), count: len), encoding: .utf8)`. Or use `String(cString:)` if NUL-terminated, but libsmithers uses ptr+len (NOT NUL-terminated).

## Xcode Project Impact

New files must be added to `macos/Smithers.xcodeproj/project.pbxproj`:
- `macos/Sources/Features/Chat/Models/ChatModel.swift` → Smithers target + SmithersTests target
- `macos/SmithersTests/ChatModelTests.swift` → SmithersTests target

The pbxproj must be updated with new file references, build file entries, and group entries. Use the existing file patterns in the project as reference.

## Test Plan

### Zig Tests (already passing)
- `codex_client.zig` test: validates ≥2 deltas + 1 complete within 500ms timeout

### Swift Unit Tests (NEW)
1. **SmithersTests** — `smithers_app_action` with callback: create app with action callback, send `SMITHERS_ACTION_CHAT_SEND`, assert ≥2 delta callbacks + 1 complete within 500ms
2. **ChatModelTests** — `appendDelta` accumulates text; `completeTurn` flips `isStreaming`; empty delta is no-op; complete without streaming message is safe

### Manual Verification
- Launch app → type message → press Return → see streaming bubbles appear
- Window chrome, design tokens, sidebar all intact
- `zig build all` green
- `xcodebuild test` green
