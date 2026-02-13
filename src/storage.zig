//! Storage abstraction and SQLite implementation.
//! Foundation for chat persistence, agent state, workspace settings, and JJ snapshots.
//! All business-logic persistence routes through this interface. Zig owns lifetimes and
//! allocators explicitly; no global allocators.
const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.storage);

pub const Error = Allocator.Error || error{
    OpenFailed,
    CloseFailed,
    ExecFailed,
    QueryFailed,
    StepFailed,
    NotOpen,
    Invalid,
};

/// Compile-time injected storage wrapper. Mirrors host.StaticHost pattern.
pub fn StaticStorage(comptime Impl: type) type {
    return struct {
        const Self = @This();
        ctx: *Impl,

        pub fn open(self: *Self, path: []const u8) Error!void {
            if (@hasDecl(Impl, "open")) return Impl.open(self.ctx, path);
            return error.Invalid;
        }
        pub fn close(self: *Self) void {
            if (@hasDecl(Impl, "close")) Impl.close(self.ctx);
        }
        pub fn exec(self: *Self, sql: []const u8) Error!void {
            if (@hasDecl(Impl, "exec")) return Impl.exec(self.ctx, sql);
            return error.Invalid;
        }
        pub fn query(self: *Self, alloc: Allocator, sql: []const u8) Error!QueryResult {
            if (@hasDecl(Impl, "query")) return Impl.query(self.ctx, alloc, sql);
            return error.Invalid;
        }

        pub fn execWithBinds(self: *Self, sql: []const u8, binds: []const Impl.Bind) Error!void {
            if (@hasDecl(Impl, "execWithBinds")) return Impl.execWithBinds(self.ctx, sql, binds);
            return error.Invalid;
        }

        pub fn queryWithBinds(self: *Self, alloc: Allocator, sql: []const u8, binds: []const Impl.Bind) Error!QueryResult {
            if (@hasDecl(Impl, "queryWithBinds")) return Impl.queryWithBinds(self.ctx, alloc, sql, binds);
            return error.Invalid;
        }
    };
}

/// Query result with arena-owned deep copies.
pub const Value = union(enum) {
    text: []const u8,
    integer: i64,
    null_val: void,
};

pub const QueryResult = struct {
    const Self = @This();
    arena: std.heap.ArenaAllocator,
    columns: [][]const u8,
    rows: []Row,

    pub const Row = struct { values: []Value };

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
        self.* = undefined; // poison
    }
};

