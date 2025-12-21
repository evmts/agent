# 09: Markdown Renderer

## Goal

Implement a streaming-capable markdown renderer that converts CommonMark to styled terminal text.

## Context

- Assistant messages contain markdown formatting
- Must handle: headers, bold, italic, code (inline and block), lists, links
- Should support streaming (partial content rendering)
- Reference: codex `pulldown-cmark` usage, `/Users/williamcory/plue/tui/src/render/markdown.ts`

## Supported Elements

| Element | Syntax | Terminal Style |
|---------|--------|----------------|
| H1 | `# Title` | Bold + Cyan + Underline |
| H2 | `## Title` | Bold + Cyan |
| H3-H6 | `### Title` | Bold |
| Bold | `**text**` | Bold |
| Italic | `*text*` | Italic |
| Code inline | `` `code` `` | Reverse video |
| Code block | ``` ```lang ``` | Dim + indented |
| Link | `[text](url)` | Underline + Blue |
| List item | `- item` | `  • item` |
| Numbered | `1. item` | `  1. item` |
| Blockquote | `> text` | Dim + `│ ` prefix |
| Strikethrough | `~~text~~` | Strikethrough |

## Tasks

### 1. Create Markdown Parser (src/render/markdown.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");

pub const MarkdownRenderer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MarkdownRenderer {
        return .{ .allocator = allocator };
    }

    /// Render markdown to styled segments
    pub fn render(self: *MarkdownRenderer, markdown: []const u8) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);
        var state = ParserState{};

        var lines = std.mem.split(u8, markdown, "\n");
        while (lines.next()) |line| {
            try self.parseLine(&segments, line, &state);
            try segments.append(.{ .text = "\n", .style = .{} });
        }

        return segments.toOwnedSlice();
    }

    fn parseLine(self: *MarkdownRenderer, segments: *std.ArrayList(Segment), line: []const u8, state: *ParserState) !void {
        // Handle code blocks
        if (std.mem.startsWith(u8, line, "```")) {
            state.in_code_block = !state.in_code_block;
            if (state.in_code_block and line.len > 3) {
                state.code_language = line[3..];
            } else {
                state.code_language = null;
            }
            return;
        }

        if (state.in_code_block) {
            try segments.append(.{
                .text = try self.allocator.dupe(u8, line),
                .style = .{ .fg = .{ .index = 8 }, .dim = true },
            });
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

        // Regular line with inline formatting
        try self.parseInline(segments, line);
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

                try segments.append(.{
                    .text = try self.allocator.dupe(u8, text[start..i]),
                    .style = .{ .bold = true },
                });

                i += 2;
                current_start = i;
                continue;
            }

            // Italic *text*
            if (text[i] == '*' and (i + 1 >= text.len or text[i + 1] != '*')) {
                if (i > current_start) {
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, text[current_start..i]),
                        .style = .{},
                    });
                }

                const start = i + 1;
                i = start;
                while (i < text.len and text[i] != '*') : (i += 1) {}

                try segments.append(.{
                    .text = try self.allocator.dupe(u8, text[start..i]),
                    .style = .{ .italic = true },
                });

                i += 1;
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

                try segments.append(.{
                    .text = try self.allocator.dupe(u8, text[start..i]),
                    .style = .{ .reverse = true },
                });

                i += 1;
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

                try segments.append(.{
                    .text = try self.allocator.dupe(u8, text[start..i]),
                    .style = .{ .strikethrough = true },
                });

                i += 2;
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
                        .link = l.url,
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
};
```

### 2. Create Streaming Markdown Buffer (src/render/streaming_markdown.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const MarkdownRenderer = @import("markdown.zig").MarkdownRenderer;
const Segment = @import("markdown.zig").Segment;

/// Handles streaming markdown by buffering incomplete elements
pub const StreamingMarkdown = struct {
    allocator: std.mem.Allocator,
    renderer: MarkdownRenderer,
    buffer: std.ArrayList(u8),
    rendered_segments: std.ArrayList(Segment),
    incomplete_line: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) StreamingMarkdown {
        return .{
            .allocator = allocator,
            .renderer = MarkdownRenderer.init(allocator),
            .buffer = std.ArrayList(u8).init(allocator),
            .rendered_segments = std.ArrayList(Segment).init(allocator),
            .incomplete_line = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *StreamingMarkdown) void {
        self.buffer.deinit();
        self.rendered_segments.deinit();
        self.incomplete_line.deinit();
    }

    /// Append new text to the stream
    pub fn append(self: *StreamingMarkdown, text: []const u8) !void {
        try self.buffer.appendSlice(text);
        try self.processBuffer();
    }

    /// Get currently rendered segments
    pub fn getSegments(self: *StreamingMarkdown) []Segment {
        return self.rendered_segments.items;
    }

    /// Get the incomplete line buffer (for cursor positioning)
    pub fn getIncompleteLine(self: *StreamingMarkdown) []const u8 {
        return self.incomplete_line.items;
    }

    fn processBuffer(self: *StreamingMarkdown) !void {
        // Find complete lines
        var last_newline: ?usize = null;
        for (self.buffer.items, 0..) |char, i| {
            if (char == '\n') last_newline = i;
        }

        if (last_newline) |nl| {
            // Process complete lines
            const complete = self.buffer.items[0 .. nl + 1];
            const segments = try self.renderer.render(complete);

            for (segments) |seg| {
                try self.rendered_segments.append(seg);
            }

            // Keep incomplete part
            self.incomplete_line.clearRetainingCapacity();
            if (nl + 1 < self.buffer.items.len) {
                try self.incomplete_line.appendSlice(self.buffer.items[nl + 1 ..]);
            }

            // Clear processed buffer
            try self.buffer.replaceRange(0, nl + 1, &.{});
        }
    }

    /// Finalize streaming - process any remaining buffer
    pub fn finalize(self: *StreamingMarkdown) ![]Segment {
        if (self.buffer.items.len > 0) {
            const segments = try self.renderer.render(self.buffer.items);
            for (segments) |seg| {
                try self.rendered_segments.append(seg);
            }
            self.buffer.clearRetainingCapacity();
        }
        return self.rendered_segments.items;
    }

    pub fn clear(self: *StreamingMarkdown) void {
        self.buffer.clearRetainingCapacity();
        self.rendered_segments.clearRetainingCapacity();
        self.incomplete_line.clearRetainingCapacity();
    }
};
```

