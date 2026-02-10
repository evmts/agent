# Context: sqlite-storage-layer

SQLite is the initial persistence layer shared by Zig (libsmithers) and Swift (GRDB.swift). We vendor the amalgamation to ensure reproducible builds and enable feature flags (FTS5/JSON1) while keeping thread-safety enabled. WAL mode is required to allow concurrent access from the Swift UI and Zig core without locking the entire database. Foreign keys are disabled by default in SQLite, so we explicitly enable them on open to enforce referential integrity for messages → sessions.

Schema v1 focuses on chat persistence only (sessions/messages). IDs are UUID-like TEXT primary keys to align with cross-interface references (C API, HTTP, Swift). We also store Codex thread identifiers (thread_id at session, optional turn_id at message). Indexes are created for high-frequency queries: messages by session, messages by timestamp, sessions by workspace path.

Design choices:
- Allocator ownership: Sqlite struct stores an Allocator. All C strings are created via `alloc.dupeZ`. Query results use an ArenaAllocator tied to the result’s lifetime.
- Close semantics: `close()` returns CloseFailed for BUSY handles (unfinalized statements), and `deinit()` poisons `self.*` to surface UAFs early.
- Parameterization: `execWithBinds()` and `queryWithBinds()` support positional `?` parameters, binding text/integer/null. TEXT binds use SQLITE_TRANSIENT semantics (or an arena copy) to avoid lifetime issues.
- Null vs empty: Query returns a `Value` union, preserving NULL distinct from empty string.

Future schema migrations will bump `PRAGMA user_version` and remain idempotent. WAL and FK settings are verified in tests to prevent regressions.

## 1. Current Codebase State

### Existing Zig files in src/
- `src/lib.zig` — Root module, C API exports, Zig API. Imports: App.zig, config.zig, action.zig, capi.zig, host.zig
- `src/App.zig` — Root app struct. Owns allocator, arena, runtime config. Ghostty lifecycle: create/init/deinit/destroy with self-poisoning
- `src/host.zig` — **THE DI pattern to follow.** VTable (optional fn ptrs) + StaticHost(comptime Impl) with @hasDecl checks
- `src/memory.zig` — Arena helpers: ScopedArena(), ownedDupe()
- `src/action.zig` — Action tags + tagged union Payload
- `src/capi.zig` — C boundary types
- `src/config.zig` — RuntimeConfig (wakeup/action callbacks)
- `src/main.zig` — CLI stub

### No pkg/ directory exists yet
First vendored dependency. Must create `pkg/sqlite/` from scratch.

### build.zig key patterns
- Module: `b.addModule("smithers", .{ .root_source_file = b.path("src/lib.zig"), ... })`
- Static lib: `b.addLibrary(.{ .name = "smithers", .root_module = mod, .linkage = .static })`
- Tests: `b.addTest(.{ .root_module = mod })` + `b.addRunArtifact(mod_tests)`
- build.zig.zon has `.dependencies = .{}` (empty — no deps yet)

## 2. DI Pattern from host.zig (FOLLOW THIS)

```zig
// Runtime vtable (optional fn ptrs, returns error on missing)
pub const VTable = struct {
    log: ?*const fn (ctx: ?*anyopaque, level: LogLevel, msg: []const u8) HostError!void = null,
    // ...
};

pub const Host = struct {
    vtable: VTable = .{},
    ctx: ?*anyopaque = null,
    pub fn log(self: *const Self, level: LogLevel, msg: []const u8) HostError!void {
        if (self.vtable.log) |f| return f(self.ctx, level, msg);
        return HostError.Unsupported;
    }
};

// Comptime static DI
pub fn StaticHost(comptime Impl: type) type {
    return struct {
        ctx: *Impl,
        pub fn log(self: *const Self, level: LogLevel, msg: []const u8) HostError!void {
            if (@hasDecl(Impl, "log")) {
                try Impl.log(self.ctx, level, msg);
                return;
            }
            return HostError.Unsupported;
        }
    };
}
```

**For Storage: replicate this pattern.** Storage interface with open/close/exec/query. SQLite as concrete impl. In-memory test stub possible via same interface.

## 3. Ghostty pkg/ Vendoring Pattern

### Simple C library (zlib-style, closest to what we need for SQLite):

```zig
// pkg/sqlite/build.zig
const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "sqlite3",
        .root_module = b.createModule(.{ .target = target, .optimize = optimize }),
        .linkage = .static,
    });
    lib.linkLibC();
    // macOS SDK: if (target.result.os.tag.isDarwin()) { apple_sdk... }
    // For SQLite vendored directly (not lazy dep), use b.path():
    lib.addIncludePath(b.path(""));  // pkg/sqlite/ contains sqlite3.h
    lib.addCSourceFiles(.{
        .root = b.path(""),
        .files = &.{"sqlite3.c"},
        .flags = &.{
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_ENABLE_JSON1",
            "-DSQLITE_THREADSAFE=1",
        },
    });
    lib.installHeadersDirectory(b.path(""), "", .{ .include_extensions = &.{".h"} });
    b.installArtifact(lib);
}
```