// ----------------- SQLite backend -----------------
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Sqlite = struct {
    const Self = @This();
    alloc: Allocator,
    db: ?*c.sqlite3 = null,

    pub fn init(alloc: Allocator) Self {
        return .{ .alloc = alloc, .db = null };
    }

    pub fn open(self: *Self, path: []const u8) Error!void {
        if (self.db != null) return error.Invalid; // double-open is a bug
        const zpath = try self.alloc.dupeZ(u8, path);
        defer self.alloc.free(zpath);
        var out: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open_v2(@ptrCast(zpath.ptr), &out, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX, null);
        if (rc != c.SQLITE_OK or out == null) {
            if (out) |h| _ = c.sqlite3_close(h);
            log.err("sqlite open failed rc={d}", .{rc});
            return error.OpenFailed;
        }
        self.db = out;
        // Enable WAL and pragmatic defaults. Foreign keys must be enabled explicitly.
        try self.exec("PRAGMA journal_mode=WAL;");
        try self.exec("PRAGMA synchronous=NORMAL;");
        try self.exec("PRAGMA foreign_keys=ON;");
        try self.ensureSchema();
    }

    /// Close the database connection. Leaves the struct usable for a
    /// subsequent `open()`; sets `db = null` on success. Does not poison.
    pub fn close(self: *Self) Error!void {
        if (self.db) |h| {
            const rc = c.sqlite3_close(h);
            if (rc != c.SQLITE_OK) return error.CloseFailed;
            self.db = null;
            return;
        }
        return error.NotOpen;
    }

    /// Final cleanup for owned instances. Safe to call even if already closed.
    pub fn deinit(self: *Self) void {
        if (self.db) |h| {
            _ = c.sqlite3_close(h);
        }
        self.* = undefined; // poison after free
    }

    pub fn exec(self: *Self, sql: []const u8) Error!void {
        const db = self.db orelse return error.NotOpen;
        const zsql = try self.alloc.dupeZ(u8, sql);
        defer self.alloc.free(zsql);
        var errmsg: [*c]u8 = null;
        const rc = c.sqlite3_exec(db, @ptrCast(zsql.ptr), null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) {
                log.debug("sqlite exec error: {s}", .{@as([*:0]const u8, @ptrCast(errmsg))});
                c.sqlite3_free(errmsg);
            }
            return error.ExecFailed;
        }
    }

    pub fn execWithBinds(self: *Self, sql: []const u8, binds: []const Bind) Error!void {
        const db = self.db orelse return error.NotOpen;
        const zsql = try self.alloc.dupeZ(u8, sql);
        defer self.alloc.free(zsql);
        var stmt: ?*c.sqlite3_stmt = null;
        const rc_prep = c.sqlite3_prepare_v2(db, @ptrCast(zsql.ptr), @intCast(zsql.len), &stmt, null);
        if (rc_prep != c.SQLITE_OK or stmt == null) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);
        // Keep bound TEXT memory alive until finalize
        var bind_arena = std.heap.ArenaAllocator.init(self.alloc);
        defer bind_arena.deinit();
        const bind_alloc = bind_arena.allocator();

        for (binds, 0..) |b, i| {
            const idx: c_int = @intCast(i + 1);
            const rc: c_int = switch (b) {
                .null_val => c.sqlite3_bind_null(stmt, idx),
                .integer => |v| c.sqlite3_bind_int64(stmt, idx, v),
                .text => |s| blk: {
                    const dup = try bind_alloc.dupe(u8, s);
                    break :blk c.sqlite3_bind_text(stmt, idx, @ptrCast(dup.ptr), @intCast(dup.len), c.SQLITE_STATIC);
                },
            };
            if (rc != c.SQLITE_OK) return error.QueryFailed;
        }
        const rc_step = c.sqlite3_step(stmt);
        const ok = rc_step == c.SQLITE_DONE or rc_step == c.SQLITE_ROW; // accept RETURNING as well
        if (!ok) return error.StepFailed;
    }

    pub fn query(self: *Self, caller: Allocator, sql: []const u8) Error!QueryResult {
        const db = self.db orelse return error.NotOpen;
        const zsql = try self.alloc.dupeZ(u8, sql);
        defer self.alloc.free(zsql);

        var stmt: ?*c.sqlite3_stmt = null;
        const rc_prep = c.sqlite3_prepare_v2(db, @ptrCast(zsql.ptr), @intCast(zsql.len), &stmt, null);
        if (rc_prep != c.SQLITE_OK or stmt == null) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        var arena = std.heap.ArenaAllocator.init(caller);
        errdefer arena.deinit();
        const a = arena.allocator();

        const col_count: usize = @intCast(c.sqlite3_column_count(stmt));
        const columns = try a.alloc([]const u8, col_count);
        for (columns, 0..) |*name, i| {
            const cstr: [*:0]const u8 = @ptrCast(c.sqlite3_column_name(stmt, @intCast(i)));
            // Copy column name into arena
            name.* = try a.dupe(u8, std.mem.span(cstr));
        }

        var rows = std.ArrayListUnmanaged(QueryResult.Row){};
        while (true) {
            const rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_ROW) {
                var vals = try a.alloc(Value, col_count);
                var i: usize = 0;
                while (i < col_count) : (i += 1) {
                    const ctype = c.sqlite3_column_type(stmt, @intCast(i));
                    switch (ctype) {
                        c.SQLITE_NULL => vals[i] = .{ .null_val = {} },
                        c.SQLITE_INTEGER => vals[i] = .{ .integer = c.sqlite3_column_int64(stmt, @intCast(i)) },
                        c.SQLITE_TEXT => {
                            const txt: [*c]const u8 = @ptrCast(c.sqlite3_column_text(stmt, @intCast(i)));
                            const blen: usize = @intCast(c.sqlite3_column_bytes(stmt, @intCast(i)));
                            vals[i] = .{ .text = try a.dupe(u8, txt[0..blen]) };
                        },
                        else => {
                            // For now treat BLOB/REAL as text copies
                            const txt2: [*c]const u8 = @ptrCast(c.sqlite3_column_text(stmt, @intCast(i)));
                            const blen2: usize = @intCast(c.sqlite3_column_bytes(stmt, @intCast(i)));
                            vals[i] = .{ .text = try a.dupe(u8, txt2[0..blen2]) };
                        },
                    }
                }
                try rows.append(a, .{ .values = vals });
            } else if (rc == c.SQLITE_DONE) {
                break;
            } else {
                return error.StepFailed;
            }
        }

        return .{ .arena = arena, .columns = columns, .rows = try rows.toOwnedSlice(a) };
    }

    pub const Bind = union(enum) {
        text: []const u8,
        integer: i64,
        null_val: void,
    };

    fn sqliteTransient() c.sqlite3_destructor_type {
        return c.SQLITE_TRANSIENT;
    }

    pub fn queryWithBinds(self: *Self, caller: Allocator, sql: []const u8, binds: []const Bind) Error!QueryResult {
        const db = self.db orelse return error.NotOpen;
        const zsql = try self.alloc.dupeZ(u8, sql);
        defer self.alloc.free(zsql);

        var stmt: ?*c.sqlite3_stmt = null;
        const rc_prep = c.sqlite3_prepare_v2(db, @ptrCast(zsql.ptr), @intCast(zsql.len), &stmt, null);
        if (rc_prep != c.SQLITE_OK or stmt == null) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        // Bind parameters 1-based
        for (binds, 0..) |b, i| {
            const idx: c_int = @intCast(i + 1);
            const rc: c_int = switch (b) {
                .null_val => c.sqlite3_bind_null(stmt, idx),
                .integer => |v| c.sqlite3_bind_int64(stmt, idx, v),
                .text => |s| c.sqlite3_bind_text(stmt, idx, @ptrCast(s.ptr), @intCast(s.len), sqliteTransient()),
            };
            if (rc != c.SQLITE_OK) return error.QueryFailed;
        }
        // Reuse row-reading from query() by stepping manually and copying
        var arena = std.heap.ArenaAllocator.init(caller);
        errdefer arena.deinit();
        const a = arena.allocator();

        const col_count: usize = @intCast(c.sqlite3_column_count(stmt));
        const columns = try a.alloc([]const u8, col_count);
        for (columns, 0..) |*name, j| {
            const cstr: [*:0]const u8 = @ptrCast(c.sqlite3_column_name(stmt, @intCast(j)));
            name.* = try a.dupe(u8, std.mem.span(cstr));
        }

        var rows = std.ArrayListUnmanaged(QueryResult.Row){};
        while (true) {
            const rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_ROW) {
                var vals = try a.alloc(Value, col_count);
                var j: usize = 0;
                while (j < col_count) : (j += 1) {
                    const ctype = c.sqlite3_column_type(stmt, @intCast(j));
                    switch (ctype) {
                        c.SQLITE_NULL => vals[j] = .{ .null_val = {} },
                        c.SQLITE_INTEGER => vals[j] = .{ .integer = c.sqlite3_column_int64(stmt, @intCast(j)) },
                        c.SQLITE_TEXT => {
                            const txt: [*c]const u8 = @ptrCast(c.sqlite3_column_text(stmt, @intCast(j)));
                            const blen: usize = @intCast(c.sqlite3_column_bytes(stmt, @intCast(j)));
                            vals[j] = .{ .text = try a.dupe(u8, txt[0..blen]) };
                        },
                        else => {
                            const txt2: [*c]const u8 = @ptrCast(c.sqlite3_column_text(stmt, @intCast(j)));
                            const blen2: usize = @intCast(c.sqlite3_column_bytes(stmt, @intCast(j)));
                            vals[j] = .{ .text = try a.dupe(u8, txt2[0..blen2]) };
                        },
                    }
                }
                try rows.append(a, .{ .values = vals });
            } else if (rc == c.SQLITE_DONE) {
                break;
            } else {
                return error.StepFailed;
            }
        }

        return .{ .arena = arena, .columns = columns, .rows = try rows.toOwnedSlice(a) };
    }

    fn ensureSchema(self: *Self) Error!void {
        // user_version=0 -> apply migration 1
        var has = try self.query(self.alloc, "PRAGMA user_version;");
        defer has.deinit();
        var ver: usize = 0;
        if (has.rows.len > 0 and has.rows[0].values.len > 0) {
            // Column 0 is integer user_version
            const v0 = has.rows[0].values[0];
            switch (v0) {
                .integer => |iv| ver = @intCast(iv),
                .text => |s| ver = std.fmt.parseInt(usize, s, 10) catch 0,
                else => ver = 0,
            }
        }
        if (ver == 0) {
            // UUID-text primary keys per plan; thread_id for session; turn_id for messages.
            try self.exec("CREATE TABLE IF NOT EXISTS sessions (\n" ++
                "  id TEXT PRIMARY KEY,\n" ++
                "  thread_id TEXT,\n" ++
                "  title TEXT,\n" ++
                "  workspace_path TEXT,\n" ++
                "  created_at INTEGER NOT NULL,\n" ++
                "  updated_at INTEGER NOT NULL\n" ++
                ");");
            try self.exec("CREATE TABLE IF NOT EXISTS messages (\n" ++
                "  id TEXT PRIMARY KEY,\n" ++
                "  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,\n" ++
                "  turn_id TEXT,\n" ++
                "  role TEXT NOT NULL,\n" ++
                "  kind TEXT NOT NULL,\n" ++
                "  content TEXT NOT NULL,\n" ++
                "  metadata_json TEXT,\n" ++
                "  timestamp INTEGER NOT NULL\n" ++
                ");");
            // Performance-critical indexes
            try self.exec("CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);");
            try self.exec("CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);");
            try self.exec("CREATE INDEX IF NOT EXISTS idx_sessions_workspace ON sessions(workspace_path);");
            try self.exec("PRAGMA user_version=1;");
        }
    }
};

