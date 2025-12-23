const std = @import("std");
const session = @import("session.zig");

/// Part time tracking
pub const PartTime = struct {
    start: i64,
    end: ?i64 = null,
};

/// Tool status
pub const ToolStatus = enum {
    pending,
    running,
    completed,

    pub fn toString(self: ToolStatus) []const u8 {
        return switch (self) {
            .pending => "pending",
            .running => "running",
            .completed => "completed",
        };
    }

    pub fn fromString(s: []const u8) ?ToolStatus {
        if (std.mem.eql(u8, s, "pending")) return .pending;
        if (std.mem.eql(u8, s, "running")) return .running;
        if (std.mem.eql(u8, s, "completed")) return .completed;
        return null;
    }
};

/// Tool state - pending
pub const ToolStatePending = struct {
    status: ToolStatus = .pending,
    input: std.json.Value,
    raw: []const u8,
};

/// Tool state - running
pub const ToolStateRunning = struct {
    status: ToolStatus = .running,
    input: std.json.Value,
    title: ?[]const u8 = null,
    metadata: ?std.json.Value = null,
    time: PartTime,
};

/// Tool state - completed
pub const ToolStateCompleted = struct {
    status: ToolStatus = .completed,
    input: std.json.Value,
    output: []const u8,
    title: ?[]const u8 = null,
    metadata: ?std.json.Value = null,
    time: PartTime,
};

/// Tool state union
pub const ToolState = union(enum) {
    pending: ToolStatePending,
    running: ToolStateRunning,
    completed: ToolStateCompleted,

    pub fn getStatus(self: ToolState) ToolStatus {
        return switch (self) {
            .pending => .pending,
            .running => .running,
            .completed => .completed,
        };
    }

    pub fn getInput(self: ToolState) std.json.Value {
        return switch (self) {
            .pending => |p| p.input,
            .running => |r| r.input,
            .completed => |c| c.input,
        };
    }
};

/// Part type
pub const PartType = enum {
    text,
    reasoning,
    tool,
    file,

    pub fn toString(self: PartType) []const u8 {
        return switch (self) {
            .text => "text",
            .reasoning => "reasoning",
            .tool => "tool",
            .file => "file",
        };
    }

    pub fn fromString(s: []const u8) ?PartType {
        if (std.mem.eql(u8, s, "text")) return .text;
        if (std.mem.eql(u8, s, "reasoning")) return .reasoning;
        if (std.mem.eql(u8, s, "tool")) return .tool;
        if (std.mem.eql(u8, s, "file")) return .file;
        return null;
    }
};

/// Text part
pub const TextPart = struct {
    id: []const u8,
    session_id: []const u8,
    message_id: []const u8,
    part_type: PartType = .text,
    text: []const u8,
    time: ?PartTime = null,
};

/// Reasoning part
pub const ReasoningPart = struct {
    id: []const u8,
    session_id: []const u8,
    message_id: []const u8,
    part_type: PartType = .reasoning,
    text: []const u8,
    time: PartTime,
};

/// Tool part
pub const ToolPart = struct {
    id: []const u8,
    session_id: []const u8,
    message_id: []const u8,
    part_type: PartType = .tool,
    tool: []const u8,
    state: ToolState,
};

/// File part
pub const FilePart = struct {
    id: []const u8,
    session_id: []const u8,
    message_id: []const u8,
    part_type: PartType = .file,
    mime: []const u8,
    url: []const u8,
    filename: ?[]const u8 = null,
};

/// Part union type
pub const Part = union(enum) {
    text: TextPart,
    reasoning: ReasoningPart,
    tool: ToolPart,
    file: FilePart,

    pub fn id(self: Part) []const u8 {
        return switch (self) {
            .text => |t| t.id,
            .reasoning => |r| r.id,
            .tool => |t| t.id,
            .file => |f| f.id,
        };
    }

    pub fn sessionId(self: Part) []const u8 {
        return switch (self) {
            .text => |t| t.session_id,
            .reasoning => |r| r.session_id,
            .tool => |t| t.session_id,
            .file => |f| f.session_id,
        };
    }

    pub fn messageId(self: Part) []const u8 {
        return switch (self) {
            .text => |t| t.message_id,
            .reasoning => |r| r.message_id,
            .tool => |t| t.message_id,
            .file => |f| f.message_id,
        };
    }

    pub fn partType(self: Part) PartType {
        return switch (self) {
            .text => .text,
            .reasoning => .reasoning,
            .tool => .tool,
            .file => .file,
        };
    }

    pub fn isText(self: Part) bool {
        return self == .text;
    }

    pub fn isReasoning(self: Part) bool {
        return self == .reasoning;
    }

    pub fn isTool(self: Part) bool {
        return self == .tool;
    }

    pub fn isFile(self: Part) bool {
        return self == .file;
    }
};

/// Generate a part ID
pub fn generatePartId(allocator: std.mem.Allocator) ![]const u8 {
    return session.generateId(allocator, "prt_");
}

test "generatePartId creates valid ID" {
    const allocator = std.testing.allocator;
    const id = try generatePartId(allocator);
    defer allocator.free(id);

    try std.testing.expect(std.mem.startsWith(u8, id, "prt_"));
    try std.testing.expectEqual(@as(usize, 15), id.len);
}
