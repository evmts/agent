# Plan: sqlite-storage-layer

Status: Implemented on 2026-02-10. pkg/sqlite vendored + build wired; src/storage.zig trait + SQLite backend landed; tests green via `zig build all`.

Validation notes (2026-02-10): Addressed review items — allocator ownership (no page_allocator), PRAGMA foreign_keys=ON, schema uses TEXT PRIMARY KEY (UUID) plus thread_id/turn_id, created indexes, added parameterized binds, preserved NULL semantics with Value union, close semantics detect BUSY via sqlite3_close, added comprehensive tests (WAL/FK/migration/CRUD/error paths).

## Overview

Vendor SQLite amalgamation into `pkg/sqlite/` with a Zig build wrapper. Implement `src/storage.zig` with a Storage interface (comptime DI following `host.zig` pattern) and a concrete SQLite implementation. Create initial schema for chat persistence (sessions + messages tables). Enable WAL mode for concurrent Zig + Swift access.

**This is the first vendored dependency** — `pkg/` directory does not exist yet.

---

## Step 0: Create pkg/sqlite/ build infrastructure

**Layer:** zig

Create the vendored SQLite package with build system integration. Download SQLite amalgamation (sqlite3.c + sqlite3.h), create `build.zig` that compiles it as a static C library, and create `build.zig.zon` for the sub-package manifest.

**Files to create:**
- `pkg/sqlite/build.zig` — Compiles sqlite3.c as static lib with recommended defines (FTS5, JSON1, THREADSAFE=1)
- `pkg/sqlite/build.zig.zon` — Package manifest for the sqlite sub-package
- `pkg/sqlite/sqlite3.c` — SQLite amalgamation source (download from sqlite.org)
- `pkg/sqlite/sqlite3.h` — SQLite amalgamation header (download from sqlite.org)

**Details:**

`pkg/sqlite/build.zig`:
- `b.addLibrary(.{ .name = "sqlite3", ... .linkage = .static })`
- `lib.linkLibC()`
- `lib.addIncludePath(b.path(""))` — sqlite3.h is in same dir
- `lib.addCSourceFiles(.{ .root = b.path(""), .files = &.{"sqlite3.c"}, .flags = &.{"-DSQLITE_ENABLE_FTS5", "-DSQLITE_ENABLE_JSON1", "-DSQLITE_THREADSAFE=1", "-DSQLITE_DQS=0", "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1"} })`
- `lib.installHeadersDirectory(b.path(""), "", .{ .include_extensions = &.{".h"} })`
- `b.installArtifact(lib)`

`pkg/sqlite/build.zig.zon`:
- Name: `.sqlite`
- Minimal manifest with paths: `"build.zig"`, `"build.zig.zon"`, `"sqlite3.c"`, `"sqlite3.h"`

**SQLite amalgamation:** Download latest stable from https://www.sqlite.org/download.html (amalgamation zip). Extract `sqlite3.c` and `sqlite3.h` only.

---

## Step 1: Wire pkg/sqlite into root build.zig

**Layer:** zig

Add sqlite as a path dependency in build.zig.zon. Wire the sqlite static library into the smithers module, the static library artifact, and the test artifacts in build.zig. Ensure `linkLibC` is called on all consumers.

**Files to modify:**
- `build.zig.zon` — Add `.sqlite = .{ .path = "pkg/sqlite" }` to dependencies, add `"pkg"` to paths
- `build.zig` — Add sqlite dependency wiring after module creation

**build.zig changes (after line 19, after mod creation):**
```zig
// Vendored SQLite
const sqlite_dep = b.dependency("sqlite", .{ .target = target, .optimize = optimize });
mod.linkLibrary(sqlite_dep.artifact("sqlite3"));
mod.linkLibC();
```

**Also wire to test step:** The `mod_tests` created from `b.addTest(.{ .root_module = mod })` inherits module link settings, so no extra wiring needed. But the static library artifact `lib` also needs:
```zig
lib.linkLibrary(sqlite_dep.artifact("sqlite3"));
```

**Verification:** `zig build` compiles SQLite without errors. `zig build test` links against SQLite.

---

## Step 2: Write storage.zig tests (TDD — tests first)

**Layer:** zig

Write comprehensive tests for the storage interface before implementing it. Tests define the contract. Use `std.testing.allocator` for leak detection. Cover: open/close lifecycle, exec DDL, parameterized insert/query, WAL mode verification, schema migration, round-trip for sessions and messages tables, error handling, self-poisoning after deinit.

