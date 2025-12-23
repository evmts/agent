const std = @import("std");

/// Calculate the number of lines needed to display text at given width
/// Handles newlines and word wrapping
pub fn wrapHeight(text: []const u8, line_width: u16) u16 {
    if (line_width == 0) return 1;
    if (text.len == 0) return 1;

    var lines: u16 = 1;
    var col: u16 = 0;

    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];

        if (c == '\n') {
            lines += 1;
            col = 0;
            i += 1;
            continue;
        }

        // Simple grapheme handling - count bytes for UTF-8
        const char_len = utf8CharLen(c) catch 1;
        const grapheme_width = if (c < 128) 1 else 2; // Simple approximation

        if (col + grapheme_width > line_width) {
            lines += 1;
            col = 0;
        }

        col += grapheme_width;
        i += char_len;
    }

    return lines;
}

/// Get the length in bytes of a UTF-8 character given its first byte
fn utf8CharLen(first_byte: u8) !usize {
    if (first_byte < 0x80) return 1;
    if ((first_byte & 0xE0) == 0xC0) return 2;
    if ((first_byte & 0xF0) == 0xE0) return 3;
    if ((first_byte & 0xF8) == 0xF0) return 4;
    return error.InvalidUtf8;
}

/// Wrapped line information
pub const WrappedLine = struct {
    text: []const u8,
    start_offset: usize,
    end_offset: usize,
};

/// Wrap text and return list of line slices
/// Caller owns the returned ArrayList
pub fn wrapText(
    allocator: std.mem.Allocator,
    text: []const u8,
    line_width: u16,
) !std.ArrayList(WrappedLine) {
    var lines = std.ArrayList(WrappedLine).init(allocator);
    errdefer lines.deinit();

    if (line_width == 0 or text.len == 0) {
        try lines.append(.{
            .text = text,
            .start_offset = 0,
            .end_offset = text.len,
        });
        return lines;
    }

    var line_start: usize = 0;
    var i: usize = 0;
    var col: u16 = 0;

    while (i < text.len) {
        const c = text[i];

        if (c == '\n') {
            // End current line at newline
            try lines.append(.{
                .text = text[line_start..i],
                .start_offset = line_start,
                .end_offset = i,
            });
            i += 1;
            line_start = i;
            col = 0;
            continue;
        }

        const char_len = utf8CharLen(c) catch 1;
        const grapheme_width = if (c < 128) 1 else 2;

        if (col + grapheme_width > line_width) {
            // Wrap at current position
            try lines.append(.{
                .text = text[line_start..i],
                .start_offset = line_start,
                .end_offset = i,
            });
            line_start = i;
            col = 0;
        }

        col += grapheme_width;
        i += char_len;
    }

    // Add remaining text
    if (line_start < text.len) {
        try lines.append(.{
            .text = text[line_start..],
            .start_offset = line_start,
            .end_offset = text.len,
        });
    }

    return lines;
}

/// Find the column position of the last character in wrapped text
pub fn lastColumnOf(text: []const u8, line_width: u16) u16 {
    if (line_width == 0 or text.len == 0) return 0;

    var col: u16 = 0;
    var i: usize = 0;

    while (i < text.len) {
        const c = text[i];

        if (c == '\n') {
            col = 0;
            i += 1;
            continue;
        }

        const char_len = utf8CharLen(c) catch 1;
        const grapheme_width = if (c < 128) 1 else 2;

        if (col + grapheme_width > line_width) {
            col = 0;
        }

        col += grapheme_width;
        i += char_len;
    }

    return col;
}

test "wrapHeight with simple text" {
    try std.testing.expectEqual(@as(u16, 1), wrapHeight("hello", 10));
    try std.testing.expectEqual(@as(u16, 1), wrapHeight("hello world", 20));
    try std.testing.expectEqual(@as(u16, 2), wrapHeight("hello world", 5));
}

test "wrapHeight with newlines" {
    try std.testing.expectEqual(@as(u16, 2), wrapHeight("hello\nworld", 20));
    try std.testing.expectEqual(@as(u16, 3), wrapHeight("a\nb\nc", 20));
}

test "wrapHeight with zero width" {
    try std.testing.expectEqual(@as(u16, 1), wrapHeight("test", 0));
}

test "wrapText splits correctly" {
    const allocator = std.testing.allocator;
    const lines = try wrapText(allocator, "hello world", 5);
    defer lines.deinit();

    try std.testing.expectEqual(@as(usize, 3), lines.items.len);
    try std.testing.expectEqualStrings("hello", lines.items[0].text);
    try std.testing.expectEqualStrings(" worl", lines.items[1].text);
    try std.testing.expectEqualStrings("d", lines.items[2].text);
}

test "wrapText handles newlines" {
    const allocator = std.testing.allocator;
    const lines = try wrapText(allocator, "hello\nworld", 20);
    defer lines.deinit();

    try std.testing.expectEqual(@as(usize, 2), lines.items.len);
    try std.testing.expectEqualStrings("hello", lines.items[0].text);
    try std.testing.expectEqualStrings("world", lines.items[1].text);
}

test "lastColumnOf simple text" {
    try std.testing.expectEqual(@as(u16, 5), lastColumnOf("hello", 10));
    try std.testing.expectEqual(@as(u16, 1), lastColumnOf("hello world", 5));
}
