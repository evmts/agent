# Research Context: swift-chat-stream-bridge

## Ticket Summary

Wire chat send/stream to libsmithers C API: ChatComposerZone dispatches `SMITHERS_ACTION_CHAT_SEND`, receives streamed deltas via `SMITHERS_EVENT_CHAT_DELTA` + `SMITHERS_EVENT_TURN_COMPLETE`. Create managed `SmithersCore` (replacing `SmithersCoreBridge` enum), create `ChatModel`, replace hardcoded messages with model-driven rendering, show "Thinking..." bubble during streaming.

---

## 1. Current State Analysis

### Zig Side — READY

The Zig C API already handles chat_send end-to-end:

**`src/App.zig:51-63`** — `performAction` routes `.chat_send` to `codex.streamChat()` and calls wakeup:
```zig
pub fn performAction(self: *App, payload: action.Payload) void {
    switch (payload) {
        .chat_send => |cs| {
            codex.streamChat(self.runtime, cs.message);
        },
        else => {},
    }
    if (self.runtime.wakeup) |cb| cb(self.runtime.userdata);
}
```

**`src/codex_client.zig:6-25`** — Spawns background thread, emits 3 deltas ("Thinking... ", "Okay. ", "Done.") then turn_complete:
```zig
pub fn streamChat(runtime: configpkg.RuntimeConfig, message: []const u8) void {
    const Spawn = struct {
        fn run(rt: configpkg.RuntimeConfig) void {
            const chunks = [_][]const u8{ "Thinking\xe2\x80\xa6 ", "Okay. ", "Done." };
            if (rt.action) |cb| {
                for (chunks) |ch| {
                    cb(rt.userdata, .event_chat_delta, ch.ptr, ch.len);
                    std.posix.nanosleep(0, 10 * std.time.ns_per_ms);
                }
                cb(rt.userdata, .event_turn_complete, null, 0);
            }
        }
    };
    const th = std.Thread.spawn(.{}, Spawn.run, .{runtime}) catch return;
    th.detach();
}
```

**Key: Callbacks fire from a background thread.** Swift handler MUST dispatch to MainActor.

### Swift Side — STUBS ONLY

**`macos/Sources/Ghostty/SmithersCore.swift`** — Minimal bridge enum, no lifecycle management:
```swift
enum SmithersCoreBridge {
    static func smokeInitAndFree() {
        var cfg = smithers_config_s(runtime: smithers_runtime_config_s(wakeup: nil, action: nil, userdata: nil))
        if let h = smithers_app_new(&cfg) { smithers_app_free(h) }
    }
}
```

**`macos/Sources/App/AppModel.swift`** — Minimal, no chat state:
```swift
@Observable @MainActor
final class AppModel {
    var theme: AppTheme = .dark
    var workspaceName: String = "Smithers"
    let windowCoordinator = WindowCoordinator()
}
```

**`macos/Sources/Features/Chat/Views/ChatWindowRootView.swift:19`** — Composer onSend is a stub:
```swift
ChatComposerZone(onSend: { _ in /* stub */ })
```

**`ChatWindowRootView.swift:27-50`** — MessagesZone uses hardcoded ForEach(0..<12):
```swift
LazyVStack(spacing: DS.Space._10) {
    ForEach(0..<12, id: \.self) { i in
        HStack {
            if i % 2 == 0 { UserBubble(text: "User message #\(i)") }
            else { AssistantBubble(text: "Assistant message #\(i)") }
        }
    }
}
```

---

## 2. Key Reference Patterns

### Ghostty Unmanaged/Callback Pattern (MUST FOLLOW)

**Registration** (`ghostty/macos/Sources/Ghostty/Ghostty.App.swift:60-70`):
```swift
var runtime_cfg = ghostty_runtime_config_s(
    userdata: Unmanaged.passUnretained(self).toOpaque(),
    wakeup_cb: { userdata in App.wakeup(userdata) },
    action_cb: { app, target, action in App.action(app!, target: target, action: action) },
    // ...
)
guard let app = ghostty_app_new(&runtime_cfg, config.config) else { ... }
```

**Callback unwrapping + main thread dispatch** (`Ghostty.App.swift:424-431`):
```swift
static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
    let state = Unmanaged<App>.fromOpaque(userdata!).takeUnretainedValue()
    DispatchQueue.main.async { state.appTick() }
}
```

