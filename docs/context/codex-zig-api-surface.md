# Research Context: codex-zig-api-surface

## Ticket Summary

Add event tags (SMITHERS_EVENT_CHAT_DELTA, SMITHERS_EVENT_TURN_COMPLETE) to the unified action enum. Implement `src/codex_client.zig` with a stub orchestrator that, on `chat_send`, spawns a background thread emitting 2-4 deltas then a completion event via `runtime.action` callback.

## Key Files to Modify

| File | Lines | What Changes |
|------|-------|--------------|
| `include/libsmithers.h` | 110 | Add `SMITHERS_EVENT_CHAT_DELTA = 13`, `SMITHERS_EVENT_TURN_COMPLETE = 14` to `smithers_action_tag_e`. Update `_Static_assert` in c_header_test.c. |
| `src/action.zig` | 45 | Add `event_chat_delta` and `event_turn_complete` to `Tag` enum + `Payload` union. |
| `src/capi.zig` | 79 | Add matching entries to `smithers_action_tag_e`. Comptime sync check auto-validates. |
| `src/App.zig` | 86 | Route `.chat_send` in `performAction` to codex_client. |
| `src/codex_client.zig` | NEW | Stub orchestrator: spawn thread, emit deltas + completion via callback. |
| `src/lib.zig` | 171 | Import codex_client for test discovery. Events don't need `payloadFromC` (host→zig direction only). |
| `tests/c_header_test.c` | 40 | Update static assert, add event tag usage. |

## Critical Patterns to Follow

### 1. Action Tag Enum Sync (capi.zig:65-73)

The comptime block validates `action.Tag` and `smithers_action_tag_e` are in lockstep by name, count, and value. Adding new tags to both enums is sufficient — the check will catch mismatches at compile time.

```zig
// capi.zig comptime sync check
comptime {
    const t_internal = @typeInfo(action.Tag).@"enum";
    const t_c = @typeInfo(smithers_action_tag_e).@"enum";
    std.debug.assert(t_internal.fields.len == t_c.fields.len);
    for (t_internal.fields, 0..) |f, i| {
        std.debug.assert(std.mem.eql(u8, f.name, t_c.fields[i].name));
        std.debug.assert(@intFromEnum(@field(action.Tag, f.name)) == @intFromEnum(@field(smithers_action_tag_e, f.name)));
    }
}
```

### 2. Callback Invocation (config.zig:9-14)

The `ActionFn` is already defined but **never called** in current code. This is the hook:

```zig
pub const ActionFn = *const fn (
    userdata: ?*anyopaque,
    tag: capi.smithers_action_tag_e,
    data: ?[*]const u8,
    len: usize,
) callconv(.c) void;
```

To invoke from App or codex_client:
```zig
if (self.runtime.action) |cb| {
    cb(self.runtime.userdata, @enumFromInt(@intFromEnum(tag)), data_ptr, data_len);
}
```

### 3. Thread Spawn API (Zig 0.15.2)

```zig
// std.Thread.spawn signature (verified from /usr/local/zig/lib/std/Thread.zig:487)
pub fn spawn(config: SpawnConfig, comptime function: anytype, args: anytype) SpawnError!Thread

// SpawnConfig (Thread.zig:441)
pub const SpawnConfig = struct {
    stack_size: usize = default_stack_size,  // 16MB
    allocator: ?std.mem.Allocator = null,
};

// Usage pattern (from stdlib tests):
const thread = try std.Thread.spawn(.{}, myFunction, .{arg1, arg2});
thread.detach();  // or thread.join();
```

### 4. Sleep API (Zig 0.15.2 — CHANGED from older versions)

Use `std.Thread.sleep` (preferred on Zig 0.15.2) for millisecond delays:

```zig
// std.Thread.sleep (Thread.zig)
pub fn sleep(nanoseconds: u64) void
```

Usage: `std.Thread.sleep(10 * std.time.ns_per_ms);` for 10ms sleep.

### 5. Struct-as-File Pattern (App.zig)

New `codex_client.zig` should follow the same struct-as-file pattern:
- File IS the struct (`const CodexClient = @This();`)
- Fields at top, then types, then functions
- Lifecycle: `create(alloc, runtime) !*CodexClient` → `init()` → `deinit()` → `destroy()`
- Poison after deinit: `self.* = undefined`

### 6. C Header Event Payload Convention

Events flow Zig→C (opposite of actions which flow C→Zig). The `smithers_action_cb` callback sends `data` + `len` as opaque bytes. For events:
- `SMITHERS_EVENT_CHAT_DELTA`: `data` = UTF-8 text pointer, `len` = byte count
- `SMITHERS_EVENT_TURN_COMPLETE`: `data` = NULL, `len` = 0

