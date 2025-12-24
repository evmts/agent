const std = @import("std");
const protocol = @import("../client/protocol.zig");
const testing = std.testing;

test "parse text event with data" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"text\",\"data\":\"Hello, world!\"}";

    var event = try protocol.StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .text);
    try testing.expect(event.text.data != null);
    try testing.expectEqualStrings("Hello, world!", event.text.data.?);
}

test "parse text event without data" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"text\"}";

    var event = try protocol.StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .text);
    try testing.expect(event.text.data == null);
}

test "parse tool_call event" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"tool_call\",\"toolName\":\"grep\",\"toolId\":\"call_123\",\"args\":\"{\\\"pattern\\\":\\\"test\\\"}\"}";

    var event = try protocol.StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .tool_call);
    try testing.expect(event.tool_call.tool_name != null);
    try testing.expectEqualStrings("grep", event.tool_call.tool_name.?);
    try testing.expect(event.tool_call.tool_id != null);
    try testing.expectEqualStrings("call_123", event.tool_call.tool_id.?);
    try testing.expect(event.tool_call.args != null);
    try testing.expectEqualStrings("{\"pattern\":\"test\"}", event.tool_call.args.?);
}

test "parse tool_result event" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"tool_result\",\"toolId\":\"call_123\",\"toolOutput\":\"Result output\"}";

    var event = try protocol.StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .tool_result);
    try testing.expect(event.tool_result.tool_id != null);
    try testing.expectEqualStrings("call_123", event.tool_result.tool_id.?);
    try testing.expect(event.tool_result.tool_output != null);
    try testing.expectEqualStrings("Result output", event.tool_result.tool_output.?);
}

test "parse error event" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"error\",\"error\":\"Something went wrong\"}";

    var event = try protocol.StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .error_event);
    try testing.expect(event.error_event.error_msg != null);
    try testing.expectEqualStrings("Something went wrong", event.error_event.error_msg.?);
}

test "parse done event" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"done\"}";

    var event = try protocol.StreamEvent.parse(allocator, json);
    defer event.deinit(allocator);

    try testing.expect(event == .done);
}

test "parse event with missing type" {
    const allocator = testing.allocator;
    const json = "{\"data\":\"Hello\"}";

    const result = protocol.StreamEvent.parse(allocator, json);
    try testing.expectError(error.MissingType, result);
}

test "parse event with unknown type" {
    const allocator = testing.allocator;
    const json = "{\"type\":\"unknown\"}";

    const result = protocol.StreamEvent.parse(allocator, json);
    try testing.expectError(error.UnknownEventType, result);
}

test "parse malformed JSON" {
    const allocator = testing.allocator;
    const json = "{invalid json}";

    const result = protocol.StreamEvent.parse(allocator, json);
    try testing.expectError(error.UnexpectedToken, result);
}

test "SendMessageRequest toJson" {
    const allocator = testing.allocator;
    const req = protocol.SendMessageRequest{
        .message = "Hello",
        .model = "claude-3-5-sonnet-20241022",
        .agent_name = "build",
    };

    const json = try req.toJson(allocator);
    defer allocator.free(json);

    // Parse it back to verify structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try testing.expectEqualStrings("Hello", obj.get("message").?.string);
    try testing.expectEqualStrings("claude-3-5-sonnet-20241022", obj.get("model").?.string);
    try testing.expectEqualStrings("build", obj.get("agent_name").?.string);
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

    var session = try protocol.Session.parse(allocator, json);
    defer session.deinit(allocator);

    try testing.expectEqualStrings("session_123", session.id);
    try testing.expect(session.title != null);
    try testing.expectEqualStrings("Test Session", session.title.?);
    try testing.expectEqualStrings("claude-3-5-sonnet-20241022", session.model);
    try testing.expectEqualStrings("medium", session.reasoning_effort);
    try testing.expectEqualStrings("/home/user/project", session.directory);
    try testing.expectEqual(@as(i64, 1234567890), session.created_at);
}

test "CreateSessionRequest toJson" {
    const allocator = testing.allocator;
    const req = protocol.CreateSessionRequest{
        .directory = "/home/user/project",
        .model = "claude-3-5-sonnet-20241022",
    };

    const json = try req.toJson(allocator);
    defer allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"/home/user/project\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"claude-3-5-sonnet-20241022\"") != null);
}

test "UndoRequest toJson" {
    const allocator = testing.allocator;
    const req = protocol.UndoRequest{ .turns = 3 };

    const json = try req.toJson(allocator);
    defer allocator.free(json);

    try testing.expectEqualStrings("{\"turns\":3}", json);
}
