const std = @import("std");
const session = @import("session.zig");

/// Message status
pub const MessageStatus = enum {
    pending,
    streaming,
    completed,
    failed,
    aborted,

    pub fn toString(self: MessageStatus) []const u8 {
        return switch (self) {
            .pending => "pending",
            .streaming => "streaming",
            .completed => "completed",
            .failed => "failed",
            .aborted => "aborted",
        };
    }

    pub fn fromString(s: []const u8) ?MessageStatus {
        if (std.mem.eql(u8, s, "pending")) return .pending;
        if (std.mem.eql(u8, s, "streaming")) return .streaming;
        if (std.mem.eql(u8, s, "completed")) return .completed;
        if (std.mem.eql(u8, s, "failed")) return .failed;
        if (std.mem.eql(u8, s, "aborted")) return .aborted;
        return null;
    }
};

/// Message role
pub const MessageRole = enum {
    user,
    assistant,

    pub fn toString(self: MessageRole) []const u8 {
        return switch (self) {
            .user => "user",
            .assistant => "assistant",
        };
    }

    pub fn fromString(s: []const u8) ?MessageRole {
        if (std.mem.eql(u8, s, "user")) return .user;
        if (std.mem.eql(u8, s, "assistant")) return .assistant;
        return null;
    }
};

/// Message time tracking
pub const MessageTime = struct {
    created: i64,
    completed: ?i64 = null,
};

/// Model information
pub const ModelInfo = struct {
    provider_id: []const u8,
    model_id: []const u8,
};

/// Path information
pub const PathInfo = struct {
    cwd: []const u8,
    root: []const u8,
};

/// Token usage information
pub const TokenInfo = struct {
    input: u64 = 0,
    output: u64 = 0,
    reasoning: u64 = 0,
    cache_read: ?u64 = null,
    cache_write: ?u64 = null,

    pub fn total(self: TokenInfo) u64 {
        return self.input + self.output + self.reasoning;
    }
};

/// User message
pub const UserMessage = struct {
    id: []const u8,
    session_id: []const u8,
    role: MessageRole = .user,
    time: MessageTime,
    status: MessageStatus,
    thinking_text: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    agent: []const u8,
    model: ModelInfo,
    system: ?[]const u8 = null,
};

/// Assistant message
pub const AssistantMessage = struct {
    id: []const u8,
    session_id: []const u8,
    role: MessageRole = .assistant,
    time: MessageTime,
    status: MessageStatus,
    thinking_text: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    parent_id: []const u8,
    model_id: []const u8,
    provider_id: []const u8,
    mode: []const u8,
    path: PathInfo,
    cost: f64 = 0.0,
    tokens: TokenInfo,
    finish: ?[]const u8 = null,
    summary: bool = false,
};

/// Message union type
pub const Message = union(enum) {
    user: UserMessage,
    assistant: AssistantMessage,

    pub fn id(self: Message) []const u8 {
        return switch (self) {
            .user => |u| u.id,
            .assistant => |a| a.id,
        };
    }

    pub fn sessionId(self: Message) []const u8 {
        return switch (self) {
            .user => |u| u.session_id,
            .assistant => |a| a.session_id,
        };
    }

    pub fn role(self: Message) MessageRole {
        return switch (self) {
            .user => .user,
            .assistant => .assistant,
        };
    }

    pub fn status(self: Message) MessageStatus {
        return switch (self) {
            .user => |u| u.status,
            .assistant => |a| a.status,
        };
    }

    pub fn isUser(self: Message) bool {
        return self == .user;
    }

    pub fn isAssistant(self: Message) bool {
        return self == .assistant;
    }
};

/// Generate a message ID
pub fn generateMessageId(allocator: std.mem.Allocator) ![]const u8 {
    return session.generateId(allocator, "msg_");
}

test "generateMessageId creates valid ID" {
    const allocator = std.testing.allocator;
    const id = try generateMessageId(allocator);
    defer allocator.free(id);

    try std.testing.expect(std.mem.startsWith(u8, id, "msg_"));
    try std.testing.expectEqual(@as(usize, 15), id.len);
}
