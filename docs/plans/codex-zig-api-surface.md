# Plan: codex-zig-api-surface — Add Codex Zig API Surface and Push-Event Callbacks

## Overview

Add event tags (`SMITHERS_EVENT_CHAT_DELTA`, `SMITHERS_EVENT_TURN_COMPLETE`) to the unified action enum across the C header, Zig capi, and Zig action modules. Create `src/codex_client.zig` with a stub orchestrator that, on `chat_send`, spawns a background thread emitting 2–4 text deltas followed by a turn-complete event via the `runtime.action` callback.

## Spec Conflict Resolution

**Conflict:** The spec separates "actions" (host→Zig) from "events" (Zig→host), but the C API uses a single `smithers_action_tag_e` enum and `smithers_action_cb` callback for both directions. Per ticket instruction and spec-precedence rule #3 (correct API usage), we extend the existing enum with `event_*` prefixed values rather than introducing a separate event enum. This keeps the C ABI simple and avoids a second callback typedef. Documented here; a dedicated event enum can be introduced later if the unified enum grows unwieldy.

## Affected Files

| File | Action | Purpose |
|------|--------|---------|
| `include/libsmithers.h` | Modify | Add 2 event tags to enum, document payload convention |
| `src/action.zig` | Modify | Add 2 event variants to `Tag` + `Payload` |
| `src/capi.zig` | Modify | Add 2 event variants to `smithers_action_tag_e` (comptime sync auto-validates) |
| `src/codex_client.zig` | **Create** | Stub orchestrator: struct-as-file, spawn thread, emit deltas + complete |
| `src/App.zig` | Modify | Add `CodexClient` field, route `chat_send` to it |
| `src/lib.zig` | Modify | Import codex_client for test discovery, add event cases to `payloadFromC` |
| `tests/c_header_test.c` | Modify | Update static assert, add event tag compile check |

## Steps

### Step 1: Add event tags to `src/action.zig`

**File:** `src/action.zig`

Add two new variants to `Tag` enum after `status`:
- `event_chat_delta` (value 13)
- `event_turn_complete` (value 14)

Add corresponding `Payload` union variants:
- `event_chat_delta: struct { text: []const u8 }` — UTF-8 text chunk
- `event_turn_complete: void` — signals end of turn

**Rationale:** Internal Zig types come first (TDD). The `Payload` union gives the event a typed shape even though the C callback uses raw `data`/`len`.

### Step 2: Add event tags to `src/capi.zig`

**File:** `src/capi.zig`

Add matching entries to `smithers_action_tag_e`:
- `event_chat_delta` (auto-assigns 13)
- `event_turn_complete` (auto-assigns 14)

Add matching entries to `smithers_action_payload_u`:
- `event_chat_delta: smithers_string_s` (text payload)
- `event_turn_complete: extern struct { _pad: u8 = 0 }` (void-like)

The existing comptime sync block (lines 65–73) will auto-validate that `action.Tag` and `smithers_action_tag_e` match. No changes to the sync block needed — it iterates all fields dynamically.

### Step 3: Add event tags to `include/libsmithers.h`

**File:** `include/libsmithers.h`

Add to `smithers_action_tag_e` enum:
```c
SMITHERS_EVENT_CHAT_DELTA = 13,      // Zig→host: UTF-8 text chunk (data=ptr, len=bytes)
SMITHERS_EVENT_TURN_COMPLETE = 14,   // Zig→host: turn finished (data=NULL, len=0)
```

Add to `smithers_action_payload_u`:
```c
smithers_string_s event_chat_delta;                // delta text
struct { uint8_t _pad; } event_turn_complete;      // void-like
```

Add comment block documenting the event payload convention (events use raw `data`/`len` params of `smithers_action_cb`, not the payload union — the union entries exist only for ABI completeness).

### Step 4: Update `tests/c_header_test.c`

**File:** `tests/c_header_test.c`

- Update the `_Static_assert` from `SMITHERS_ACTION_STATUS == 12` to also assert `SMITHERS_EVENT_TURN_COMPLETE == 14` (or replace — keep the `STATUS == 12` assert for stability and add a new one for the last event).
- Add usage of the new event tags in `test_types()` to verify they compile.

### Step 5: Update `payloadFromC` in `src/lib.zig`

**File:** `src/lib.zig`

The `payloadFromC` function has an exhaustive switch on `action.Tag`. Add cases for the new event variants. Since events flow Zig→host (never host→Zig), these cases should never be reached in practice, but the switch must be exhaustive:

```zig
.event_chat_delta => .{ .event_chat_delta = .{ .text = cStringToSlice(payload.event_chat_delta) } },
.event_turn_complete => .{ .event_turn_complete = {} },
```

Also add a `test "payloadFromC event variants"` test for completeness, and add `codex_client` import + `refAllDecls` for test discovery.

### Step 6: Create `src/codex_client.zig` (stub orchestrator)

**File:** `src/codex_client.zig` (**NEW**)

Struct-as-file pattern following `App.zig` and Ghostty conventions.