### 3. Create Text Renderer Helper (src/render/text.zig)

```zig
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
        for (segment.text) |char| {
            if (max_rows) |mr| {
                if (row >= start_row + mr) {
                    return .{ .rows_used = row - start_row, .truncated = true };
                }
            }

            if (char == '\n') {
                row += 1;
                col = start_col;
                continue;
            }

            // Word wrap
            if (col >= end_col) {
                row += 1;
                col = start_col;
            }

            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = segment.style,
            });

            col += 1;
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
        for (segment.text) |char| {
            if (char == '\n') {
                rows += 1;
                col = 0;
                continue;
            }

            col += 1;
            if (col >= width) {
                rows += 1;
                col = 0;
            }
        }
    }

    return rows;
}
```

## Acceptance Criteria

- [ ] Headers H1-H6 render with appropriate styles
- [ ] Bold text renders with bold attribute
- [ ] Italic text renders with italic attribute
- [ ] Inline code renders with reverse video
- [ ] Code blocks render with dim style
- [ ] Links render with underline and blue color
- [ ] Unordered lists show bullet points
- [ ] Ordered lists show numbers
- [ ] Blockquotes show with `│ ` prefix
- [ ] Strikethrough renders correctly
- [ ] Streaming mode handles incomplete lines
- [ ] Word wrapping works correctly
- [ ] Height calculation accurate for scrolling

## Files to Create

1. `tui-zig/src/render/markdown.zig`
2. `tui-zig/src/render/streaming_markdown.zig`
3. `tui-zig/src/render/text.zig`

## Next

Proceed to `10_syntax_highlighting.md` for code block syntax highlighting.
