# Research Context: zap-http-health-endpoint

## Summary

Add `pkg/zap/` vendored dependency and `src/http_server.zig` module with `GET /api/health` → 200 JSON `{"status":"ok"}`. Bind `127.0.0.1` only. No auth. Wire into `build.zig`. Include integration test using Zig's `std.http.Client`.

---

## 1. Key Reference Files

| File | Relevance |
|------|-----------|
| `build.zig` (217 lines) | Must add zap dependency, link to smithers module + CLI |
| `build.zig.zon` | Must add `.zap = .{ .path = "pkg/zap" }` + `"pkg/zap"` to paths |
| `pkg/sqlite/build.zig` (30 lines) | Vendoring pattern to follow |
| `pkg/sqlite/build.zig.zon` | Minimal `.zon` for vendored pkg |
| `src/lib.zig` (174 lines) | Root module — must import http_server for test discovery |
| `src/App.zig` (97 lines) | Lifecycle pattern (create/init/deinit/destroy) to follow |
| `src/config.zig` (33 lines) | RuntimeConfig — http_server may need similar config |
| `src/main.zig` (33 lines) | CLI entry — could wire `smithers-ctl serve` subcommand |
| `src/host.zig` (131 lines) | VTable DI pattern — optional reference |

## 2. Vendoring Strategy: Zap v0.11.0

### Option A: `zig fetch` (URL-based, preferred for external deps)

```bash
zig fetch --save "git+https://github.com/zigzap/zap#v0.11.0"
```

This auto-populates `build.zig.zon` with URL + hash. Avoids 100+ files in repo.

### Option B: Clone into `pkg/zap/` (project convention)

Clone Zap v0.11.0 into `pkg/zap/`. This includes `src/`, `facil.io/`, `build.zig`, `build.zig.zon`. Large (~hundreds of C files from facil.io). Follows SQLite pattern but significantly more code.

**Recommendation:** Use Option A (`zig fetch --save`) for Zap. It's standard Zig practice, avoids bloating the repo, and the project comment in `build.zig.zon` already mentions `zig fetch --save` as the approach for adding dependencies. SQLite is vendored because it's a single-file amalgamation; Zap is not.

### Integration in build.zig

```zig
// In build() function, alongside sqlite_dep:
const zap_dep = b.dependency("zap", .{
    .target = target,
    .optimize = optimize,
    .openssl = false,
});

// Add zap import to the smithers module:
mod.addImport("zap", zap_dep.module("zap"));

// Also add to exe (CLI) module for potential `serve` subcommand:
exe.root_module.addImport("zap", zap_dep.module("zap"));
```

Note: Zap's build.zig handles compiling facil.io C source internally. We just link the module.

### Version Compatibility

- Zap v0.11.0 targets Zig 0.15.1
- Project uses `minimum_zig_version = "0.15.2"`
- Should be compatible (0.15.2 is a patch release of 0.15)
- If build breaks, try master branch hash instead

## 3. Zap API Reference (Critical for Implementation)

### Minimal HTTP Server

```zig
const std = @import("std");
const zap = @import("zap");

fn onRequest(r: zap.Request) !void {
    if (r.path) |path| {
        if (std.mem.eql(u8, path, "/api/health")) {
            r.sendJson("{\"status\":\"ok\"}") catch return;
            return;
        }
    }
    r.setStatusNumeric(404);
    r.sendBody("Not Found") catch return;
}

pub fn main() !void {
    var listener = zap.HttpListener.init(.{
        .port = 8080,
        .interface = "127.0.0.1",
        .on_request = onRequest,
        .log = false,
    });
    try listener.listen();
    // BLOCKS until zap.stop() called
    zap.start(.{ .threads = 2, .workers = 1 });
}
```

### Key API Types

```
zap.HttpListener.init(settings) → HttpListener
  .listen() → !void  (binds socket)
zap.start(.{ .threads, .workers }) → void  (BLOCKS, runs event loop)
zap.stop() → void  (triggers shutdown, start() returns)

zap.Request:
  .path: ?[]const u8
  .method: ?[]const u8
  .body: ?[]const u8
  .query: ?[]const u8
  .sendJson(json: []const u8) → HttpError!void  (sets Content-Type: application/json)
  .sendBody(body: []const u8) → HttpError!void
  .setStatusNumeric(status: usize) → void
  .setHeader(name, value) → HttpError!void
  .methodAsEnum() → http.Method
```

