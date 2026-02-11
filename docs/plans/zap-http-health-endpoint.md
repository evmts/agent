# Plan: zap-http-health-endpoint

## Goal

Add a Zap-based HTTP server skeleton (`src/http_server.zig`) with `GET /api/health` returning `{"status":"ok"}`. Bind `127.0.0.1` only, no auth, CORS restricted to localhost. Wire Zap dependency into build system.

---

## Step 0: Add Zap v0.11.0 dependency via `zig fetch`

**Files:** `build.zig.zon`

Run `zig fetch --save "git+https://github.com/zigzap/zap#v0.11.0"` to auto-populate `build.zig.zon` with the Zap URL + content hash. This is preferred over vendoring in `pkg/zap/` because Zap is a full framework (100+ C files from facil.io), not a single-file amalgamation like SQLite. The `build.zig.zon` comments already reference `zig fetch --save` as the intended approach.

**Verification:** `zig build` still compiles (Zap not yet imported, just registered).

---

## Step 1: Wire Zap module imports into `build.zig`

**Files:** `build.zig`

Three integration points:

1. **Main `build()` function** — After `sqlite_dep` (line 76), add:
   ```zig
   const zap_dep = b.dependency("zap", .{
       .target = target,
       .optimize = optimize,
       .openssl = false,
   });
   ```
   Then add `mod.addImport("zap", zap_dep.module("zap"));` to the smithers module (after line 84). Also add to `exe.root_module.addImport("zap", ...)` for the CLI (after line 106).

2. **Test compilation** — `mod_tests` and `exe_tests` already share the module with imports, so they should pick up zap automatically. But we may need to `linkLibrary` if zap produces a C artifact. Will test and wire as needed.

3. **`buildStaticLibForTarget()` function** (line 52) — Add the same `zap_dep` + `mod.addImport` so xcframework builds include zap. This is critical — without it, `zig build xcframework` would fail.

**Verification:** `zig build` compiles with zap available but not yet imported in source.

---

## Step 2: Write tests for `src/http_server.zig` (TDD)

**Files:** `src/http_server.zig` (create — tests at bottom per Ghostty pattern)

Write tests FIRST, before implementation. Tests go at the bottom of the module file (Ghostty pattern — tests colocated with code).

### Test 1: `"HttpServer create/destroy lifecycle"`
- Create server with `std.testing.allocator` + default config
- Verify struct fields initialized correctly
- Destroy — leak detector confirms no leaks
- Verifies: lifecycle pattern (create → destroy), allocator discipline

### Test 2: `"HttpServer start/stop without requests"`
- Create server on a fixed test port (e.g., 18923)
- Start (spawns background thread, non-blocking return)
- Small sleep (200ms) for server startup
- Stop (joins thread)
- Destroy
- Verifies: thread lifecycle, clean shutdown, no resource leaks

### Test 3: `"health endpoint returns 200 JSON"`
- Create + start server on fixed test port
- Use raw TCP (`std.net.tcpConnectToHost`) to send `GET /api/health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n`
- Read response, verify contains `200` status and `{"status":"ok"}` body
- Stop + destroy
- Why raw TCP: avoids `std.http.Client` API complexity that changes across Zig versions; more reliable for CI

### Test 4: `"unknown route returns 404"`
- Same setup, send `GET /api/nonexistent HTTP/1.1\r\n...`
- Verify response contains `404`
- Stop + destroy

### Test 5: `"CORS headers present on health response"`
- Same setup, send health request
- Verify response contains `Access-Control-Allow-Origin` header restricted to localhost

