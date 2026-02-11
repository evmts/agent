# Context: http-chat-endpoints-serve

## Summary

Add `POST /api/chat/send` (returns 202, dispatches into App), WebSocket streaming at `/ws/chat`, and `smithers-ctl serve` subcommand. All infrastructure exists — extending, not building from scratch.

## Existing Code to Modify

### `src/http_server.zig` (336 lines)
- **Server struct** (lines 19-91): lifecycle (create/init/deinit/destroy/start/stop), spawns Zap on background thread
- **onRequest** (lines 95-115): routes GET /api/health, OPTIONS preflight, 404 fallback
- **CORS** (lines 117-162): `setCorsHeaders()` reflects localhost origins (127.0.0.1, ::1, localhost)
- **Tests** (lines 166-336): 8 tests, port base 18920, uses `std.http.Client` for HTTP assertions
- **Key gap**: `onRequest` is a file-level fn with no access to App/state. Need to thread App handle through.

### `src/main.zig` (33 lines)
- Stub CLI: creates App, parses args, handles "help" only
- No `serve` subcommand

### `src/App.zig` (97 lines)
- `performAction(payload)` dispatches actions; `chat_send` calls `codex.streamChat()`
- Has `runtime: configpkg.RuntimeConfig` with wakeup/action callbacks

### `src/action.zig` (51 lines)
- `Tag.chat_send` = 0, `Tag.event_chat_delta` = 13, `Tag.event_turn_complete` = 14
- `Payload.chat_send` = `{ message: []const u8 }`
- `Payload.event_chat_delta` = `{ text: []const u8 }`

### `src/codex_client.zig` (70 lines)
- `streamChat(runtime, message)` spawns thread emitting 3 deltas + completion via `runtime.action` callback
- Stub chunks: "Thinking… ", "Okay. ", "Done." with 10ms delays

### `src/config.zig` (33 lines)
- `RuntimeConfig` = `{ wakeup: ?WakeupFn, action: ?ActionFn, userdata: ?*anyopaque }`
- `ActionFn` signature: `fn(userdata, tag, data, len) callconv(.c) void`

## Critical API References

### Zap Request (from vendored source)
```zig
// Fields
r.path: ?[]const u8
r.body: ?[]const u8         // Raw POST body - just read the field!
r.method: ?[]const u8
r.h: [*c]fio.http_s         // Internal handle, needed for WS upgrade

// Methods
r.methodAsEnum() -> http.Method    // .GET, .POST, .OPTIONS, etc.
r.setStatus(.accepted)             // http.StatusCode enum, has .accepted = 202
r.setHeader(name, value) -> !void
r.sendJson(json_string) -> !void
r.sendBody(body) -> !void
```

### Zap WebSocket (src/websockets.zig)
```zig
const WsHandler = zap.WebSockets.Handler(MyContextType);

// Upgrade from HTTP to WS (consume the HTTP handle):
WsHandler.upgrade(r.h, &settings) -> !void

// Settings:
WsHandler.WebSocketSettings{
    .on_open: ?fn(?*Ctx, WsHandle) !void,
    .on_message: ?fn(?*Ctx, WsHandle, []const u8, bool) !void,
    .on_close: ?fn(?*Ctx, isize) !void,
    .context: ?*Ctx,
}

// Send text frame:
WsHandler.write(handle, message, true) -> !void  // true = text frame

// Close:
WsHandler.close(handle)
```

### Zap HTTP Status Codes
```zig
// Zap uses its own http.StatusCode enum (not std.http.Status)
// r.setStatus(.accepted) for 202
// r.setStatus(.bad_request) for 400
// r.setStatus(.no_content) for 204
```

### std.json (Zig 0.15.2) - Parse POST body
```zig
const ChatSendRequest = struct { message: []const u8 };
const parsed = try std.json.parseFromSlice(ChatSendRequest, allocator, body, .{});
defer parsed.deinit();
// Use parsed.value.message
```

### std.http.Client POST in tests (Zig 0.15.2)
```zig
var req = try client.request(.POST, uri, .{
    .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
});
defer req.deinit();
// Send body:
var body_buf: [256]u8 = undefined;
@memcpy(body_buf[0..json.len], json);
try req.sendBodyComplete(body_buf[0..json.len]);
// Read response:
var redirect_buf: [1024]u8 = undefined;
var resp = try req.receiveHead(&redirect_buf);
```

## Architecture Decisions

