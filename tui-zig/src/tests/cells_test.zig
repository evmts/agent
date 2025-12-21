const std = @import("std");
const testing = std.testing;
const cells = @import("../widgets/cells.zig");
const wrap = @import("../utils/wrap.zig");
const Message = @import("../state/message.zig").Message;
const ToolCall = @import("../state/message.zig").ToolCall;

test "UserMessageCell height calculation" {
    const cell = cells.UserMessageCell{
        .content = "Hello world",
        .timestamp = 0,
    };

    // Short text should be 1 line
    try testing.expectEqual(@as(u16, 1), cell.height(80));

    // Should wrap if width is less than content + prefix
    const long_cell = cells.UserMessageCell{
        .content = "This is a very long message that should wrap",
        .timestamp = 0,
    };
    const height = long_cell.height(20);
    try testing.expect(height > 1);
}

test "AssistantMessageCell height includes tool calls" {
    var tool_calls = [_]ToolCall{
        .{
            .id = "1",
            .name = "test",
            .args = "{}",
            .status = .completed,
        },
    };

    const cell = cells.AssistantMessageCell{
        .content = "Response",
        .tool_calls = &tool_calls,
        .timestamp = 0,
    };

    const height = cell.height(80);
    // Should be at least 2: 1 for content + 1 for tool call
    try testing.expect(height >= 2);
}

test "ToolCallCell height with result" {
    const tc_no_result = ToolCall{
        .id = "1",
        .name = "test",
        .args = "{}",
        .status = .pending,
    };

    try testing.expectEqual(@as(u16, 1), cells.ToolCallCell.heightFor(tc_no_result, 80));

    const tc_with_result = ToolCall{
        .id = "1",
        .name = "test",
        .args = "{}",
        .status = .completed,
        .result = .{ .output = "success", .is_error = false },
    };

    try testing.expectEqual(@as(u16, 2), cells.ToolCallCell.heightFor(tc_with_result, 80));
}

test "StreamingCell height calculation" {
    const cell = cells.StreamingCell{
        .text_buffer = "Streaming text",
        .cursor_visible = true,
    };

    const height = cell.height(80);
    // Should be at least 1 (plus extra for cursor line)
    try testing.expect(height >= 1);
}

test "SystemMessageCell height calculation" {
    const cell = cells.SystemMessageCell{
        .content = "System message",
    };

    try testing.expectEqual(@as(u16, 1), cell.height(80));
}

test "Text wrapping utility" {
    // Simple text
    try testing.expectEqual(@as(u16, 1), wrap.wrapHeight("hello", 10));

    // Text that needs wrapping
    try testing.expectEqual(@as(u16, 2), wrap.wrapHeight("hello world", 5));

    // Text with newlines
    try testing.expectEqual(@as(u16, 2), wrap.wrapHeight("hello\nworld", 20));
}

test "Text wrapping with zero width" {
    try testing.expectEqual(@as(u16, 1), wrap.wrapHeight("test", 0));
}

test "Last column position" {
    try testing.expectEqual(@as(u16, 5), wrap.lastColumnOf("hello", 10));
    try testing.expectEqual(@as(u16, 1), wrap.lastColumnOf("hello world", 5));
}

test "HistoryCell union height" {
    const user_cell = cells.HistoryCell{
        .user_message = .{
            .content = "Test",
            .timestamp = 0,
        },
    };

    try testing.expectEqual(@as(u16, 1), user_cell.height(80));

    const separator = cells.HistoryCell{ .separator = .{} };
    try testing.expectEqual(@as(u16, 1), separator.height(80));
}

test "wrapText splits at boundaries" {
    const allocator = testing.allocator;
    const lines = try wrap.wrapText(allocator, "hello world", 5);
    defer lines.deinit();

    try testing.expectEqual(@as(usize, 3), lines.items.len);
}

test "wrapText handles empty string" {
    const allocator = testing.allocator;
    const lines = try wrap.wrapText(allocator, "", 10);
    defer lines.deinit();

    try testing.expectEqual(@as(usize, 1), lines.items.len);
    try testing.expectEqualStrings("", lines.items[0].text);
}