### Wiring into main build.zig:

**Option A: Local path dependency** (simpler for vendored-in-repo):
In build.zig.zon:
```zig
.dependencies = .{
    .sqlite = .{ .path = "pkg/sqlite" },
},
```
Then in build.zig:
```zig
const sqlite_dep = b.dependency("sqlite", .{ .target = target, .optimize = optimize });
mod.linkLibrary(sqlite_dep.artifact("sqlite3"));  // link to smithers module
lib.linkLibrary(sqlite_dep.artifact("sqlite3"));   // link to static lib
mod_tests.linkLibrary(sqlite_dep.artifact("sqlite3")); // link to tests
```

**Option B: Inline in main build.zig** (no sub-build.zig):
Add SQLite compilation directly to the smithers module. Simpler but less modular.

### @cImport pattern (from Ghostty):
```zig
// In src/storage.zig or src/storage/c.zig:
const c = @cImport({ @cInclude("sqlite3.h"); });
// Then use: c.sqlite3_open, c.sqlite3_exec, etc.
```
Build system `addIncludePath` tells Zig where to find sqlite3.h.

## 4. Zig 0.15.2 API Signatures (VERIFIED from stdlib source)

### ArenaAllocator
```zig
pub fn init(child_allocator: Allocator) ArenaAllocator  // takes value
pub fn deinit(self: ArenaAllocator) void                 // takes VALUE (not pointer!)
pub fn allocator(self: *ArenaAllocator) Allocator        // takes pointer
```

### ArrayList (std.ArrayList = UNMANAGED in 0.15)
```zig
// std.ArrayList(T) = Aligned(T, null) = UNMANAGED (allocator passed per call)
var list: std.ArrayList(Row) = .{};  // or .empty
list.append(gpa, item) // Allocator.Error!void
list.deinit(gpa)       // void, self-poisons
list.toOwnedSlice(gpa) // Allocator.Error![]T
list.items              // []T — direct field access
```

### Testing
```zig
const testing = std.testing;
const alloc = testing.allocator;       // pre-initialized, leak-detecting
testing.expectEqual(expected, actual)  // !void
testing.expectEqualStrings(exp, act)   // !void — for []const u8
testing.expectError(err, result)       // !void
```

### Allocator
```zig
alloc.dupe(u8, slice)   // Error![]u8
alloc.dupeZ(u8, slice)  // Error![:0]u8 (null-terminated)
alloc.alloc(u8, len)    // Error![]u8
alloc.free(slice)       // void
alloc.create(T)         // Error!*T
alloc.destroy(ptr)      // void
```

## 5. SQLite C API (Key Functions for Storage Layer)

```c
// Open/close
int sqlite3_open(const char *filename, sqlite3 **ppDb);
int sqlite3_close(sqlite3 *db);

// Simple exec (no results)
int sqlite3_exec(sqlite3*, const char *sql, callback, void*, char **errmsg);
void sqlite3_free(void *ptr);  // free errmsg

// Prepared statements (for parameterized queries)
int sqlite3_prepare_v2(sqlite3 *db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail);
int sqlite3_step(sqlite3_stmt *pStmt);           // SQLITE_ROW or SQLITE_DONE
int sqlite3_finalize(sqlite3_stmt *pStmt);
int sqlite3_reset(sqlite3_stmt *pStmt);

// Bind parameters
int sqlite3_bind_text(sqlite3_stmt*, int, const char*, int n, void(*)(void*));
int sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64);
int sqlite3_bind_null(sqlite3_stmt*, int);
#define SQLITE_TRANSIENT ((sqlite3_destructor_type)-1)

// Read columns
const unsigned char *sqlite3_column_text(sqlite3_stmt*, int iCol);
sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int iCol);
int sqlite3_column_bytes(sqlite3_stmt*, int iCol);
int sqlite3_column_count(sqlite3_stmt*);
int sqlite3_column_type(sqlite3_stmt*, int iCol);  // SQLITE_INTEGER, SQLITE_TEXT, etc.
const char *sqlite3_column_name(sqlite3_stmt*, int N);

// Result codes
#define SQLITE_OK        0
#define SQLITE_ROW       100
#define SQLITE_DONE      101

// Error info
const char *sqlite3_errmsg(sqlite3 *db);
int sqlite3_errcode(sqlite3 *db);
```

## 6. Schema Design (from engineering spec + v1 reference)

