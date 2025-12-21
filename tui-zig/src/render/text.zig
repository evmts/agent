const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const Segment = @import("markdown.zig").Segment;

/// Render segments to a vxfw Surface with word wrapping
pub fn renderSegments(
    surface: *vxfw.Surface,
    segments: []const Segment,
    start_row: u16,
    start_col: u16,
    max_width: u16,
    max_rows: ?u16,
) RenderResult {
    var row = start_row;
    var col = start_col;
    const end_col = start_col + max_width;

    for (segments) |segment| {
        var i: usize = 0;
        while (i < segment.text.len) {
            if (max_rows) |mr| {
                if (row >= start_row + mr) {
                    return .{ .rows_used = row - start_row, .truncated = true };
                }
            }

            const c = segment.text[i];

            if (c == '\n') {
                row += 1;
                col = start_col;
                i += 1;
                continue;
            }

            // Get UTF-8 character length
            const char_len = utf8CharLen(c) catch 1;
            const grapheme_width = if (c < 128) 1 else 2;

            // Word wrap
            if (col + grapheme_width > end_col) {
                row += 1;
                col = start_col;
            }

            // Ensure we're not out of bounds
            if (max_rows) |mr| {
                if (row >= start_row + mr) {
                    return .{ .rows_used = row - start_row, .truncated = true };
                }
            }

            const char_slice = segment.text[i .. i + char_len];
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = char_slice, .width = @intCast(grapheme_width) },
                .style = segment.style,
            });

            col += grapheme_width;
            i += char_len;
        }
    }

    return .{ .rows_used = row - start_row + 1, .truncated = false };
}

pub const RenderResult = struct {
    rows_used: u16,
    truncated: bool,
};

/// Calculate height needed for segments with word wrapping
pub fn calculateHeight(segments: []const Segment, width: u16) u16 {
    var rows: u16 = 1;
    var col: u16 = 0;

    for (segments) |segment| {
        var i: usize = 0;
        while (i < segment.text.len) {
            const c = segment.text[i];

            if (c == '\n') {
                rows += 1;
                col = 0;
                i += 1;
                continue;
            }

            const char_len = utf8CharLen(c) catch 1;
            const grapheme_width = if (c < 128) 1 else 2;

            col += grapheme_width;
            if (col >= width) {
                rows += 1;
                col = 0;
            }

            i += char_len;
        }
    }

    return rows;
}

fn utf8CharLen(first_byte: u8) !usize {
    if (first_byte < 0x80) return 1;
    if ((first_byte & 0xE0) == 0xC0) return 2;
    if ((first_byte & 0xF0) == 0xE0) return 3;
    if ((first_byte & 0xF8) == 0xF0) return 4;
    return error.InvalidUtf8;
}

// Tests
test "calculate height single line" {
    const testing = std.testing;
    const segments = [_]Segment{
        .{ .text = "Hello world", .style = .{} },
    };

    const height = calculateHeight(&segments, 80);
    try testing.expectEqual(@as(u16, 1), height);
}

test "calculate height with newlines" {
    const testing = std.testing;
    const segments = [_]Segment{
        .{ .text = "Line 1\nLine 2\nLine 3", .style = .{} },
    };

    const height = calculateHeight(&segments, 80);
    try testing.expectEqual(@as(u16, 3), height);
}

test "calculate height with wrapping" {
    const testing = std.testing;
    const segments = [_]Segment{
        .{ .text = "This is a very long line that should wrap", .style = .{} },
    };

    const height = calculateHeight(&segments, 20);
    try testing.expect(height > 1);
}

test "calculate height empty" {
    const testing = std.testing;
    const segments = [_]Segment{};

    const height = calculateHeight(&segments, 80);
    try testing.expectEqual(@as(u16, 1), height);
}

test "calculate height multiple segments" {
    const testing = std.testing;
    const segments = [_]Segment{
        .{ .text = "Hello ", .style = .{} },
        .{ .text = "world", .style = .{ .bold = true } },
    };

    const height = calculateHeight(&segments, 80);
    try testing.expectEqual(@as(u16, 1), height);
}