### Binding Address

The `interface` field in `HttpListenerSettings` is `[*c]const u8` (C string). Pass `"127.0.0.1"` for localhost-only binding.

### CORS Headers

Must set manually via `r.setHeader()`:

```zig
fn setCorsHeaders(r: zap.Request) void {
    r.setHeader("Access-Control-Allow-Origin", "http://localhost:5173") catch {};
    r.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS") catch {};
    r.setHeader("Access-Control-Allow-Headers", "Content-Type") catch {};
}
```

### Port Discovery (Ephemeral)

Zap does NOT expose the actual bound port when using port 0. Two approaches:
1. **Use a known port** (simpler, sufficient for dev tool)
2. **Scan ports** before starting (try bind, find available)

For testing with ephemeral port, alternatives:
- Use Zig's `std.net` to find an available port, then pass to Zap
- Or use a fixed port in tests (e.g., 19285) and retry on EADDRINUSE

### Server Lifecycle (Critical Gotcha)

**`zap.start()` BLOCKS the calling thread.** Must run in a dedicated thread:

```zig
pub fn startInThread(self: *HttpServer) !void {
    self.thread = try std.Thread.spawn(.{}, runServer, .{self});
}

fn runServer(self: *HttpServer) void {
    zap.start(.{ .threads = 2, .workers = 1 });
    // Execution resumes here after zap.stop()
    self.stopped = true;
}

pub fn stop(self: *HttpServer) void {
    zap.stop();
    if (self.thread) |t| t.join();
}
```

### Workers vs Threads

- `.workers = 1` — **MUST use 1** because workers > 1 forks the process. Shared state (SQLite, allocators) would be lost.
- `.threads = 2` — I/O threads within the single process. Safe with shared state.

## 4. Test Strategy

### Integration Test Using `std.http.Client` (Zig 0.15)

```zig
const std = @import("std");

test "health endpoint returns 200 JSON" {
    const alloc = std.testing.allocator;

    // 1. Start server in background thread
    var server = try HttpServer.create(alloc, .{ .port = 0 }); // or fixed test port
    defer server.destroy();
    try server.start();

    // 2. Wait for server to be ready (small sleep or polling)
    std.time.sleep(100 * std.time.ns_per_ms);

    // 3. HTTP client request
    var client: std.http.Client = .{ .allocator = alloc };
    defer client.deinit();

    var body = std.ArrayListUnmanaged(u8){};
    defer body.deinit(alloc);

    const result = try client.fetch(.{
        .location = .{ .url = "http://127.0.0.1:<port>/api/health" },
        .response_writer = ... // need to pipe to body
    });

    try std.testing.expectEqual(std.http.Status.ok, result.status);
    // Parse and verify JSON body
}
```

**Important Zig 0.15 `std.http.Client.fetch` API:**
- `FetchOptions.location` is a tagged union: `.url` or `.uri`
- Returns `FetchResult` with `.status: http.Status`
- To capture body, use `response_writer` (a `*std.Io.Writer`)
- Alternative: use lower-level `client.request()` + `req.sendBodiless()` + `req.receiveHead()` + read body

### Simpler Test Alternative: Raw TCP

```zig
test "health endpoint raw TCP" {
    // Start server thread...

    const stream = try std.net.tcpConnectToHost(alloc, "127.0.0.1", port);
    defer stream.close();

    const request = "GET /api/health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";
    _ = try stream.writeAll(request);

    var buf: [4096]u8 = undefined;
    const n = try stream.read(&buf);
    const response = buf[0..n];

    // Verify contains 200 and JSON body
    try std.testing.expect(std.mem.indexOf(u8, response, "200") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "{\"status\":\"ok\"}") != null);
}
```

This avoids `std.http.Client` complexity and is more portable across Zig versions.

## 5. Module Design: `src/http_server.zig`

Follow Ghostty struct-as-file pattern (PascalCase → struct-as-file would be `HttpServer.zig`, but ticket says `http_server.zig` which is namespace style). Since the ticket specifies `http_server.zig`, use that name.