**Key points:**
- `Unmanaged.passUnretained(self).toOpaque()` — no retain count change
- Static methods as callbacks (C function pointers can't capture context)
- `fromOpaque(userdata!).takeUnretainedValue()` to recover Swift instance
- `DispatchQueue.main.async {}` for thread safety on UI updates

### V1 Chat Streaming Pattern

**`prototype0/Smithers/WorkspaceState.swift:5518-5528`** — Find-or-create, mutate, reassign:
```swift
private func applyAgentMessageDelta(turnId: String, delta: String) {
    if let index = chatMessages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
        var message = chatMessages[index]
        message.appendText(delta)
        chatMessages[index] = message
    } else {
        let message = ChatMessage(role: .assistant, kind: .text(delta), isStreaming: true)
        chatMessages.append(message)
    }
}
```

**V1 ChatMessage** — Mutating struct with append method:
```swift
struct ChatMessage: Identifiable, Hashable {
    var kind: Kind
    var isStreaming: Bool
    mutating func appendText(_ delta: String) {
        guard case .text(let text) = kind else { return }
        kind = .text(text + delta)
    }
}
```

---

## 3. C API Contract (include/libsmithers.h)

Relevant types for this ticket:

```c
typedef struct smithers_app_s* smithers_app_t;

typedef struct { const uint8_t* ptr; size_t len; } smithers_string_s;

typedef enum {
    SMITHERS_ACTION_CHAT_SEND = 0,
    // ...
    SMITHERS_EVENT_CHAT_DELTA = 13,
    SMITHERS_EVENT_TURN_COMPLETE = 14,
} smithers_action_tag_e;

typedef void (*smithers_wakeup_cb)(void* userdata);
typedef void (*smithers_action_cb)(void* userdata, smithers_action_tag_e tag,
                                   const void* data, size_t len);

typedef struct {
    smithers_wakeup_cb wakeup;
    smithers_action_cb action;
    void* userdata;
} smithers_runtime_config_s;

typedef struct { smithers_runtime_config_s runtime; } smithers_config_s;

typedef union {
    struct { smithers_string_s message; } chat_send;
    // ... other payloads
} smithers_action_payload_u;

smithers_app_t smithers_app_new(const smithers_config_s* config);
void smithers_app_free(smithers_app_t app);
void smithers_app_action(smithers_app_t app, smithers_action_tag_e tag,
                         smithers_action_payload_u payload);
```

---

## 4. Xcode Project Structure

### Targets in pbxproj:
1. **Smithers** — app target, links SmithersKit.xcframework
2. **SmithersTests** — hosted unit test bundle (runs inside app process)
3. **SmithersUITests** — directory EXISTS at `macos/SmithersUITests/WindowFlowTests.swift` but **NOT registered in pbxproj** — must be added to Xcode project for UI tests to run

### SmithersKit Module:
- Exposed via `dist/SmithersKit.xcframework/macos-arm64_x86_64/Headers/module.modulemap`
- Umbrella header: `libsmithers.h`
- Swift imports: `import SmithersKit`
- No bridging header needed

### Test framework:
- Unit tests use **Swift Testing** (`@Suite`, `@Test`, `#expect`) — see SmithersTests.swift
- Some tests use **XCTest** (`XCTestCase`) — see ChatViewTests.swift
- Both patterns coexist in SmithersTests target

### Accessibility identifiers already in place:
- `"messages_scroll"` — ScrollView in MessagesZone
- `"bubble_user"` — UserBubble
- `"bubble_assistant"` — AssistantBubble
- `"composer_text"` — KeyHandlingTextView
- `"composer_send"` — Send button
- `"open_editor"` — Open Editor button in title bar
- `"ide_window_root"` — IDE window root

---

## 5. Implementation Plan

### New Files to Create:
1. **`macos/Sources/Ghostty/SmithersCore.swift`** — REPLACE existing SmithersCoreBridge with managed SmithersCore class
2. **`macos/Sources/Features/Chat/Models/ChatMessage.swift`** — Message model struct
3. **`macos/Sources/Features/Chat/Models/ChatModel.swift`** — @Observable chat state

### Files to Modify:
1. **`macos/Sources/App/AppModel.swift`** — Add `SmithersCore` instance + `ChatModel`
2. **`macos/Sources/Features/Chat/Views/ChatWindowRootView.swift`** — Wire onSend, replace hardcoded messages with ChatModel, add ThinkingBubble
3. **`macos/Sources/App/SmithersApp.swift`** — Remove `SmithersCoreBridge.smokeInitAndFree()`, init SmithersCore via AppModel
4. **`macos/SmithersTests/SmithersCoreTests.swift`** — NEW: callback sequencing test
5. **`macos/SmithersUITests/ChatFlowTests.swift`** — NEW: UI test for send→assistant bubble

### SmithersCore Design (following Ghostty pattern):

```swift
@MainActor
final class SmithersCore {
    private let app: smithers_app_t

    init() throws {
        var cfg = smithers_config_s(
            runtime: smithers_runtime_config_s(
                wakeup: { userdata in
                    let core = Unmanaged<SmithersCore>.fromOpaque(userdata!).takeUnretainedValue()
                    DispatchQueue.main.async { core.handleWakeup() }
                },
                action: { userdata, tag, data, len in
                    // CRITICAL: this fires from Zig background thread
                    let core = Unmanaged<SmithersCore>.fromOpaque(userdata!).takeUnretainedValue()
                    // Copy data before dispatching to main
                    let text: String? = if let data, len > 0 {
                        String(bytes: UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: len), encoding: .utf8)
                    } else { nil }
                    DispatchQueue.main.async { core.handleAction(tag, text: text) }
                },
                userdata: Unmanaged.passUnretained(self).toOpaque()  // AFTER self is fully init'd
            )
        )
        // PROBLEM: Can't use self in config before init completes
        // Solution: two-phase init — create app with nil callbacks, then update
    }
}
```

**GOTCHA: Self-referential init.** Can't pass `Unmanaged.passUnretained(self)` in the initializer before `self` is fully initialized. Solutions:
1. Two-phase: create with nil callbacks, then update (if C API supports)
2. Use a separate `Holder` class that's allocated first
3. Use `nonisolated(unsafe)` static storage + set after init
4. **Recommended: Store SmithersCore in a property wrapper that delays callback registration**

Looking at Ghostty: they solve this by having `App` as a class where the C API init happens in a method called AFTER the Swift object exists. The `ghostty_app_new` is called inside `init()` but after assigning all stored properties.

### ChatModel Design:

```swift
@Observable @MainActor
final class ChatModel {
    var messages: [ChatMessage] = []
    var isStreaming: Bool = false

    func appendUserMessage(_ text: String) {
        messages.append(ChatMessage(id: UUID(), role: .user, text: text))
    }

    func appendDelta(_ text: String) {
        if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[index].text += text
        } else {
            messages.append(ChatMessage(id: UUID(), role: .assistant, text: text, isStreaming: true))
            isStreaming = true
        }
    }

    func completeTurn() {
        if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[index].isStreaming = false
        }
        isStreaming = false
    }
}
```

### ChatMessage Design:

```swift
struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var text: String
    var isStreaming: Bool = false

    enum Role { case user, assistant }
}
```

---

## 6. Critical Gotchas

### 1. Thread Safety — Zig callbacks fire from background thread
The `action_cb` in codex_client.zig fires from a `std.Thread.spawn` background thread. Swift MUST:
- Copy any data pointer content BEFORE dispatching to main (pointer may be invalidated)
- Use `DispatchQueue.main.async` to marshal to MainActor
- The `smithers_string_s` data pointer is stack-allocated in Zig and only valid during the callback

### 2. Self-referential init — Unmanaged.passUnretained(self) before init completes
Can't reference `self` in the config struct passed to `smithers_app_new` during `init()`. The Ghostty pattern works because all stored properties are assigned before the C API call. For SmithersCore, ensure all stored properties have defaults or are assigned before the `smithers_app_new` call.

### 3. SmithersUITests target not in pbxproj
The `SmithersUITests/` directory exists but is NOT a registered Xcode target. To run UI tests, either:
- Add the target to pbxproj manually
- Use `xcodebuild` with the correct scheme (must exist)
- Or run them as XCTestCase in the existing SmithersTests target (less ideal for UI tests)

### 4. Data lifetime in callbacks
When `action_cb` receives `data` and `len` for `event_chat_delta`, the data pointer points to Zig stack memory (`const chunks = ...`). This memory is valid ONLY during the callback invocation. Must copy to Swift String immediately, not defer.

### 5. @Observable vs ObservableObject
v2 uses `@Observable` (macOS 14+). Do NOT use `@Published` or `ObservableObject`. ChatModel must use `@Observable` macro. SwiftUI views access via `@Environment(AppModel.self)`, not `@EnvironmentObject`.

---

## 7. Files Referenced

| File | Relevance |
|------|-----------|
| `include/libsmithers.h` | C API contract (action tags, callbacks, payloads) |
| `src/App.zig` | performAction dispatch, wakeup callback |
| `src/codex_client.zig` | Streaming stub (3 deltas + complete), background thread |
| `src/capi.zig` | Zig-side C type definitions, comptime sync check |
| `src/action.zig` | Internal action Tag enum and Payload union |
| `src/config.zig` | RuntimeConfig (WakeupFn, ActionFn) |
| `src/lib.zig` | C exports (smithers_app_new/free/action), payloadFromC |
| `macos/Sources/Ghostty/SmithersCore.swift` | Current stub (SmithersCoreBridge) — TO REPLACE |
| `macos/Sources/App/AppModel.swift` | AppModel — TO EXTEND with SmithersCore + ChatModel |
| `macos/Sources/App/SmithersApp.swift` | App entry point — uses SmithersCoreBridge.smokeInitAndFree() |
| `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` | MessagesZone (hardcoded), onSend stub, bubble views |
| `macos/Sources/Features/Chat/Views/ChatComposerZone.swift` | Composer with onSend callback |
| `macos/SmithersTests/SmithersTests.swift` | Existing C API linking test |
| `macos/SmithersUITests/WindowFlowTests.swift` | Existing UI test (target may not be in pbxproj) |