No payload union needed for events — they use the raw `data`/`len` params of `smithers_action_cb`.

### 7. Force-Export Block (lib.zig:166-170)

Any new module imported in lib.zig gets test discovery via `refAllDecls`:
```zig
test "codex_client module is reachable" {
    std.testing.refAllDecls(codex_clientpkg);
}
```

## Gotchas / Pitfalls

### 1. Thread Safety with Callbacks
The stub spawns a background thread that calls `runtime.action` callback. The callback's `userdata` must be safe to access from any thread. In tests, use a simple struct with an atomic or mutex-protected counter. In production (Swift side), the callback dispatches to main queue — but the Zig side must not assume main-thread-only.

### 2. payloadFromC Exhaustive Switch
`payloadFromC` in lib.zig has an exhaustive switch on `action.Tag`. Adding new event tags to the enum means this switch must handle them. Since events are Zig→host (not host→Zig), the event variants should map to void/no-op in `payloadFromC`:
```zig
.event_chat_delta => .{ .event_chat_delta = {} },
.event_turn_complete => .{ .event_turn_complete = {} },
```

### 3. C Header Static Assert
`tests/c_header_test.c` has `_Static_assert(SMITHERS_ACTION_STATUS == 12, ...)`. After adding events, either update to assert on the last event tag or keep both asserts. The xcframework link test also uses the header.

### 4. Detached Thread Lifetime
The spawned thread must not reference stack-local data from the caller. Either:
- Copy data into heap (arena) before spawning
- Use `thread.join()` in tests to ensure completion before assertions
In tests: **always join**, never detach. In production: detach is fine.

### 5. Naming: "event_" prefix vs no prefix
Ticket says extend `smithers_action_tag_e` with event values. Use `event_chat_delta` / `event_turn_complete` naming (lowercase, underscore prefix) to distinguish from actions while staying in the same enum. The C header uses `SMITHERS_EVENT_CHAT_DELTA` (SCREAMING_SNAKE) per convention.

## Verified API Signatures (Zig 0.15.2)

| API | Signature | Source |
|-----|-----------|--------|
| `std.Thread.spawn` | `fn spawn(config: SpawnConfig, comptime function: anytype, args: anytype) SpawnError!Thread` | Thread.zig:487 |
| `std.Thread.detach` | `fn detach(self: Thread) void` | Thread.zig:507 |
| `std.Thread.join` | `fn join(self: Thread) ... (consumes Thread)` | Thread.zig:511+ |
| `SpawnConfig` | `struct { stack_size: usize = 16MB, allocator: ?Allocator = null }` | Thread.zig:441 |
| `std.posix.nanosleep` | `fn nanosleep(seconds: u64, nanoseconds: u64) void` | posix.zig:4955 |
| `std.time.ns_per_ms` | `const ns_per_ms = 1_000_000` | time.zig:14 |
| `@enumFromInt` | converts integer → enum | builtin |
| `@intFromEnum` | converts enum → integer | builtin |
| `@tagName` | returns name of active union/enum tag | builtin |

## Test Strategy

Tests should verify:
1. **Streaming order**: >=2 deltas followed by exactly 1 turn_complete
2. **Callback invoked**: action callback receives correct tags and data
3. **No leaks**: use `std.testing.allocator`
4. **Thread join**: join the spawned thread before asserting (don't detach in tests)

Pattern for collecting callback events in tests:
```zig
const TestCtx = struct {
    events: std.ArrayList(RecordedEvent),
    mutex: std.Thread.Mutex = .{},

    const RecordedEvent = struct {
        tag: capi.smithers_action_tag_e,
        data: []const u8,  // duped into events arena
    };

    fn callback(userdata: ?*anyopaque, tag: capi.smithers_action_tag_e, data: ?[*]const u8, len: usize) callconv(.c) void {
        const self: *TestCtx = @ptrCast(@alignCast(userdata.?));
        self.mutex.lock();
        defer self.mutex.unlock();
        const slice = if (data) |d| d[0..len] else &[_]u8{};
        self.events.append(.{ .tag = tag, .data = self.events.allocator.dupe(u8, slice) catch unreachable }) catch unreachable;
    }
};
```

## Open Questions

1. **Thread pool vs spawn-per-chat**: For the stub, one thread per `chat_send` is fine. Production will need a thread pool or async. Not needed for this ticket.

2. **Event data encoding**: Ticket says UTF-8 text chunk for deltas. Raw bytes (ptr+len) is simplest and matches the callback signature. No JSON wrapping needed for the stub. Future real Codex integration may use structured data.

3. **codex_client ownership**: Should `App` own a `CodexClient` field, or should codex_client be stateless (just functions)? Recommend: App stores a `CodexClient` field initialized in `App.init`. This allows future state (session tracking, thread pool). For the stub, it can be minimal.