// ----------------- Tests -----------------

test "sqlite open/close" {
    const t = std.testing;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const p = try tmp.dir.realpathAlloc(t.allocator, ".");
    defer t.allocator.free(p);
    const dbfile = try std.fs.path.join(t.allocator, &.{ p, "test.db" });
    defer t.allocator.free(dbfile);

    var s = Sqlite.init(t.allocator);
    try s.open(dbfile);
    try s.close();
}

test "sqlite exec + query roundtrip" {
    const t = std.testing;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const p = try tmp.dir.realpathAlloc(t.allocator, ".");
    defer t.allocator.free(p);
    const dbfile = try std.fs.path.join(t.allocator, &.{ p, "rt.db" });
    defer t.allocator.free(dbfile);

    var s = Sqlite.init(t.allocator);
    try s.open(dbfile);
    defer {
        _ = s.close() catch {}; // ignore error in happy path
    }

    try s.exec("CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT);");
    try s.exec("INSERT INTO kv(k,v) VALUES('a','1'),('b','2');");

    var res = try s.query(t.allocator, "SELECT k,v FROM kv ORDER BY k;");
    defer res.deinit();
    try t.expectEqual(@as(usize, 2), res.rows.len);
    // Expect typed results
    const v0 = res.rows[0].values[0];
    switch (v0) {
        .text => |s0| try t.expectEqualStrings("a", s0),
        else => return error.Unexpected,
    }
    const v1 = res.rows[0].values[1];
    switch (v1) {
        .text => |s1| try t.expectEqualStrings("1", s1),
        else => return error.Unexpected,
    }
}