**Port strategy:** Use a fixed high port (18923) for tests. If EADDRINUSE, the test fails fast with a clear message. This is simpler than ephemeral port discovery (Zap doesn't expose the bound port). The port is high enough to avoid conflicts with common services.

---

## Step 3: Implement `src/http_server.zig`

**Files:** `src/http_server.zig` (create)

Follow Ghostty struct-as-file lifecycle pattern. File name is `http_server.zig` (snake_case = namespace/module, per Ghostty naming — this is a module with functions, not a struct-as-file because the ticket says `http_server.zig`).

### Structure

```
//! HTTP/WS server for web app + Playwright tests. Wraps Zap (facil.io).
//! Binds 127.0.0.1 only. No auth (localhost trust model).

const HttpServer = @This();

// Fields
alloc: Allocator,
config: Config,
listener: zap.HttpListener,
thread: ?std.Thread = null,
started: bool = false,

// Types
pub const Config = struct { port: u16, interface: []const u8 };
pub const CreateError = Allocator.Error;
pub const StartError = error{AlreadyStarted} || std.Thread.SpawnError;

// Lifecycle
pub fn create(alloc, config) → CreateError!*HttpServer
pub fn init(self, alloc, config) → CreateError!void
pub fn deinit(self) → void
pub fn destroy(self) → void

// Server control
pub fn start(self) → StartError!void   // non-blocking, spawns thread
pub fn stop(self) → void               // calls zap.stop() + joins thread

// Handlers (private)
fn onRequest(r: zap.Request) !void     // router dispatch
fn handleHealth(r: zap.Request) void   // GET /api/health → 200 JSON
fn handleNotFound(r: zap.Request) void // catch-all → 404
fn setCorsHeaders(r: zap.Request) void // localhost-only CORS
fn handleOptions(r: zap.Request) void  // CORS preflight → 204

// Tests at bottom
```

### Key implementation details

1. **`zap.start()` blocks** — Must run in dedicated thread via `std.Thread.spawn`. `start()` returns immediately after spawning.
2. **`.workers = 1`** — MUST be 1. Workers > 1 forks process, breaking shared state (allocators, SQLite, etc.).
3. **`.threads = 2`** — I/O threads within single process. Safe.
4. **Port default** — Use `0` (OS picks) for production. Tests use fixed port.
5. **CORS** — `Access-Control-Allow-Origin: http://localhost:*` pattern. Reject non-localhost origins. Handle OPTIONS preflight with 204.
6. **Logging** — `std.log.scoped(.http_server)` for structured logs. Log start/stop/requests.
7. **Self-poisoning** — `self.* = undefined` at end of `deinit()`.

---

## Step 4: Wire `http_server` into `src/lib.zig` for test discovery

**Files:** `src/lib.zig`

Add import and test discovery block:

```zig
const http_server = @import("http_server.zig");

test "http_server module is reachable" {
    std.testing.refAllDecls(http_server);
}
```

This follows the existing pattern for `hostpkg` and `storagepkg` (lines 159-165 in lib.zig). Ensures the module compiles as part of `zig build test` and all test blocks within `http_server.zig` are discovered.

---

## Step 5: Verify green build

**Commands:** `zig build all`

Run the full check suite:
- `zig build` — compiles with zap linked
- `zig build test` — all tests pass (including new http_server tests)
- `zig build fmt-check` — formatting
- `zig build all` — everything together
- Verify xcframework still builds: `zig build xcframework` (zap wired into `buildStaticLibForTarget`)

---

## Dependency Order

```
Step 0 (zig fetch)
  → Step 1 (build.zig wiring)
    → Step 2 (write tests — they need zap importable)
      → Step 3 (implement to make tests pass)
        → Step 4 (lib.zig discovery)
          → Step 5 (verify green)
```

Steps 2 and 3 are iterative (TDD cycle: write test → implement → green → next test).

---

## Risks

1. **Zap v0.11.0 vs Zig 0.15.2 compatibility** — Zap v0.11.0 targets Zig 0.15.1. Should work with 0.15.2 (patch release). If not, fallback to Zap master branch hash. Low risk.

2. **Port conflicts in CI** — Fixed test port (18923) could collide. Mitigation: high port number, test failure message mentions port conflict. Could add retry logic later if needed.

3. **`zap.start()` thread lifecycle** — Blocking call in dedicated thread means tests must properly stop+join to avoid leaks. `std.testing.allocator` will catch leaks. Medium risk — well-understood pattern from research.

4. **xcframework build** — `buildStaticLibForTarget()` must include zap or xcframework builds break. Must wire zap_dep in that function too. Easy to miss.

5. **facil.io C compilation** — Zap internally compiles facil.io C sources. Could have issues with cross-compilation (x86_64 target for universal binary). Low risk — Zap handles this in its own build.zig.
