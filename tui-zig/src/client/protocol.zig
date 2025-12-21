const std = @import("std");

/// Stream events from the Plue API server
/// Matches the server-side StreamEvent in server/src/ai/types.zig
pub const StreamEvent = union(enum) {
    text: TextEvent,
    tool_call: ToolCallEvent,
    tool_result: ToolResultEvent,
    error_event: ErrorEvent,
    done,

    /// Parse a stream event from JSON
    pub fn parse(allocator: std.mem.Allocator, json_str: []const u8) !StreamEvent {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json_str,
            .{},
        );
        defer parsed.deinit();

        const obj = parsed.value.object;
        const event_type = obj.get("type") orelse return error.MissingType;
        const type_str = event_type.string;

        if (std.mem.eql(u8, type_str, "text")) {
            const data = if (obj.get("data")) |d| d.string else null;
            return .{ .text = .{ .data = if (data) |d| try allocator.dupe(u8, d) else null } };
        } else if (std.mem.eql(u8, type_str, "tool_call")) {
            return .{ .tool_call = .{
                .tool_name = if (obj.get("toolName")) |n| try allocator.dupe(u8, n.string) else null,
                .tool_id = if (obj.get("toolId")) |id| try allocator.dupe(u8, id.string) else null,
                .args = if (obj.get("args")) |a| try allocator.dupe(u8, a.string) else null,
            } };
        } else if (std.mem.eql(u8, type_str, "tool_result")) {
            return .{ .tool_result = .{
                .tool_id = if (obj.get("toolId")) |id| try allocator.dupe(u8, id.string) else null,
                .tool_output = if (obj.get("toolOutput")) |o| try allocator.dupe(u8, o.string) else null,
            } };
        } else if (std.mem.eql(u8, type_str, "error")) {
            return .{ .error_event = .{
                .error_msg = if (obj.get("error")) |e| try allocator.dupe(u8, e.string) else null,
            } };
        } else if (std.mem.eql(u8, type_str, "done")) {
            return .done;
        }

        return error.UnknownEventType;
    }

    /// Free all allocated memory in this event
    pub fn deinit(self: *StreamEvent, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .text => |*t| {
                if (t.data) |d| allocator.free(d);
            },
            .tool_call => |*tc| {
                if (tc.tool_name) |n| allocator.free(n);
                if (tc.tool_id) |id| allocator.free(id);
                if (tc.args) |a| allocator.free(a);
            },
            .tool_result => |*tr| {
                if (tr.tool_id) |id| allocator.free(id);
                if (tr.tool_output) |o| allocator.free(o);
            },
            .error_event => |*e| {
                if (e.error_msg) |m| allocator.free(m);
            },
            .done => {},
        }
    }
};

pub const TextEvent = struct {
    data: ?[]const u8,
};

pub const ToolCallEvent = struct {
    tool_name: ?[]const u8,
    tool_id: ?[]const u8,
    args: ?[]const u8, // JSON string
};

pub const ToolResultEvent = struct {
    tool_id: ?[]const u8,
    tool_output: ?[]const u8,
};

pub const ErrorEvent = struct {
    error_msg: ?[]const u8,
};

/// Request to send a message to the agent
pub const SendMessageRequest = struct {
    message: []const u8,
    model: ?[]const u8 = null,
    agent_name: ?[]const u8 = null,

    pub fn toJson(self: SendMessageRequest, allocator: std.mem.Allocator) ![]const u8 {
        if (self.model) |m| {
            if (self.agent_name) |a| {
                return std.fmt.allocPrint(allocator, "{{\"message\":\"{s}\",\"model\":\"{s}\",\"agent_name\":\"{s}\"}}", .{ self.message, m, a });
            } else {
                return std.fmt.allocPrint(allocator, "{{\"message\":\"{s}\",\"model\":\"{s}\"}}", .{ self.message, m });
            }
        } else {
            if (self.agent_name) |a| {
                return std.fmt.allocPrint(allocator, "{{\"message\":\"{s}\",\"agent_name\":\"{s}\"}}", .{ self.message, a });
            } else {
                return std.fmt.allocPrint(allocator, "{{\"message\":\"{s}\"}}", .{self.message});
            }
        }
    }
};

/// Agent session
pub const Session = struct {
    id: []const u8,
    title: ?[]const u8,
    model: []const u8,
    reasoning_effort: []const u8,
    directory: []const u8,
    created_at: i64,

    pub fn parse(allocator: std.mem.Allocator, json_str: []const u8) !Session {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json_str,
            .{},
        );
        defer parsed.deinit();

        const obj = parsed.value.object;
        return .{
            .id = try allocator.dupe(u8, obj.get("id").?.string),
            .title = if (obj.get("title")) |t| try allocator.dupe(u8, t.string) else null,
            .model = try allocator.dupe(u8, obj.get("model").?.string),
            .reasoning_effort = try allocator.dupe(u8, obj.get("reasoning_effort").?.string),
            .directory = try allocator.dupe(u8, obj.get("directory").?.string),
            .created_at = obj.get("created_at").?.integer,
        };
    }

    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        if (self.title) |t| allocator.free(t);
        allocator.free(self.model);
        allocator.free(self.reasoning_effort);
        allocator.free(self.directory);
    }
};