test "sqlite pragmas wal+fk enabled and migration idempotent" {
    const t = std.testing;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const p = try tmp.dir.realpathAlloc(t.allocator, ".");
    defer t.allocator.free(p);
    const dbfile = try std.fs.path.join(t.allocator, &.{ p, "pragmas.db" });
    defer t.allocator.free(dbfile);

    var s = Sqlite.init(t.allocator);
    try s.open(dbfile);
    defer _ = s.close() catch {};

    var mode = try s.query(t.allocator, "PRAGMA journal_mode;");
    defer mode.deinit();
    try t.expect(mode.rows.len >= 1);
    switch (mode.rows[0].values[0]) {
        .text => |m| try t.expectEqualStrings("wal", m),
        else => return error.Unexpected,
    }

    var fk = try s.query(t.allocator, "PRAGMA foreign_keys;");
    defer fk.deinit();
    switch (fk.rows[0].values[0]) {
        .integer => |iv| try t.expect(iv == 1),
        .text => |sval| try t.expectEqualStrings("1", sval),
        else => return error.Unexpected,
    }

    // Ensure re-running ensureSchema path is idempotent
    try s.exec("PRAGMA user_version=0;");
    try s.ensureSchema();
}

test "sqlite binds and fk enforcement" {
    const t = std.testing;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const p = try tmp.dir.realpathAlloc(t.allocator, ".");
    defer t.allocator.free(p);
    const dbfile = try std.fs.path.join(t.allocator, &.{ p, "fk.db" });
    defer t.allocator.free(dbfile);

    var s = Sqlite.init(t.allocator);
    try s.open(dbfile);
    defer _ = s.close() catch {};

    // Insert a session and a message referencing it using binds
    const sess_id = "abc-123";
    const now: i64 = 1700000000;
    try s.exec("DELETE FROM sessions;");
    try s.exec("DELETE FROM messages;");
    try s.execWithBinds(
        "INSERT INTO sessions(id, thread_id, title, workspace_path, created_at, updated_at) VALUES (?,?,?,?,?,?);",
        &.{ .{ .text = sess_id }, .{ .null_val = {} }, .{ .text = "Title" }, .{ .text = "/tmp" }, .{ .integer = now }, .{ .integer = now } },
    );

    // Valid child
    try s.execWithBinds(
        "INSERT INTO messages(id, session_id, turn_id, role, kind, content, timestamp) VALUES (?,?,?,?,?,?,?);",
        &.{ .{ .text = "m1" }, .{ .text = sess_id }, .{ .null_val = {} }, .{ .text = "user" }, .{ .text = "text" }, .{ .text = "hi" }, .{ .integer = now } },
    );

    // Orphan should fail due to FK
    const orphan = s.execWithBinds(
        "INSERT INTO messages(id, session_id, role, kind, content, timestamp) VALUES (?,?,?,?,?,?);",
        &.{ .{ .text = "m2" }, .{ .text = "missing" }, .{ .text = "user" }, .{ .text = "text" }, .{ .text = "hi" }, .{ .integer = now } },
    );
    try t.expectError(error.StepFailed, orphan);
}

