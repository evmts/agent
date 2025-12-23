const std = @import("std");
const vaxis = @import("vaxis");
const syntax = @import("syntax.zig");

pub const MarkdownRenderer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MarkdownRenderer {
        return .{ .allocator = allocator };
    }

    /// Render markdown to styled segments
    pub fn render(self: *MarkdownRenderer, markdown: []const u8) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);
        var state = ParserState.init(self.allocator);
        defer state.deinit();

        var lines = std.mem.splitScalar(u8, markdown, '\n');
        var first = true;
        while (lines.next()) |line| {
            if (!first) {
                try segments.append(.{ .text = "\n", .style = .{} });
            }
            first = false;
            try self.parseLine(&segments, line, &state);
        }

        return segments.toOwnedSlice();
    }

    fn parseLine(self: *MarkdownRenderer, segments: *std.ArrayList(Segment), line: []const u8, state: *ParserState) !void {
        // Handle code blocks
        if (std.mem.startsWith(u8, line, "```")) {
            if (state.in_code_block) {
                // Closing code block - render with syntax highlighting
                try self.renderCodeBlock(segments, state);
                state.code_buffer.clearRetainingCapacity();
            } else {
                // Opening code block
                if (line.len > 3) {
                    state.code_language = line[3..];
                } else {
                    state.code_language = null;
                }
            }
            state.in_code_block = !state.in_code_block;
            return;
        }

        if (state.in_code_block) {
            // Accumulate code lines
            if (state.code_buffer.items.len > 0) {
                try state.code_buffer.append('\n');
            }
            try state.code_buffer.appendSlice(line);
            return;
        }

        // Headers
        if (line.len > 0 and line[0] == '#') {
            const header = self.parseHeader(line);
            try segments.append(.{
                .text = try self.allocator.dupe(u8, header.text),
                .style = header.style,
            });
            return;
        }

        // Blockquotes
        if (std.mem.startsWith(u8, line, "> ")) {
            try segments.append(.{
                .text = "│ ",
                .style = .{ .fg = .{ .index = 8 } },
            });
            try self.parseInline(segments, line[2..]);
            return;
        }

        // Unordered lists
        if (std.mem.startsWith(u8, line, "- ") or std.mem.startsWith(u8, line, "* ")) {
            try segments.append(.{
                .text = "  • ",
                .style = .{ .fg = .{ .index = 8 } },
            });
            try self.parseInline(segments, line[2..]);
            return;
        }

        // Ordered lists
        if (self.isOrderedListItem(line)) |num_end| {
            try segments.append(.{
                .text = try std.fmt.allocPrint(self.allocator, "  {s} ", .{line[0..num_end]}),
                .style = .{ .fg = .{ .index = 8 } },
            });
            try self.parseInline(segments, line[num_end + 2 ..]);
            return;
        }

        // Horizontal rule
        if (line.len >= 3 and (std.mem.eql(u8, line, "---") or std.mem.eql(u8, line, "***") or std.mem.eql(u8, line, "___"))) {
            try segments.append(.{
                .text = "────────────────────────────────────────",
                .style = .{ .fg = .{ .index = 8 } },
            });
            return;
        }

        // Regular line with inline formatting
        try self.parseInline(segments, line);
    }

    fn renderCodeBlock(self: *MarkdownRenderer, segments: *std.ArrayList(Segment), state: *ParserState) !void {
        if (state.code_buffer.items.len == 0) return;

        // Detect language
        const lang = if (state.code_language) |lang_str|
            syntax.detectLanguage(std.mem.trim(u8, lang_str, " \t\r\n"))
        else
            syntax.Language.unknown;

        // Highlight code
        const highlighted = try syntax.highlight(self.allocator, state.code_buffer.items, lang);
        defer highlighted.deinit();

        // Split by newlines and render each line with indentation
        var line_start: usize = 0;
        for (highlighted.items, 0..) |seg, i| {
            // Add indentation at start of each line
            if (line_start == 0 or (i > 0 and std.mem.endsWith(u8, highlighted.items[i - 1].text, "\n"))) {
                try segments.append(.{
                    .text = "  ",
                    .style = .{},
                });
            }

            // Add the styled segment
            try segments.append(.{
                .text = try self.allocator.dupe(u8, seg.text),
                .style = .{ .fg = .{ .index = seg.color } },
            });

            if (std.mem.endsWith(u8, seg.text, "\n")) {
                line_start = i + 1;
            }
        }
    }

    fn parseHeader(self: *MarkdownRenderer, line: []const u8) HeaderResult {
        _ = self;
        var level: u8 = 0;
        for (line) |char| {
            if (char == '#') level += 1 else break;
        }

        const text = std.mem.trim(u8, line[level..], " ");

        const style: vaxis.Cell.Style = switch (level) {
            1 => .{ .fg = .{ .index = 14 }, .bold = true, .ul_style = .single },
            2 => .{ .fg = .{ .index = 14 }, .bold = true },
            else => .{ .bold = true },
        };

        return .{ .text = text, .style = style };
    }

    const HeaderResult = struct {
        text: []const u8,
        style: vaxis.Cell.Style,
    };

    fn parseInline(self: *MarkdownRenderer, segments: *std.ArrayList(Segment), text: []const u8) !void {
        if (text.len == 0) return;

        var i: usize = 0;
        var current_start: usize = 0;

        while (i < text.len) {
            // Bold **text**
            if (i + 1 < text.len and text[i] == '*' and text[i + 1] == '*') {
                // Flush current text
                if (i > current_start) {
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, text[current_start..i]),
                        .style = .{},
                    });
                }

                // Find closing **
                const start = i + 2;
                i = start;
                while (i + 1 < text.len) : (i += 1) {
                    if (text[i] == '*' and text[i + 1] == '*') break;
                }

                if (i + 1 < text.len) {
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, text[start..i]),
                        .style = .{ .bold = true },
                    });
                    i += 2;
                } else {
                    // No closing found, treat as literal
                    try segments.append(.{
                        .text = "**",
                        .style = .{},
                    });
                    i = start;
                }
                current_start = i;
                continue;
            }

            // Italic *text* (but not **)
            if (text[i] == '*' and (i == 0 or text[i - 1] != '*') and (i + 1 >= text.len or text[i + 1] != '*')) {
                if (i > current_start) {
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, text[current_start..i]),
                        .style = .{},
                    });
                }

                const start = i + 1;
                i = start;
                while (i < text.len and text[i] != '*') : (i += 1) {}

                if (i < text.len) {
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, text[start..i]),
                        .style = .{ .italic = true },
                    });
                    i += 1;
                } else {
                    // No closing found, treat as literal
                    try segments.append(.{
                        .text = "*",
                        .style = .{},
                    });
                    i = start;
                }
                current_start = i;
                continue;
            }

            // Inline code `code`
            if (text[i] == '`') {
                if (i > current_start) {
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, text[current_start..i]),
                        .style = .{},
                    });
                }

                const start = i + 1;
                i = start;
                while (i < text.len and text[i] != '`') : (i += 1) {}

                if (i < text.len) {
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, text[start..i]),
                        .style = .{ .reverse = true },
                    });
                    i += 1;
                } else {
                    // No closing found, treat as literal
                    try segments.append(.{
                        .text = "`",
                        .style = .{},
                    });
                    i = start;
                }
                current_start = i;
                continue;
            }

            // Strikethrough ~~text~~
            if (i + 1 < text.len and text[i] == '~' and text[i + 1] == '~') {
                if (i > current_start) {
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, text[current_start..i]),
                        .style = .{},
                    });
                }

                const start = i + 2;
                i = start;
                while (i + 1 < text.len) : (i += 1) {
                    if (text[i] == '~' and text[i + 1] == '~') break;
                }

                if (i + 1 < text.len) {
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, text[start..i]),
                        .style = .{ .strikethrough = true },
                    });
                    i += 2;
                } else {
                    // No closing found, treat as literal
                    try segments.append(.{
                        .text = "~~",
                        .style = .{},
                    });
                    i = start;
                }
                current_start = i;
                continue;
            }

            // Links [text](url)
            if (text[i] == '[') {
                const link = self.parseLink(text[i..]);
                if (link) |l| {
                    if (i > current_start) {
                        try segments.append(.{
                            .text = try self.allocator.dupe(u8, text[current_start..i]),
                            .style = .{},
                        });
                    }

                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, l.text),
                        .style = .{ .fg = .{ .index = 12 }, .ul_style = .single },
                        .link = try self.allocator.dupe(u8, l.url),
                    });

                    i += l.consumed;
                    current_start = i;
                    continue;
                }
            }

            i += 1;
        }

        // Flush remaining text
        if (current_start < text.len) {
            try segments.append(.{
                .text = try self.allocator.dupe(u8, text[current_start..]),
                .style = .{},
            });
        }
    }

    fn parseLink(self: *MarkdownRenderer, text: []const u8) ?LinkResult {
        _ = self;
        if (text.len == 0 or text[0] != '[') return null;

        // Find ]
        var i: usize = 1;
        while (i < text.len and text[i] != ']') : (i += 1) {}
        if (i >= text.len) return null;

        const link_text = text[1..i];

        // Expect (
        i += 1;
        if (i >= text.len or text[i] != '(') return null;

        // Find )
        const url_start = i + 1;
        i = url_start;
        while (i < text.len and text[i] != ')') : (i += 1) {}
        if (i >= text.len) return null;

        const url = text[url_start..i];

        return .{
            .text = link_text,
            .url = url,
            .consumed = i + 1,
        };
    }

    const LinkResult = struct {
        text: []const u8,
        url: []const u8,
        consumed: usize,
    };

    fn isOrderedListItem(self: *MarkdownRenderer, line: []const u8) ?usize {
        _ = self;
        var i: usize = 0;
        while (i < line.len and line[i] >= '0' and line[i] <= '9') : (i += 1) {}
        if (i > 0 and i + 1 < line.len and line[i] == '.' and line[i + 1] == ' ') {
            return i;
        }
        return null;
    }
};