**Files to create:**
- `src/storage.zig` — Start with test blocks and minimal type stubs to make tests compile

**Tests to write (all in src/storage.zig):**

1. **"Sqlite open and close"** — Open in-memory db (`:memory:`), verify non-null handle, close, verify poisoned
2. **"Sqlite create and destroy"** — Heap-allocated lifecycle via create()/destroy()
3. **"Sqlite exec DDL"** — Create table via exec(), verify no error
4. **"Sqlite WAL mode enabled"** — Open db file (tmp path), query `PRAGMA journal_mode`, verify returns `"wal"`
5. **"Sqlite foreign keys enabled"** — Query `PRAGMA foreign_keys`, verify returns `1`
6. **"Sqlite schema version"** — Set and read `PRAGMA user_version`
7. **"Sqlite parameterized insert and query"** — Insert row with bind params, query back, verify values match
8. **"Sqlite query returns owned slices"** — Query text column, verify caller owns memory (free with allocator)
9. **"Sqlite query multiple rows"** — Insert 3 rows, query all, verify count and order
10. **"Sqlite query no results"** — Query empty table, verify empty result set
11. **"Sqlite exec error on bad SQL"** — Pass invalid SQL, verify ExecFailed error
12. **"Sqlite migrate creates sessions table"** — Run migration, verify sessions table exists
13. **"Sqlite migrate creates messages table"** — Run migration, verify messages table exists with foreign key
14. **"Sqlite migrate is idempotent"** — Run migration twice, no error
15. **"Sqlite session CRUD round trip"** — Insert session, query by id, verify all fields
16. **"Sqlite message CRUD round trip"** — Insert session + message, query messages by session_id, verify

---

## Step 3: Implement storage.zig — Error types and Sqlite struct skeleton

**Layer:** zig

Define the error set, the Sqlite struct (struct-as-file pattern following App.zig), and the C import. Implement create/init/deinit/destroy lifecycle with self-poisoning.

**Files to modify:**
- `src/storage.zig` — Add error types, struct definition, lifecycle methods

**Key types:**
```zig
pub const StorageError = error{
    OpenFailed,
    ExecFailed,
    PrepareFailed,
    StepFailed,
    BindFailed,
    MigrationFailed,
    InvalidState,
} || Allocator.Error;

// Sqlite struct fields:
alloc: Allocator,
db: ?*c.sqlite3,
```

**Lifecycle (Ghostty pattern):**
- `create(alloc, path)` — alloc on heap, call init, return pointer. errdefer destroy.
- `init(self, alloc, path)` — open sqlite3, enable WAL + foreign keys, set self.* = .{...}
- `deinit(self)` — close sqlite3, poison self.* = undefined
- `destroy(self)` — save alloc, deinit, free self

**WAL + FK pragmas in init:**
```zig
_ = c.sqlite3_exec(db, "PRAGMA journal_mode=WAL;", null, null, null);
_ = c.sqlite3_exec(db, "PRAGMA foreign_keys=ON;", null, null, null);
```

---

## Step 4: Implement storage.zig — exec() and query() methods

**Layer:** zig

Implement the core database operations: `exec()` for DDL/DML without results, and `query()` / `queryWithBinds()` for parameterized SELECT returning owned results.

**Files to modify:**
- `src/storage.zig` — Add exec, query, bind helpers

**exec(sql):**
- Takes `[:0]const u8` (null-terminated SQL string)
- Calls `sqlite3_exec()`, checks return code
- On error: log errmsg, free errmsg, return StorageError.ExecFailed

**Row type:**
```zig
pub const Value = union(enum) {
    text: []const u8,  // owned by caller allocator
    integer: i64,
    null_val: void,
};

pub const Row = struct {
    values: []Value,

    pub fn deinit(self: *Row, alloc: Allocator) void {
        for (self.values) |v| {
            switch (v) {
                .text => |t| alloc.free(t),
                else => {},
            }
        }
        alloc.free(self.values);
    }
};
```

**Rows result type:**
```zig
pub const Rows = struct {
    rows: []Row,
    column_count: usize,

    pub fn deinit(self: *Rows, alloc: Allocator) void {
        for (self.rows) |*r| r.deinit(alloc);
        alloc.free(self.rows);
    }
};
```