test "sqlite invalid sql and closed db errors" {
    const t = std.testing;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const p = try tmp.dir.realpathAlloc(t.allocator, ".");
    defer t.allocator.free(p);
    const dbfile = try std.fs.path.join(t.allocator, &.{ p, "err.db" });
    defer t.allocator.free(dbfile);

    var s = Sqlite.init(t.allocator);
    try s.open(dbfile);
    // Bad SQL should fail with ExecFailed
    try t.expectError(error.ExecFailed, s.exec("THIS IS NOT SQL"));
    // Close and then ensure operations complain NotOpen
    try s.close();
    // After close(), operations must fail with NotOpen
    try t.expectError(error.NotOpen, s.exec("SELECT 1;"));
    try t.expectError(error.NotOpen, s.query(t.allocator, "SELECT 1;"));
}

test "sqlite close fails when statements are unfinalized" {
    const t = std.testing;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const p = try tmp.dir.realpathAlloc(t.allocator, ".");
    defer t.allocator.free(p);
    const dbfile = try std.fs.path.join(t.allocator, &.{ p, "busy.db" });
    defer t.allocator.free(dbfile);

    var s = Sqlite.init(t.allocator);
    try s.open(dbfile);
    // Prepare a statement and intentionally do not finalize (keep stmt alive)
    const db = s.db.?;
    var stmt: ?*c.sqlite3_stmt = null;
    const zsql = try s.alloc.dupeZ(u8, "SELECT 1;");
    defer s.alloc.free(zsql);
    const rc_prep = c.sqlite3_prepare_v2(db, @ptrCast(zsql.ptr), @intCast(zsql.len), &stmt, null);
    try t.expect(rc_prep == c.SQLITE_OK and stmt != null);

    // Now attempt to close; expect CloseFailed due to unfinalized stmt
    try t.expectError(error.CloseFailed, s.close());

    // Finalize and close cleanly
    _ = c.sqlite3_finalize(stmt);
    try s.close();
}