### Threading App handle into onRequest
**Problem**: `onRequest` is a file-scope fn (Zap callback). No way to pass App pointer through Zap's `on_request` callback directly.

**Options**:
1. **Module-level var** — `var global_app: ?*App = null;` set before start(). Simple, matches Ghostty singleton pattern. Zap's `on_request` can't take user data.
2. **Server stores App in Config** — `Config.app: ?*App = null;` but onRequest doesn't receive Server.
3. **Thread-local** — overkill.

**Recommendation**: Module-level `var app_handle` is the pragmatic choice. Zap's HttpListener doesn't support user context on the request callback. Ghostty's GhosttyApp uses a similar singleton pattern.

### WebSocket for streaming (vs SSE)
**Recommendation**: WebSocket at `/ws/chat` — Zap has full WS support built-in. SSE would require chunked transfer encoding which Zap doesn't natively support (no streaming response API, only full `sendBody`).

**WS flow**:
1. Client connects WS to `/ws/chat`
2. Client sends JSON `{"message":"..."}` via WS text frame
3. Server dispatches `chat_send` into App
4. App's codex_client emits `event_chat_delta` / `event_turn_complete` callbacks
5. Server's action callback relays events as WS text frames to connected clients

### Event relay pattern
The HTTP server needs to receive Codex events. Two approaches:
1. **Server registers as RuntimeConfig.action callback** — intercepts events, forwards to WS clients
2. **Server polls App state** — less efficient

**Recommendation**: Server sets up `RuntimeConfig.action` callback that both the original host AND the WS relay receive. For the `serve` command (no Swift host), the server IS the host.

## Test Strategy

### POST /api/chat/send test
- Create Server with `Config.app` pointing to an App with stub action callback
- POST JSON `{"message":"hello"}` → assert 202
- Verify action callback received `chat_send` with message "hello"

### WebSocket streaming test
- Start server with App wired to codex stub
- Connect WS client to `/ws/chat`
- Send `{"message":"test"}` over WS
- Collect frames: expect >=2 delta frames + 1 completion frame
- **Note**: Zig stdlib has no WebSocket client. Options:
  - Use raw TCP + manual WS handshake (complex)
  - Test via the action callback capture instead (simpler, validates the dispatch path)
  - Use the pub/sub pattern for unit testing the relay logic

### Port allocation for tests
Existing tests use `test_port_base` (18920) + offsets. New tests should use higher offsets (e.g., +10, +11, +12).

## Gotchas / Pitfalls

1. **Zap onRequest has no user context** — Can't pass App pointer through callback signature. Must use module-level var or equivalent.

2. **`r.body` is raw bytes** — No parsing needed to access it; just read `r.body` field directly. Don't call `parseBody()` (that's for form-urlencoded/multipart, not JSON).

3. **Zap StatusCode vs std.http.Status** — Server code uses `r.setStatus(.accepted)` (Zap's enum). Test assertions use `std.http.Status.accepted` (stdlib enum). Same numeric value (202) but different types.

4. **WebSocket upgrade consumes HTTP handle** — After `WsHandler.upgrade(r.h, &settings)`, the request handle `r` is invalid. Don't send HTTP response after upgrade.

5. **WebSocket settings lifetime** — The `WebSocketSettings` pointer is stored by facil.io as udata. It must live as long as the connection. Allocate on heap or use a global/module-level settings struct.

6. **`std.http.Client` POST body** — Use `sendBodyComplete(buf)` for sending. The buffer must be mutable (`[]u8`, not `[]const u8`). Copy const string into a var buffer first.

7. **Workers must be 1** — Already correct in existing code (`workers: 1`). Workers > 1 forks the process.

## File Dependency Graph
```
main.zig → smithers (lib.zig) → App.zig → action.zig, codex_client.zig, config.zig
                               → http_server.zig → zap (external)
                               → capi.zig → action.zig
```

## Implementation Order
1. Add `Config.app: ?*App = null` or module-level app handle to `http_server.zig`
2. Add `POST /api/chat/send` route in `onRequest` — parse body, dispatch to App, return 202
3. Add WS upgrade at `/ws/chat` — store handles, relay events as text frames
4. Wire App's RuntimeConfig.action to relay events to WS clients
5. Add `serve` subcommand in `main.zig` — parse `--port`, create App, create Server, start, block
6. Add tests: POST 202, action dispatch verification, existing tests remain green