```
//! CodexClient: stub orchestrator for streaming chat events.
const CodexClient = @This();

Fields:
- runtime: configpkg.RuntimeConfig  — callbacks to invoke
- alloc: Allocator                   — for heap-allocated thread args

Lifecycle:
- init(self, alloc, runtime) void    — initialize fields
- deinit(self) void                  — poison with undefined

Public API:
- handleChatSend(self, message) !std.Thread
  - Heap-allocate a ThreadArgs struct (runtime + message dupe)
  - Spawn a thread running streamStub
  - Return the Thread handle (caller decides join vs detach)

Private:
- ThreadArgs struct { runtime, message, alloc }
- streamStub(args) void (thread entry point):
  1. Emit 2-4 deltas via runtime.action callback:
     - Tag = event_chat_delta (as smithers_action_tag_e)
     - data = UTF-8 text ptr, len = byte count
     - Sleep 10ms between deltas (std.posix.nanosleep)
  2. Emit turn_complete:
     - Tag = event_turn_complete
     - data = null, len = 0
  3. Free ThreadArgs (self-cleanup)

Tests (in this file):
- "streaming emits >=2 deltas then complete":
  Uses TestCtx with mutex-protected ArrayList to collect events.
  Creates CodexClient, calls handleChatSend, joins thread.
  Asserts: >=2 events with tag event_chat_delta, last event is event_turn_complete.
  Uses std.testing.allocator for leak detection.

- "delta data is valid UTF-8":
  Same pattern, verify data slices are non-empty valid UTF-8.

- "no leaks on chat send":
  Implicitly covered by std.testing.allocator but called out for clarity.
```

**Key implementation details:**
- Thread entry function must be a named function (not closure) per Zig thread API
- ThreadArgs heap-allocated so thread doesn't reference caller stack
- ThreadArgs freed by the thread itself after completion (self-cleanup pattern)
- Message duped into ThreadArgs allocation so it outlives the caller
- `handleChatSend` returns `std.Thread` — tests join, production detaches
- Sleep uses `std.posix.nanosleep(0, 10 * std.time.ns_per_ms)` (verified for Zig 0.15.2)
- Tag conversion: `@enumFromInt(@intFromEnum(action.Tag.event_chat_delta))` converts Zig tag to C enum

### Step 7: Wire `CodexClient` into `src/App.zig`

**File:** `src/App.zig`

- Import `codex_client.zig`
- Add field: `codex: CodexClient` (value type, not pointer — lightweight)
- In `init()`: initialize `self.codex` via `CodexClient.init(&self.codex, alloc, runtime)`
- In `deinit()`: call `self.codex.deinit()`
- In `performAction()`: route `.chat_send` to `self.codex.handleChatSend(msg)`:
  ```zig
  .chat_send => |cs| {
      const thread = self.codex.handleChatSend(cs.message) catch |err| {
          log.warn("codex handleChatSend failed: {}", .{err});
          return;
      };
      thread.detach();
  },
  ```
- Keep the existing log + wakeup for other actions (fallback case)

**Update existing tests:**
- `"app wakeup callback invoked on performAction"` — this test sends `chat_send` which now routes to codex. The wakeup callback won't be called directly by `performAction` for `chat_send` anymore (it goes through codex's streaming path instead). Update the test to use a different action tag (e.g., `.status`) to verify wakeup still works for non-chat actions, OR verify the streaming events arrive via the action callback.

### Step 8: Verify green — `zig build all`

Run the canonical check:
```bash
zig build all
```

This runs: build (zero errors/warnings) + test (all Zig unit tests) + fmt-check + prettier-check + typos-check + shellcheck.

Also verify:
```bash
zig build xcframework
zig build xcframework-test
```

Both must succeed without project changes outside this ticket.

## Dependency Order

```
Step 1 (action.zig) ─┐
Step 2 (capi.zig) ────┤── These 3 are the enum changes, can be done together
Step 3 (libsmithers.h)┘
         │
Step 4 (c_header_test.c) ── depends on Step 3
Step 5 (lib.zig payloadFromC) ── depends on Steps 1-2
         │
Step 6 (codex_client.zig) ── depends on Steps 1-2 (uses action.Tag, config)
         │
Step 7 (App.zig wiring) ── depends on Step 6
         │
Step 8 (verify green) ── depends on all above
```

## Test Coverage

All tests use `std.testing.allocator` for leak detection.

| Test | File | What it verifies |
|------|------|------------------|
| Comptime sync check | `src/capi.zig` | Tag enum Zig↔C lockstep (automatic) |
| `payloadFromC` event variants | `src/lib.zig` | Exhaustive switch handles events |
| C header compile | `tests/c_header_test.c` | New tags compile, static asserts pass |
| Streaming order | `src/codex_client.zig` | >=2 deltas then turn_complete |
| Delta data valid | `src/codex_client.zig` | Non-empty UTF-8 text in deltas |
| App chat_send routes | `src/App.zig` | chat_send reaches codex_client |
| No leaks | All test files | std.testing.allocator catches leaks |
| xcframework build | `zig build xcframework` | Library + header package correctly |
| xcframework symbols | `zig build xcframework-test` | Symbols exported, header valid |

## Risks & Mitigations

1. **Thread callback safety:** The stub's background thread calls `runtime.action` which may be invoked from any thread. Tests use mutex-protected event collection. Production (Swift) dispatches to main queue — safe by convention.

2. **Sleep API correctness:** Research verified `std.posix.nanosleep` for Zig 0.15.2. `std.time.sleep` does NOT exist. Using verified API.

3. **Exhaustive switch breakage:** Adding enum variants breaks the exhaustive switch in `payloadFromC`. Handled in Step 5 — events map to their typed payloads.

4. **Thread lifetime in production:** `handleChatSend` returns `Thread` — caller decides join/detach. Tests join for determinism. `App.performAction` detaches. ThreadArgs self-cleanup ensures no leaks either way.
