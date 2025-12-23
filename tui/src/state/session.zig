const std = @import("std");

/// Reasoning effort level for Claude models
pub const ReasoningEffort = enum {
    minimal,
    low,
    medium,
    high,

    /// Convert to string representation
    pub fn toString(self: ReasoningEffort) []const u8 {
        return switch (self) {
            .minimal => "minimal",
            .low => "low",
            .medium => "medium",
            .high => "high",
        };
    }

    /// Parse from string representation
    pub fn fromString(s: []const u8) ?ReasoningEffort {
        if (std.mem.eql(u8, s, "minimal")) return .minimal;
        if (std.mem.eql(u8, s, "low")) return .low;
        if (std.mem.eql(u8, s, "medium")) return .medium;
        if (std.mem.eql(u8, s, "high")) return .high;
        return null;
    }
};

/// Session metadata
pub const Session = struct {
    id: []const u8,
    title: ?[]const u8,
    model: []const u8,
    reasoning_effort: ReasoningEffort,
    directory: []const u8,
    created_at: i64,
    updated_at: i64,

    /// Free all allocated memory for this session
    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        if (self.title) |t| allocator.free(t);
        allocator.free(self.model);
        allocator.free(self.directory);
    }
};