test "sqlite null handling vs empty string" {
    const t = std.testing;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const p = try tmp.dir.realpathAlloc(t.allocator, ".");
    defer t.allocator.free(p);
    const dbfile = try std.fs.path.join(t.allocator, &.{ p, "nulls.db" });
    defer t.allocator.free(dbfile);

    var s = Sqlite.init(t.allocator);
    try s.open(dbfile);
    defer _ = s.close() catch {};

    const sess_id = "n1";
    const now: i64 = 1700000001;
    try s.execWithBinds(
        "INSERT INTO sessions(id, thread_id, title, workspace_path, created_at, updated_at) VALUES (?,?,?,?,?,?);",
        &.{ .{ .text = sess_id }, .{ .null_val = {} }, .{ .text = "T" }, .{ .text = "/w" }, .{ .integer = now }, .{ .integer = now } },
    );
    // Insert message with metadata_json NULL and another with empty string
    try s.execWithBinds(
        "INSERT INTO messages(id, session_id, role, kind, content, metadata_json, timestamp) VALUES (?,?,?,?,?,?,?);",
        &.{ .{ .text = "mnull" }, .{ .text = sess_id }, .{ .text = "user" }, .{ .text = "text" }, .{ .text = "c" }, .{ .null_val = {} }, .{ .integer = now } },
    );
    try s.execWithBinds(
        "INSERT INTO messages(id, session_id, role, kind, content, metadata_json, timestamp) VALUES (?,?,?,?,?,?,?);",
        &.{ .{ .text = "mempty" }, .{ .text = sess_id }, .{ .text = "user" }, .{ .text = "text" }, .{ .text = "c" }, .{ .text = "" }, .{ .integer = now } },
    );

    var res = try s.query(t.allocator, "SELECT id, metadata_json FROM messages ORDER BY id;");
    defer res.deinit();
    try t.expectEqual(@as(usize, 2), res.rows.len);
    // First row (mempty or mnull depending on sort) — check both
    // Find mnull row and assert null_val
    var found_null = false;
    var found_empty = false;
    for (res.rows) |row| {
        const idv = row.values[0];
        const metav = row.values[1];
        switch (idv) {
            .text => |id| if (std.mem.eql(u8, id, "mnull")) {
                found_null = true;
                try t.expect(@as(@TypeOf(metav), metav).null_val == {});
            } else if (std.mem.eql(u8, id, "mempty")) {
                found_empty = true;
                switch (metav) {
                    .text => |sval| try t.expectEqualStrings("", sval),
                    else => return error.Unexpected,
                }
            },
            else => return error.Unexpected,
        }
    }
    try t.expect(found_null and found_empty);
}