### Proposed Structure

```zig
//! HTTP/WS server for web app + Playwright. Wraps Zap (facil.io).
//! Binds 127.0.0.1 only. No auth (security-posture.md: localhost trust).

const std = @import("std");
const zap = @import("zap");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.http_server);

pub const Config = struct {
    port: u16 = 0,  // 0 = OS picks
    interface: []const u8 = "127.0.0.1",
};

// Server lifecycle: create → start (spawns thread) → stop → destroy
// start() is non-blocking (runs zap in bg thread)
// stop() calls zap.stop() + joins thread

pub const StartError = error{AlreadyStarted} || std.Thread.SpawnError;

pub fn start(config: Config) StartError!void { ... }
pub fn stop() void { ... }

// Request handlers
fn onRequest(r: zap.Request) !void { ... }
fn handleHealth(r: zap.Request) void { ... }
fn handleNotFound(r: zap.Request) void { ... }
fn setCorsHeaders(r: zap.Request) void { ... }
```

### Integration with lib.zig

```zig
// In src/lib.zig, add:
const http_server = @import("http_server.zig");

// In test discovery block:
test "http_server module is reachable" {
    std.testing.refAllDecls(http_server);
}
```

## 6. build.zig Changes Required

1. **Add zap dependency** to `build.zig.zon`:
   - Either `zig fetch --save "git+https://github.com/zigzap/zap#v0.11.0"` (auto)
   - Or manually add URL + hash

2. **Wire in build.zig**:
   ```zig
   const zap_dep = b.dependency("zap", .{
       .target = target,
       .optimize = optimize,
       .openssl = false,
   });
   mod.addImport("zap", zap_dep.module("zap"));
   // Also for smithers-ctl CLI:
   exe.root_module.addImport("zap", zap_dep.module("zap"));
   ```

3. **Tests**: The existing `mod_tests` and `exe_tests` should automatically pick up the new module since they use `mod` which will have zap imported.

4. **`buildStaticLibForTarget`**: Must also add zap dependency for xcframework builds. Add the same `zap_dep` + `mod.addImport` in that function.

5. **Link zap to static lib**: `lib.linkLibrary(zap_dep.artifact("facilio"))` may be needed if Zap exposes a C artifact. Check Zap's build.zig — module-level linking may handle this.

## 7. Gotchas & Pitfalls

1. **`zap.start()` blocks** — Must spawn in dedicated thread. Test must handle thread lifecycle.

2. **Port 0 (ephemeral) not queryable** — Zap/facil.io doesn't expose the actual bound port. Options: (a) use a fixed port, (b) pre-scan for available port, (c) try several ports with retry.

3. **`.workers = 1` mandatory** — Workers > 1 forks process. Shared state breaks.

4. **Zig 0.15.2 vs Zap v0.11.0** — Zap v0.11.0 targets 0.15.1. Should work with 0.15.2 (patch). If not, use master branch hash.

5. **`std.http.Client` API changed in 0.15** — The `fetch()` API uses `response_writer: ?*std.Io.Writer` (not a simple buffer). Raw TCP may be simpler for tests.

## 8. Security Posture Alignment

Per `eng/security-posture.md` and CLAUDE.md:
- MUST bind to `127.0.0.1` only (NEVER `0.0.0.0`)
- No auth required (localhost trust model)
- CORS: reject non-localhost origins
- Random high port (ephemeral range 49152-65535) by default
- No filesystem access beyond workspace root (future)

## 9. Open Questions

1. **Vendoring vs fetch?** — Should Zap be vendored in `pkg/zap/` (project convention for C deps) or fetched via `zig fetch` (standard for Zig packages with their own build.zig)? The SQLite precedent is a single amalgamation file; Zap is 100+ files. Recommendation: `zig fetch`.

2. **Port strategy for tests** — Use ephemeral (port 0) with workaround for discovery, or use a fixed high port (e.g., 19285) with retry on EADDRINUSE? Fixed port is simpler.

3. **Where does the server live in App lifecycle?** — Does `App.zig` own the HTTP server, or is it standalone (started from CLI `main.zig`)? For this ticket, standalone module with its own start/stop is sufficient. Future: App owns it.
