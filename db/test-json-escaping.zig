//! Test JSON string escaping to prevent injection attacks
//!
//! Run with: zig test db/test-json-escaping.zig

const std = @import("std");
const testing = std.testing;

/// Write a properly escaped JSON string value to a writer
/// Escapes: quotes, backslashes, newlines, tabs, carriage returns, and control characters
fn writeJsonString(writer: anytype, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            '\x08' => try writer.writeAll("\\b"), // backspace
            '\x0C' => try writer.writeAll("\\f"), // form feed
            0x00...0x07, 0x0B, 0x0E...0x1F => {
                // Other control characters: escape as \uXXXX
                try writer.print("\\u{x:0>4}", .{c});
            },
            else => try writer.writeByte(c),
        }
    }
}

test "JSON string escaping - basic strings" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try writer.writeByte('"');
    try writeJsonString(writer, "hello");
    try writer.writeByte('"');

    try testing.expectEqualStrings("\"hello\"", stream.getWritten());
}

test "JSON string escaping - prevents quote injection" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // Attack payload: inject closing quote and new key
    const malicious = "ubuntu\", \"injected\": \"payload";

    try writer.writeByte('[');
    try writer.writeByte('"');
    try writeJsonString(writer, malicious);
    try writer.writeByte('"');
    try writer.writeByte(']');

    const result = stream.getWritten();

    // Should NOT contain unescaped quotes that would break JSON structure
    try testing.expectEqualStrings("[\"ubuntu\\\", \\\"injected\\\": \\\"payload\"]", result);

    // Verify it's valid JSON by parsing
    const parsed = try std.json.parseFromSlice(
        [][]const u8,
        testing.allocator,
        result,
        .{},
    );
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 1), parsed.value.len);
    try testing.expectEqualStrings("ubuntu\", \"injected\": \"payload", parsed.value[0]);
}

test "JSON string escaping - backslashes" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try writer.writeByte('"');
    try writeJsonString(writer, "path\\to\\file");
    try writer.writeByte('"');

    try testing.expectEqualStrings("\"path\\\\to\\\\file\"", stream.getWritten());
}

test "JSON string escaping - newlines and tabs" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try writer.writeByte('"');
    try writeJsonString(writer, "line1\nline2\ttabbed");
    try writer.writeByte('"');

    try testing.expectEqualStrings("\"line1\\nline2\\ttabbed\"", stream.getWritten());
}

test "JSON string escaping - carriage returns" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try writer.writeByte('"');
    try writeJsonString(writer, "windows\r\nline");
    try writer.writeByte('"');

    try testing.expectEqualStrings("\"windows\\r\\nline\"", stream.getWritten());
}

test "JSON string escaping - control characters" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try writer.writeByte('"');
    try writeJsonString(writer, "null\x00char");
    try writer.writeByte('"');

    try testing.expectEqualStrings("\"null\\u0000char\"", stream.getWritten());
}

test "JSON string escaping - bell character" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try writer.writeByte('"');
    try writeJsonString(writer, "bell\x07char");
    try writer.writeByte('"');

    try testing.expectEqualStrings("\"bell\\u0007char\"", stream.getWritten());
}

test "JSON array construction - safe labels" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    const labels = [_][]const u8{ "ubuntu", "linux", "x86_64" };

    try writer.writeByte('[');
    for (labels, 0..) |label, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeByte('"');
        try writeJsonString(writer, label);
        try writer.writeByte('"');
    }
    try writer.writeByte(']');

    try testing.expectEqualStrings("[\"ubuntu\",\"linux\",\"x86_64\"]", stream.getWritten());
}

test "JSON array construction - malicious labels" {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // Multiple injection attempts
    const labels = [_][]const u8{
        "ubuntu\", \"evil\": \"true",
        "linux\\\\escape",
        "newline\ninjection",
    };

    try writer.writeByte('[');
    for (labels, 0..) |label, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeByte('"');
        try writeJsonString(writer, label);
        try writer.writeByte('"');
    }
    try writer.writeByte(']');

    const result = stream.getWritten();

    // Verify it's valid JSON
    const parsed = try std.json.parseFromSlice(
        [][]const u8,
        testing.allocator,
        result,
        .{},
    );
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 3), parsed.value.len);
    try testing.expectEqualStrings("ubuntu\", \"evil\": \"true", parsed.value[0]);
    try testing.expectEqualStrings("linux\\\\escape", parsed.value[1]);
    try testing.expectEqualStrings("newline\ninjection", parsed.value[2]);
}

test "JSON array construction - empty array" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    const labels: []const []const u8 = &.{};

    try writer.writeByte('[');
    for (labels, 0..) |label, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeByte('"');
        try writeJsonString(writer, label);
        try writer.writeByte('"');
    }
    try writer.writeByte(']');

    try testing.expectEqualStrings("[]", stream.getWritten());
}

test "JSON array construction - unicode and special characters" {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    const files = [_][]const u8{
        "file with spaces.txt",
        "file\twith\ttabs.txt",
        "résumé.pdf",
        "файл.txt", // Cyrillic
    };

    try writer.writeByte('[');
    for (files, 0..) |file, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeByte('"');
        try writeJsonString(writer, file);
        try writer.writeByte('"');
    }
    try writer.writeByte(']');

    const result = stream.getWritten();

    // Verify it's valid JSON and round-trips correctly
    const parsed = try std.json.parseFromSlice(
        [][]const u8,
        testing.allocator,
        result,
        .{},
    );
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 4), parsed.value.len);
    try testing.expectEqualStrings("file with spaces.txt", parsed.value[0]);
    try testing.expectEqualStrings("file\twith\ttabs.txt", parsed.value[1]);
    try testing.expectEqualStrings("résumé.pdf", parsed.value[2]);
    try testing.expectEqualStrings("файл.txt", parsed.value[3]);
}