/// Request to create a session
pub const CreateSessionRequest = struct {
    directory: []const u8,
    model: []const u8,

    pub fn toJson(self: CreateSessionRequest, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{{\"directory\":\"{s}\",\"model\":\"{s}\"}}", .{ self.directory, self.model });
    }
};

/// Request to update a session
pub const UpdateSessionRequest = struct {
    model: ?[]const u8 = null,
    reasoning_effort: ?[]const u8 = null,

    pub fn toJson(self: UpdateSessionRequest, allocator: std.mem.Allocator) ![]const u8 {
        if (self.model) |m| {
            if (self.reasoning_effort) |r| {
                return std.fmt.allocPrint(allocator, "{{\"model\":\"{s}\",\"reasoning_effort\":\"{s}\"}}", .{ m, r });
            } else {
                return std.fmt.allocPrint(allocator, "{{\"model\":\"{s}\"}}", .{m});
            }
        } else {
            if (self.reasoning_effort) |r| {
                return std.fmt.allocPrint(allocator, "{{\"reasoning_effort\":\"{s}\"}}", .{r});
            } else {
                return std.fmt.allocPrint(allocator, "{{}}", .{});
            }
        }
    }
};

/// Request to undo turns
pub const UndoRequest = struct {
    turns: u32,

    pub fn toJson(self: UndoRequest, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{{\"turns\":{d}}}", .{self.turns});
    }
};

// Tests
const testing = std.testing;

test "parse text event with data" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"text\",\"data\":\"Hello, world!\"}";

    var event = try StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .text);
    try testing.expect(event.text.data != null);
    try testing.expectEqualStrings("Hello, world!", event.text.data.?);
}

test "parse text event without data" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"text\"}";

    var event = try StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .text);
    try testing.expect(event.text.data == null);
}

test "parse tool_call event" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"tool_call\",\"toolName\":\"grep\",\"toolId\":\"call_123\",\"args\":\"{\\\"pattern\\\":\\\"test\\\"}\"}";

    var event = try StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .tool_call);
    try testing.expect(event.tool_call.tool_name != null);
    try testing.expectEqualStrings("grep", event.tool_call.tool_name.?);
    try testing.expect(event.tool_call.tool_id != null);
    try testing.expectEqualStrings("call_123", event.tool_call.tool_id.?);
    try testing.expect(event.tool_call.args != null);
    try testing.expectEqualStrings("{\"pattern\":\"test\"}", event.tool_call.args.?);
}

test "parse error event" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"error\",\"error\":\"Something went wrong\"}";

    var event = try StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .error_event);
    try testing.expect(event.error_event.error_msg != null);
    try testing.expectEqualStrings("Something went wrong", event.error_event.error_msg.?);
}

test "parse done event" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"done\"}";

    var event = try StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .done);
}

test "parse event with unknown type" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"unknown\"}";

    const result = StreamEvent.parse(allocator, json);
    try testing.expectError(error.UnknownEventType, result);
}

test "SendMessageRequest toJson" {
    const allocator = testing.allocator;
    const req = SendMessageRequest{
        .message = "Hello",
        .model = "claude-3-5-sonnet-20241022",
        .agent_name = "build",
    };

    const json = try req.toJson(allocator);
    defer allocator.free(json);

    // Verify it contains the right fields
    try testing.expect(std.mem.indexOf(u8, json, "\"message\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"Hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"model\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"claude-3-5-sonnet-20241022\"") != null);
}

test "Session parse" {
    const allocator = testing.allocator;
    const json =
        \\{
        \\  "id": "session_123",
        \\  "title": "Test Session",
        \\  "model": "claude-3-5-sonnet-20241022",
        \\  "reasoning_effort": "medium",
        \\  "directory": "/home/user/project",
        \\  "created_at": 1234567890
        \\}
    ;

    var session = try Session.parse(allocator, json);
    defer session.deinit(allocator);

    try testing.expectEqualStrings("session_123", session.id);
    try testing.expect(session.title != null);
    try testing.expectEqualStrings("Test Session", session.title.?);
    try testing.expectEqualStrings("claude-3-5-sonnet-20241022", session.model);
    try testing.expectEqualStrings("medium", session.reasoning_effort);
    try testing.expectEqualStrings("/home/user/project", session.directory);
    try testing.expectEqual(@as(i64, 1234567890), session.created_at);
}
