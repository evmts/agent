const std = @import("std");

/// Message role in the conversation
pub const Role = enum {
    user,
    assistant,
    system,
};

/// Message content - either simple text or structured parts
pub const Content = union(enum) {
    text: []const u8,
    parts: []Part,
};

/// Content part - text, file mention, or image
pub const Part = union(enum) {
    text: []const u8,
    file_mention: FileMention,
    image: Image,
};

/// File mention with optional content and line range
pub const FileMention = struct {
    path: []const u8,
    content: ?[]const u8 = null,
    line_start: ?u32 = null,
    line_end: ?u32 = null,
};

/// Image attachment
pub const Image = struct {
    path: []const u8,
    mime_type: []const u8,
    data: ?[]const u8 = null,
};

/// Tool call execution status
pub const ToolCallStatus = enum {
    pending,
    running,
    completed,
    failed,
    declined,
};

/// Tool execution result
pub const ToolResult = struct {
    output: []const u8,
    is_error: bool = false,
};

/// Tool call with execution tracking
pub const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    args: []const u8,
    result: ?ToolResult = null,
    status: ToolCallStatus = .pending,
    started_at: ?i64 = null,
    completed_at: ?i64 = null,

    /// Calculate duration in milliseconds
    pub fn duration_ms(self: ToolCall) ?u64 {
        if (self.started_at) |start| {
            if (self.completed_at) |end| {
                return @intCast(end - start);
            }
        }
        return null;
    }

    /// Free all allocated memory for this tool call
    pub fn deinit(self: *ToolCall, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.args);
        if (self.result) |r| {
            allocator.free(r.output);
        }
    }
};

/// A message in the conversation
pub const Message = struct {
    id: u64,
    role: Role,
    content: Content,
    timestamp: i64,
    tool_calls: std.ArrayList(ToolCall),

    /// Free all allocated memory for this message
    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        switch (self.content) {
            .text => |t| allocator.free(t),
            .parts => |parts| {
                for (parts) |part| {
                    switch (part) {
                        .text => |t| allocator.free(t),
                        .file_mention => |f| {
                            allocator.free(f.path);
                            if (f.content) |c| allocator.free(c);
                        },
                        .image => |i| {
                            allocator.free(i.path);
                            allocator.free(i.mime_type);
                            if (i.data) |d| allocator.free(d);
                        },
                    }
                }
                allocator.free(parts);
            },
        }
        for (self.tool_calls.items) |*tc| {
            tc.deinit(allocator);
        }
        self.tool_calls.deinit(allocator);
    }
};
