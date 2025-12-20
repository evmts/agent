const std = @import("std");

/// Session time tracking
pub const SessionTime = struct {
    created: i64,
    updated: i64,
    archived: ?i64 = null,
};

/// Session summary (changes made)
pub const SessionSummary = struct {
    additions: u32 = 0,
    deletions: u32 = 0,
    files: u32 = 0,
};

/// Revert information
pub const RevertInfo = struct {
    message_id: []const u8,
    part_id: ?[]const u8 = null,
    snapshot: ?[]const u8 = null,
};

/// Compaction information
pub const CompactionInfo = struct {
    original_count: u32,
    compacted_at: i64,
};

/// Ghost commit tracking
pub const GhostCommitInfo = struct {
    enabled: bool = false,
    current_turn: u32 = 0,
    commits: []const []const u8 = &.{},
};

/// Reasoning effort levels
pub const ReasoningEffort = enum {
    minimal,
    low,
    medium,
    high,

    pub fn toString(self: ReasoningEffort) []const u8 {
        return switch (self) {
            .minimal => "minimal",
            .low => "low",
            .medium => "medium",
            .high => "high",
        };
    }

    pub fn fromString(s: []const u8) ?ReasoningEffort {
        if (std.mem.eql(u8, s, "minimal")) return .minimal;
        if (std.mem.eql(u8, s, "low")) return .low;
        if (std.mem.eql(u8, s, "medium")) return .medium;
        if (std.mem.eql(u8, s, "high")) return .high;
        return null;
    }
};

/// Agent conversation session
pub const Session = struct {
    id: []const u8,
    project_id: []const u8,
    directory: []const u8,
    title: []const u8,
    version: []const u8,
    time: SessionTime,
    parent_id: ?[]const u8 = null,
    fork_point: ?[]const u8 = null,
    summary: ?SessionSummary = null,
    revert: ?RevertInfo = null,
    compaction: ?CompactionInfo = null,
    token_count: u64 = 0,
    bypass_mode: bool = false,
    model: ?[]const u8 = null,
    reasoning_effort: ?ReasoningEffort = null,
    ghost_commit: ?GhostCommitInfo = null,
    plugins: []const []const u8 = &.{},

    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.project_id);
        allocator.free(self.directory);
        allocator.free(self.title);
        allocator.free(self.version);
        if (self.parent_id) |pid| allocator.free(pid);
        if (self.fork_point) |fp| allocator.free(fp);
        if (self.model) |m| allocator.free(m);
        for (self.plugins) |p| allocator.free(p);
    }
};

/// Options for creating a new session
pub const CreateSessionOptions = struct {
    directory: []const u8,
    title: ?[]const u8 = null,
    parent_id: ?[]const u8 = null,
    bypass_mode: bool = false,
    model: ?[]const u8 = null,
    reasoning_effort: ?ReasoningEffort = null,
    plugins: []const []const u8 = &.{},
};

/// Options for updating a session
pub const UpdateSessionOptions = struct {
    title: ?[]const u8 = null,
    archived: ?bool = null,
    model: ?[]const u8 = null,
    reasoning_effort: ?ReasoningEffort = null,
};

/// Generate a session ID
pub fn generateSessionId(allocator: std.mem.Allocator) ![]const u8 {
    return generateId(allocator, "ses_");
}

/// Generate an ID with prefix
pub fn generateId(allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {
            seed = @intCast(std.time.milliTimestamp());
        };
        break :blk seed;
    });

    const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    const id_len = 11;

    var result = try allocator.alloc(u8, prefix.len + id_len);
    @memcpy(result[0..prefix.len], prefix);

    for (prefix.len..result.len) |i| {
        result[i] = charset[prng.random().intRangeAtMost(usize, 0, charset.len - 1)];
    }

    return result;
}

test "generateSessionId creates valid ID" {
    const allocator = std.testing.allocator;
    const id = try generateSessionId(allocator);
    defer allocator.free(id);

    try std.testing.expect(std.mem.startsWith(u8, id, "ses_"));
    try std.testing.expectEqual(@as(usize, 15), id.len);
}