pub const Segment = struct {
    text: []const u8,
    style: vaxis.Cell.Style = .{},
    link: ?[]const u8 = null,
};

const ParserState = struct {
    in_code_block: bool = false,
    code_language: ?[]const u8 = null,
    code_buffer: std.ArrayList(u8) = undefined,
    code_start_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator) ParserState {
        return .{
            .code_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *ParserState) void {
        self.code_buffer.deinit();
    }
};

// Tests
test "parse headers" {
    const testing = std.testing;
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("# H1");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
    try testing.expect(segments[0].style.bold);
    try testing.expect(segments[0].style.fg.?.index == 14);
}

test "parse bold" {
    const testing = std.testing;
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("This is **bold** text");
    defer testing.allocator.free(segments);

    // Find the bold segment
    var found_bold = false;
    for (segments) |seg| {
        if (seg.style.bold and std.mem.eql(u8, seg.text, "bold")) {
            found_bold = true;
            break;
        }
    }
    try testing.expect(found_bold);
}

test "parse italic" {
    const testing = std.testing;
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("This is *italic* text");
    defer testing.allocator.free(segments);

    var found_italic = false;
    for (segments) |seg| {
        if (seg.style.italic and std.mem.eql(u8, seg.text, "italic")) {
            found_italic = true;
            break;
        }
    }
    try testing.expect(found_italic);
}

