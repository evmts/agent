const std = @import("std");
const testing = std.testing;

// Import modules configured in build.zig
const types = @import("types");
const session = @import("session");
const message = @import("message");
const conversation = @import("conversation");

test "TokenUsage.total() calculation" {
    const usage = types.TokenUsage{
        .input = 100,
        .output = 200,
        .cached = 50,
    };

    try testing.expectEqual(@as(u64, 300), usage.total());
}

test "ReasoningEffort.toString()" {
    try testing.expectEqualStrings("minimal", session.ReasoningEffort.minimal.toString());
    try testing.expectEqualStrings("low", session.ReasoningEffort.low.toString());
    try testing.expectEqualStrings("medium", session.ReasoningEffort.medium.toString());
    try testing.expectEqualStrings("high", session.ReasoningEffort.high.toString());
}

test "ReasoningEffort.fromString()" {
    try testing.expectEqual(session.ReasoningEffort.minimal, session.ReasoningEffort.fromString("minimal").?);
    try testing.expectEqual(session.ReasoningEffort.low, session.ReasoningEffort.fromString("low").?);
    try testing.expectEqual(session.ReasoningEffort.medium, session.ReasoningEffort.fromString("medium").?);
    try testing.expectEqual(session.ReasoningEffort.high, session.ReasoningEffort.fromString("high").?);
    try testing.expectEqual(@as(?session.ReasoningEffort, null), session.ReasoningEffort.fromString("invalid"));
}

test "Message creation and deinit" {
    const allocator = testing.allocator;

    const content = try allocator.dupe(u8, "Hello, world!");
    var msg = message.Message{
        .id = 1,
        .role = .user,
        .content = .{ .text = content },
        .timestamp = std.time.timestamp(),
        .tool_calls = std.ArrayList(message.ToolCall){},
    };

    // Should not leak memory
    msg.deinit(allocator);
}

test "Message with tool calls" {
    const allocator = testing.allocator;

    var msg = message.Message{
        .id = 1,
        .role = .assistant,
        .content = .{ .text = try allocator.dupe(u8, "Running tool...") },
        .timestamp = std.time.timestamp(),
        .tool_calls = std.ArrayList(message.ToolCall){},
    };

    const tool_call = message.ToolCall{
        .id = try allocator.dupe(u8, "tc_123"),
        .name = try allocator.dupe(u8, "grep"),
        .args = try allocator.dupe(u8, "{\"pattern\": \"test\"}"),
        .status = .running,
        .started_at = std.time.timestamp(),
    };

    try msg.tool_calls.append(allocator, tool_call);

    // Should not leak memory
    msg.deinit(allocator);
}

test "ToolCall.duration_ms()" {
    const tool_call = message.ToolCall{
        .id = "tc_123",
        .name = "grep",
        .args = "{}",
        .started_at = 1000,
        .completed_at = 1500,
    };

    try testing.expectEqual(@as(?u64, 500), tool_call.duration_ms());

    // No duration if not completed
    const pending = message.ToolCall{
        .id = "tc_456",
        .name = "read",
        .args = "{}",
        .started_at = 1000,
    };

    try testing.expectEqual(@as(?u64, null), pending.duration_ms());
}

test "Conversation lifecycle" {
    const allocator = testing.allocator;

    var conv = conversation.Conversation.init(allocator);
    defer conv.deinit();

    // Add user message
    const msg = try conv.addUserMessage("Hello");
    try testing.expectEqual(@as(u64, 1), msg.id);
    try testing.expectEqual(message.Role.user, msg.role);

    // Start streaming
    conv.startStreaming();
    try testing.expect(conv.is_streaming);

    // Append streaming text
    try conv.appendStreamingText("Hello");
    try conv.appendStreamingText(" ");
    try conv.appendStreamingText("there");

    const streaming_text = conv.getStreamingText().?;
    try testing.expectEqualStrings("Hello there", streaming_text);

    // Finish streaming
    const assistant_msg = try conv.finishStreaming();
    try testing.expect(assistant_msg != null);
    try testing.expect(!conv.is_streaming);
    try testing.expectEqual(message.Role.assistant, assistant_msg.?.role);

    // Should have 2 messages now
    try testing.expectEqual(@as(usize, 2), conv.messages.items.len);
}

test "Conversation abort streaming" {
    const allocator = testing.allocator;

    var conv = conversation.Conversation.init(allocator);
    defer conv.deinit();

    // Start streaming
    conv.startStreaming();
    try conv.appendStreamingText("Some partial text");

    try testing.expect(conv.is_streaming);

    // Abort
    conv.abortStreaming();

    try testing.expect(!conv.is_streaming);
    try testing.expectEqual(@as(?[]const u8, null), conv.getStreamingText());
    try testing.expectEqual(@as(usize, 0), conv.messages.items.len);
}

test "Conversation clear" {
    const allocator = testing.allocator;

    var conv = conversation.Conversation.init(allocator);
    defer conv.deinit();

    _ = try conv.addUserMessage("Message 1");
    _ = try conv.addUserMessage("Message 2");
    _ = try conv.addUserMessage("Message 3");

    try testing.expectEqual(@as(usize, 3), conv.messages.items.len);

    conv.clear();

    try testing.expectEqual(@as(usize, 0), conv.messages.items.len);
    try testing.expectEqual(@as(u64, 1), conv.next_id);
}

test "Conversation getLastMessages" {
    const allocator = testing.allocator;

    var conv = conversation.Conversation.init(allocator);
    defer conv.deinit();

    _ = try conv.addUserMessage("Message 1");
    _ = try conv.addUserMessage("Message 2");
    _ = try conv.addUserMessage("Message 3");
    _ = try conv.addUserMessage("Message 4");

    const last_two = conv.getLastMessages(2);
    try testing.expectEqual(@as(usize, 2), last_two.len);
    try testing.expectEqual(@as(u64, 3), last_two[0].id);
    try testing.expectEqual(@as(u64, 4), last_two[1].id);

    // Request more than available
    const all = conv.getLastMessages(100);
    try testing.expectEqual(@as(usize, 4), all.len);
}
