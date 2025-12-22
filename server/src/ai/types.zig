const std = @import("std");

/// File time tracker for read-before-write safety
pub const FileTimeTracker = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    file_times: std.StringHashMap(i128),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .file_times = std.StringHashMap(i128).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.file_times.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.file_times.deinit();
    }

    pub fn recordRead(self: *Self, path: []const u8, mod_time: i128) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        try self.file_times.put(owned_path, mod_time);
    }

    pub fn getLastReadTime(self: *const Self, path: []const u8) ?i128 {
        return self.file_times.get(path);
    }

    pub fn hasBeenRead(self: *const Self, path: []const u8) bool {
        return self.file_times.contains(path);
    }
};

/// Session trackers for managing state per session
pub const SessionTrackers = struct {
    allocator: std.mem.Allocator,
    trackers: std.StringHashMap(FileTimeTracker),

    pub fn init(allocator: std.mem.Allocator) SessionTrackers {
        return .{
            .allocator = allocator,
            .trackers = std.StringHashMap(FileTimeTracker).init(allocator),
        };
    }

    pub fn getOrCreate(self: *SessionTrackers, session_id: []const u8) !*FileTimeTracker {
        if (self.trackers.getPtr(session_id)) |tracker| {
            return tracker;
        }
        const owned_id = try self.allocator.dupe(u8, session_id);
        try self.trackers.put(owned_id, FileTimeTracker.init(self.allocator));
        return self.trackers.getPtr(session_id).?;
    }
};

/// Active tasks tracking
pub const ActiveTasks = struct {
    allocator: std.mem.Allocator,
    tasks: std.StringHashMap(TaskInfo),

    pub const TaskInfo = struct {
        description: []const u8,
        started_at: i64,
    };

    pub fn init(allocator: std.mem.Allocator) ActiveTasks {
        return .{
            .allocator = allocator,
            .tasks = std.StringHashMap(TaskInfo).init(allocator),
        };
    }
};

/// File diff information
pub const FileDiff = struct {
    path: []const u8,
    before: ?[]const u8,
    after: ?[]const u8,
    change_type: ChangeType,

    pub const ChangeType = enum {
        added,
        modified,
        deleted,
    };
};

/// Snapshot information
pub const SnapshotInfo = struct {
    id: []const u8,
    timestamp: i64,
    description: ?[]const u8,
};

/// Event bus for pub/sub
pub const EventBus = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EventBus {
        return .{ .allocator = allocator };
    }

    pub fn emit(self: *EventBus, event: Event) void {
        _ = self;
        _ = event;
        // TODO: Implement event dispatch
    }
};

/// Event type
pub const EventType = enum {
    message_created,
    message_updated,
    tool_started,
    tool_completed,
    file_changed,
    session_created,
    session_updated,
};

/// Event structure
pub const Event = struct {
    event_type: EventType,
    session_id: ?[]const u8,
    data: ?[]const u8,
};