### v1 used JSON files (ChatHistoryStore.swift) — v2 uses SQLite
### v1 JJSnapshotStore used GRDB with these tables:

```sql
-- Chat persistence (P0)
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL DEFAULT '',
    workspace_path TEXT,
    thread_id TEXT,
    created_at INTEGER NOT NULL,  -- unix timestamp
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL,        -- 'user', 'assistant', 'system'
    kind TEXT NOT NULL,        -- 'text', 'command', 'diff', 'status'
    content TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    metadata_json TEXT,        -- optional JSON blob
    turn_id TEXT
);

CREATE INDEX idx_messages_session ON messages(session_id);
CREATE INDEX idx_messages_timestamp ON messages(timestamp);
CREATE INDEX idx_sessions_workspace ON sessions(workspace_path);
```

### Schema versioning via PRAGMA user_version:
```sql
PRAGMA user_version;           -- read current version (default 0)
PRAGMA user_version = 1;       -- set after migration
```

### WAL mode + foreign keys:
```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
```

## 7. Key Gotchas / Pitfalls

### 1. Zig @cImport returns sentinel-terminated strings
`sqlite3_column_text()` returns `[*c]const u8` (C pointer). Must convert:
```zig
const raw = c.sqlite3_column_text(stmt, col);
if (raw) |ptr| {
    const len: usize = @intCast(c.sqlite3_column_bytes(stmt, col));
    const slice = ptr[0..len];
    // Now duplicate into caller allocator
}
```

### 2. SQLITE_TRANSIENT is a function pointer cast
In Zig, represent as: `@ptrFromInt(@as(usize, @bitCast(@as(isize, -1))))`
Or define a helper constant.

### 3. ArenaAllocator.deinit takes VALUE not pointer
```zig
var arena = std.heap.ArenaAllocator.init(alloc);
arena.deinit();  // NOT &arena
```

### 4. ArrayList is UNMANAGED in 0.15
```zig
var list: std.ArrayList(T) = .{};
defer list.deinit(alloc);       // pass allocator
try list.append(alloc, item);   // pass allocator
```

### 5. sqlite3_prepare_v2 nByte parameter
Pass `-1` for null-terminated strings, or the exact byte count. Using `@intCast(sql.len)` works for Zig slices but requires null termination if passing the slice pointer.

Best pattern: use `alloc.dupeZ(u8, sql)` to get null-terminated copy, pass with `-1`.

## 8. Recommended Architecture

```
pkg/sqlite/
├── build.zig       # Compiles sqlite3.c as static lib
├── build.zig.zon   # Package manifest
├── sqlite3.c       # SQLite amalgamation (~250K lines)
└── sqlite3.h       # SQLite header

src/
├── storage.zig     # Storage interface + SQLite impl (struct-as-namespace)
└── lib.zig         # Add @import("storage.zig") for test discovery
```

### storage.zig structure:
```zig
//! Storage abstraction and SQLite implementation.
const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({ @cInclude("sqlite3.h"); });
const log = std.log.scoped(.storage);

pub const StorageError = error{
    OpenFailed,
    ExecFailed,
    PrepareFailed,
    StepFailed,
    BindFailed,
    MigrationFailed,
    InvalidState,
} || Allocator.Error;

pub const Sqlite = struct { ... };
```

### Build wiring:
1. Add `pkg/sqlite/` with build.zig + amalgamation
2. Add to build.zig.zon: `.sqlite = .{ .path = "pkg/sqlite" }`
3. In build.zig: link sqlite dep to smithers module + tests
4. Add `@import("storage.zig")` in lib.zig for discovery

## 9. Reference Files

| File | Purpose |
|------|---------|
| `src/host.zig` | DI pattern to follow (VTable + StaticHost) |
| `src/App.zig` | Lifecycle pattern (create/init/deinit/destroy, self-poisoning) |
| `src/memory.zig` | Arena + ownedDupe patterns |
| `build.zig` | Current build setup (needs sqlite dep wired in) |
| `build.zig.zon` | Needs sqlite path dependency added |
| Ghostty `pkg/zlib/build.zig` | Simplest vendored C lib pattern |
| Ghostty `src/build/SharedDeps.zig` | How deps wired to main build |
| v1 `JJSnapshotStore.swift` | GRDB schema patterns (WAL, indexes) |
| v1 `ChatHistoryStore.swift` | Chat data model (messages, sessions, images) |

## 10. Open Questions

1. **pkg/sqlite/build.zig.zon needed?** — For local path deps, the sub-package needs its own build.zig.zon. Verify with Zig 0.15.
2. **SQLITE_TRANSIENT in Zig** — Exact incantation for the function pointer sentinel. Test at compile time.
3. **linkLibC on module vs library** — Need to ensure both the smithers module AND the static library artifact link libc, since SQLite requires it.