test "parse code block" {
    const testing = std.testing;
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render(
        \\```zig
        \\const x = 10;
        \\```
    );
    defer testing.allocator.free(segments);

    // Should have code line
    var found_code = false;
    for (segments) |seg| {
        if (seg.style.dim and std.mem.indexOf(u8, seg.text, "const x = 10;") != null) {
            found_code = true;
            break;
        }
    }
    try testing.expect(found_code);
}

test "parse inline code" {
    const testing = std.testing;
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("Use `const` for constants");
    defer testing.allocator.free(segments);

    var found_code = false;
    for (segments) |seg| {
        if (seg.style.reverse and std.mem.eql(u8, seg.text, "const")) {
            found_code = true;
            break;
        }
    }
    try testing.expect(found_code);
}

test "parse list" {
    const testing = std.testing;
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("- Item 1");
    defer testing.allocator.free(segments);

    // Should have bullet point
    try testing.expect(segments.len > 0);
    try testing.expect(std.mem.indexOf(u8, segments[0].text, "•") != null);
}

test "parse numbered list" {
    const testing = std.testing;
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("1. First item");
    defer testing.allocator.free(segments);

    // Should have number
    try testing.expect(segments.len > 0);
    try testing.expect(std.mem.indexOf(u8, segments[0].text, "1") != null);
}

test "parse link" {
    const testing = std.testing;
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("[example](https://example.com)");
    defer testing.allocator.free(segments);

    var found_link = false;
    for (segments) |seg| {
        if (seg.link != null and std.mem.eql(u8, seg.text, "example")) {
            try testing.expectEqualStrings("https://example.com", seg.link.?);
            found_link = true;
            break;
        }
    }
    try testing.expect(found_link);
}

test "parse empty input" {
    const testing = std.testing;
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len == 0);
}

test "unclosed bold marker" {
    const testing = std.testing;
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("**unclosed");
    defer testing.allocator.free(segments);

    // Should treat ** as literal since no closing
    try testing.expect(segments.len > 0);
}