/// Events emitted during agent streaming (for HTTP layer)
/// These map to the TypeScript StreamEvent type
pub const StreamEvent = union(enum) {
    text: TextEvent,
    tool_call: ToolCallEvent,
    tool_result: ToolResultEvent,
    error_event: ErrorEvent,
    done: void,

    pub const TextEvent = struct {
        data: ?[]const u8 = null,
    };

    pub const ToolCallEvent = struct {
        tool_name: ?[]const u8 = null,
        tool_id: ?[]const u8 = null,
        args: ?[]const u8 = null, // JSON string
    };

    pub const ToolResultEvent = struct {
        tool_id: ?[]const u8 = null,
        tool_output: ?[]const u8 = null,
    };

    pub const ErrorEvent = struct {
        message: ?[]const u8 = null,
    };

    /// Escape a string for JSON (simple implementation)
    fn escapeJsonString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        try result.append(allocator, '"');
        for (input) |char| {
            switch (char) {
                '"' => try result.appendSlice(allocator, "\\\""),
                '\\' => try result.appendSlice(allocator, "\\\\"),
                '\n' => try result.appendSlice(allocator, "\\n"),
                '\r' => try result.appendSlice(allocator, "\\r"),
                '\t' => try result.appendSlice(allocator, "\\t"),
                else => try result.append(allocator, char),
            }
        }
        try result.append(allocator, '"');
        return result.toOwnedSlice(allocator);
    }

    /// Serialize event to JSON for SSE streaming
    pub fn toJson(self: StreamEvent, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.ArrayList(u8){};
        errdefer list.deinit(allocator);

        try list.appendSlice(allocator, "{\"type\":\"");
        switch (self) {
            .text => |t| {
                try list.appendSlice(allocator, "text\"");
                if (t.data) |data| {
                    try list.appendSlice(allocator, ",\"data\":");
                    const escaped = try escapeJsonString(allocator, data);
                    defer allocator.free(escaped);
                    try list.appendSlice(allocator, escaped);
                }
            },
            .tool_call => |tc| {
                try list.appendSlice(allocator, "tool_call\"");
                if (tc.tool_name) |name| {
                    try list.appendSlice(allocator, ",\"toolName\":");
                    const escaped = try escapeJsonString(allocator, name);
                    defer allocator.free(escaped);
                    try list.appendSlice(allocator, escaped);
                }
                if (tc.tool_id) |id| {
                    try list.appendSlice(allocator, ",\"toolId\":");
                    const escaped = try escapeJsonString(allocator, id);
                    defer allocator.free(escaped);
                    try list.appendSlice(allocator, escaped);
                }
                if (tc.args) |args| {
                    try list.appendSlice(allocator, ",\"args\":");
                    try list.appendSlice(allocator, args); // Already JSON
                }
            },
            .tool_result => |tr| {
                try list.appendSlice(allocator, "tool_result\"");
                if (tr.tool_id) |id| {
                    try list.appendSlice(allocator, ",\"toolId\":");
                    const escaped = try escapeJsonString(allocator, id);
                    defer allocator.free(escaped);
                    try list.appendSlice(allocator, escaped);
                }
                if (tr.tool_output) |output| {
                    try list.appendSlice(allocator, ",\"toolOutput\":");
                    const escaped = try escapeJsonString(allocator, output);
                    defer allocator.free(escaped);
                    try list.appendSlice(allocator, escaped);
                }
            },
            .error_event => |e| {
                try list.appendSlice(allocator, "error\"");
                if (e.message) |msg| {
                    try list.appendSlice(allocator, ",\"error\":");
                    const escaped = try escapeJsonString(allocator, msg);
                    defer allocator.free(escaped);
                    try list.appendSlice(allocator, escaped);
                }
            },
            .done => {
                try list.appendSlice(allocator, "done\"");
            },
        }
        try list.append(allocator, '}');

        return list.toOwnedSlice(allocator);
    }
};

/// Options for running an agent
pub const AgentOptions = struct {
    model_id: []const u8,
    agent_name: []const u8,
    working_dir: []const u8,
    session_id: ?[]const u8 = null,
};

/// Agent mode
pub const AgentMode = enum {
    primary,
    subagent,
};

/// Agent configuration
pub const AgentConfig = struct {
    name: []const u8,
    description: []const u8,
    mode: AgentMode,
    system_prompt: []const u8,
    temperature: f32,
    top_p: f32,
    tools_enabled: ToolsEnabled,
    allowed_shell_patterns: ?[]const []const u8,

    pub const ToolsEnabled = struct {
        grep: bool = true,
        read_file: bool = true,
        write_file: bool = true,
        multiedit: bool = true,
        web_fetch: bool = true,
        github: bool = true,
    };
};

/// Tool context passed to tool implementations
pub const ToolContext = struct {
    session_id: ?[]const u8,
    working_dir: []const u8,
    allocator: std.mem.Allocator,
    file_tracker: ?*FileTimeTracker = null,
};

/// Tool execution errors
pub const ToolError = error{
    SessionNotFound,
    ToolExecutionFailed,
    InvalidToolParameters,
    FileNotFound,
    FileOutsideCwd,
    PathTraversal,
    ReadBeforeWriteViolation,
    FileModifiedSinceRead,
    HttpRequestFailed,
    ResponseTooLarge,
    GitHubCommandNotAllowed,
    PtySessionNotFound,
    ApiError,
    OutOfMemory,
    Overflow,
    InvalidCharacter,
    NoSpaceLeft,
    ConnectionRefused,
    ConnectionTimedOut,
    Unexpected,
    ProcessSpawnFailed,
    InvalidPath,
    AccessDenied,
};

/// Callbacks for streaming agent execution
pub const StreamCallbacks = struct {
    on_event: *const fn (StreamEvent, ?*anyopaque) void,
    context: ?*anyopaque,
};

test "StreamEvent.toJson text event" {
    const allocator = std.testing.allocator;
    const event = StreamEvent{ .text = .{ .data = "hello" } };
    const json = try event.toJson(allocator);
    defer allocator.free(json);
    try std.testing.expectEqualStrings("{\"type\":\"text\",\"data\":\"hello\"}", json);
}

test "StreamEvent.toJson done event" {
    const allocator = std.testing.allocator;
    const event = StreamEvent{ .done = {} };
    const json = try event.toJson(allocator);
    defer allocator.free(json);
    try std.testing.expectEqualStrings("{\"type\":\"done\"}", json);
}

test "FileTimeTracker" {
    var tracker = FileTimeTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.recordRead("/test/file.txt", 12345);
    try std.testing.expect(tracker.hasBeenRead("/test/file.txt"));
    try std.testing.expectEqual(@as(i128, 12345), tracker.getLastReadTime("/test/file.txt").?);
}