**query(alloc, sql, binds):**
- `alloc` = caller-provided allocator (owned-return pattern)
- `sql` = `[:0]const u8`
- `binds` = slice of `Value` for `?` parameters
- Prepare statement, bind params, step through rows, collect into Rows
- Each text column: `sqlite3_column_text` + `sqlite3_column_bytes` → `alloc.dupe(u8, slice)`
- Returns `Rows` owned by caller
- On any error: clean up partial results, finalize statement, return appropriate error

**SQLITE_TRANSIENT helper:**
```zig
const SQLITE_TRANSIENT: c.sqlite3_destructor_type = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
```

---

## Step 5: Implement storage.zig — Schema migration

**Layer:** zig

Implement `migrate()` method that checks `PRAGMA user_version` and applies schema DDL for any missing versions. Version 1 creates sessions + messages tables with indexes.

**Files to modify:**
- `src/storage.zig` — Add migrate() method and schema constants

**Schema version 1 DDL:**
```sql
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL DEFAULT '',
    workspace_path TEXT,
    thread_id TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    kind TEXT NOT NULL,
    content TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    metadata_json TEXT,
    turn_id TEXT
);

CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
CREATE INDEX IF NOT EXISTS idx_sessions_workspace ON sessions(workspace_path);
```

**migrate() logic:**
1. Read current version: `PRAGMA user_version`
2. If version < 1: exec schema v1 DDL, set `PRAGMA user_version = 1`
3. Future migrations: if version < 2: ..., etc.
4. Each migration in a transaction (BEGIN/COMMIT) for atomicity

**getSchemaVersion() helper:** Prepare `PRAGMA user_version`, step, read integer column 0.

---

## Step 6: Wire storage.zig into lib.zig for test discovery

**Layer:** zig

Add `@import("storage.zig")` in lib.zig so tests are discovered by `zig build test`. Follow existing pattern (`refAllDecls` on imported module).

**Files to modify:**
- `src/lib.zig` — Add storage import and test discovery

**Changes:**
```zig
// At top, with other imports:
const storagepkg = @import("storage.zig");

// Add test block (following host.zig pattern):
test "storage module is reachable" {
    std.testing.refAllDecls(storagepkg);
}
```

---

## Step 7: Verify green — zig build all

**Layer:** zig

Run the full check suite. Fix any warnings, formatting issues, or test failures.

**Commands:**
1. `zig fmt .` — format all Zig code
2. `zig build all` — build + tests + fmt-check + linters + C header smoke test
3. Verify zero warnings, zero test failures, zero leaks

**Expected test count:** ~16 new storage tests + existing ~12 tests = ~28 total.

---

## Dependency Graph

```
Step 0 (pkg/sqlite/ files)
    ↓
Step 1 (wire into build.zig)
    ↓
Step 2 (write tests — TDD)
    ↓
Step 3 (implement struct + lifecycle)
    ↓
Step 4 (implement exec/query)
    ↓
Step 5 (implement migration)
    ↓
Step 6 (wire into lib.zig)
    ↓
Step 7 (verify green)
```

## Risks

1. **SQLite amalgamation download** — Need to download sqlite3.c + sqlite3.h from sqlite.org. File is ~250K lines. Must be the correct version. If download fails, can use `curl` or manual fetch.

2. **Zig 0.15 @cImport with vendored C** — The interaction between `b.dependency()`, `linkLibrary()`, and `@cImport` must be wired correctly. The module needs to see sqlite3.h include path via the linked library's installed headers. If `@cImport` can't find sqlite3.h, need to add explicit include path to the smithers module.

3. **SQLITE_TRANSIENT sentinel** — The `((sqlite3_destructor_type)-1)` cast is notoriously tricky in Zig. The `@ptrFromInt(@as(usize, @bitCast(@as(isize, -1))))` incantation must be verified at compile time. If it doesn't work, alternative: use `c.SQLITE_TRANSIENT` if available via @cImport, or use SQLITE_STATIC (0) and ensure data outlives the statement.

4. **build.zig.zon path dep requires sub-package build.zig.zon** — Zig 0.15 path dependencies require the sub-package to have its own `build.zig.zon`. Must include it.

5. **ArrayList unmanaged API** — Zig 0.15 ArrayList requires allocator passed to every method. Easy to forget and get compile errors. Research doc covers this.

6. **linkLibC propagation** — Both the smithers module AND the static lib artifact need `linkLibC()` for SQLite C functions. Test artifacts inherit from module, but verify.
