const std = @import("std");
const models = @import("models/mod.zig");

/// File diff information
pub const FileDiff = struct {
    path: []const u8,
    change_type: ChangeType,
    before_content: ?[]const u8 = null,
    after_content: ?[]const u8 = null,
    added_lines: u32 = 0,
    deleted_lines: u32 = 0,

    pub const ChangeType = enum {
        added,
        modified,
        deleted,

        pub fn toString(self: ChangeType) []const u8 {
            return switch (self) {
                .added => "added",
                .modified => "modified",
                .deleted => "deleted",
            };
        }
    };
};

/// Snapshot information
pub const SnapshotInfo = struct {
    change_id: []const u8,
    commit_id: []const u8,
    description: []const u8,
    timestamp: i64,
    is_empty: bool,
};

/// Operation information
pub const OperationInfo = struct {
    id: []const u8,
    description: []const u8,
    timestamp: i64,
};

/// File time tracker for read-before-write safety
pub const FileTimeTracker = struct {
    read_times: std.StringHashMap(i64),
    mod_times: std.StringHashMap(i64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FileTimeTracker {
        return .{
            .read_times = std.StringHashMap(i64).init(allocator),
            .mod_times = std.StringHashMap(i64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FileTimeTracker) void {
        // Free keys - only from read_times since the same keys are shared with mod_times
        var read_iter = self.read_times.keyIterator();
        while (read_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.read_times.deinit();
        self.mod_times.deinit();
    }

    /// Record a file read
    pub fn recordRead(self: *FileTimeTracker, path: []const u8, read_time: i64, mod_time: i64) !void {
        // Check if already tracked
        if (self.read_times.contains(path)) {
            try self.read_times.put(path, read_time);
            try self.mod_times.put(path, mod_time);
        } else {
            const path_copy = try self.allocator.dupe(u8, path);
            try self.read_times.put(path_copy, read_time);
            try self.mod_times.put(path_copy, mod_time);
        }
    }

    /// Check if file was read before
    pub fn wasReadBefore(self: *FileTimeTracker, path: []const u8) bool {
        return self.read_times.contains(path);
    }

    /// Get last known modification time
    pub fn getLastModTime(self: *FileTimeTracker, path: []const u8) ?i64 {
        return self.mod_times.get(path);
    }

    /// Get read time
    pub fn getReadTime(self: *FileTimeTracker, path: []const u8) ?i64 {
        return self.read_times.get(path);
    }

    /// Clear tracking for a file
    pub fn clear(self: *FileTimeTracker, path: []const u8) void {
        // Free the key once (shared between both maps)
        if (self.read_times.fetchRemove(path)) |entry| {
            self.allocator.free(entry.key);
        }
        // Just remove from mod_times, don't free (same key as read_times)
        _ = self.mod_times.remove(path);
    }
};

/// Message with parts
pub const MessageWithParts = struct {
    message: models.Message,
    parts: []models.Part,
};

/// Active task tracking
pub const ActiveTasks = struct {
    tasks: std.StringHashMap(TaskInfo),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    pub const TaskInfo = struct {
        session_id: []const u8,
        started_at: i64,
        cancelled: bool,
    };

    pub fn init(allocator: std.mem.Allocator) ActiveTasks {
        return .{
            .tasks = std.StringHashMap(TaskInfo).init(allocator),
            .mutex = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ActiveTasks) void {
        var iter = self.tasks.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.tasks.deinit();
    }

    /// Register an active task
    pub fn register(self: *ActiveTasks, session_id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const id_copy = try self.allocator.dupe(u8, session_id);
        try self.tasks.put(id_copy, .{
            .session_id = id_copy,
            .started_at = std.time.milliTimestamp(),
            .cancelled = false,
        });
    }

    /// Cancel a task
    pub fn cancel(self: *ActiveTasks, session_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.tasks.getPtr(session_id)) |task| {
            task.cancelled = true;
            return true;
        }
        return false;
    }

    /// Check if task is cancelled
    pub fn isCancelled(self: *ActiveTasks, session_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.tasks.get(session_id)) |task| {
            return task.cancelled;
        }
        return false;
    }

    /// Remove a task
    pub fn remove(self: *ActiveTasks, session_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.tasks.fetchRemove(session_id)) |entry| {
            self.allocator.free(entry.key);
        }
    }

    /// Check if task is active
    pub fn isActive(self: *ActiveTasks, session_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.tasks.contains(session_id);
    }
};

/// Session file trackers
pub const SessionTrackers = struct {
    trackers: std.StringHashMap(*FileTimeTracker),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SessionTrackers {
        return .{
            .trackers = std.StringHashMap(*FileTimeTracker).init(allocator),
            .mutex = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SessionTrackers) void {
        var iter = self.trackers.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.trackers.deinit();
    }

    /// Get or create a tracker for a session
    pub fn getOrCreate(self: *SessionTrackers, session_id: []const u8) !*FileTimeTracker {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.trackers.get(session_id)) |tracker| {
            return tracker;
        }

        const tracker = try self.allocator.create(FileTimeTracker);
        tracker.* = FileTimeTracker.init(self.allocator);
        const id_copy = try self.allocator.dupe(u8, session_id);
        try self.trackers.put(id_copy, tracker);
        return tracker;
    }

    /// Remove a tracker
    pub fn remove(self: *SessionTrackers, session_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.trackers.fetchRemove(session_id)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
            self.allocator.free(entry.key);
        }
    }
};

test "FileTimeTracker tracks reads" {
    const allocator = std.testing.allocator;
    var tracker = FileTimeTracker.init(allocator);
    defer tracker.deinit();

    try tracker.recordRead("/test/file.txt", 1000, 900);

    try std.testing.expect(tracker.wasReadBefore("/test/file.txt"));
    try std.testing.expect(!tracker.wasReadBefore("/other/file.txt"));
    try std.testing.expectEqual(@as(?i64, 900), tracker.getLastModTime("/test/file.txt"));
}

test "ActiveTasks tracks and cancels" {
    const allocator = std.testing.allocator;
    var tasks = ActiveTasks.init(allocator);
    defer tasks.deinit();

    try tasks.register("session_1");
    try std.testing.expect(tasks.isActive("session_1"));
    try std.testing.expect(!tasks.isCancelled("session_1"));

    _ = tasks.cancel("session_1");
    try std.testing.expect(tasks.isCancelled("session_1"));

    tasks.remove("session_1");
    try std.testing.expect(!tasks.isActive("session_1"));
}
