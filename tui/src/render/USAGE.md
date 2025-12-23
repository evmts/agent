# Markdown Renderer Usage

The markdown renderer provides three main components for handling markdown in the TUI:

## 1. MarkdownRenderer - Basic Markdown Parsing

```zig
const std = @import("std");
const MarkdownRenderer = @import("markdown.zig").MarkdownRenderer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = MarkdownRenderer.init(allocator);

    const markdown =
        \\# Welcome to Plue TUI
        \\
        \\This is **bold** and *italic* text.
        \\
        \\- List item 1
        \\- List item 2
    ;

    const segments = try renderer.render(markdown);
    defer allocator.free(segments);

    // segments is now an array of styled text segments
    for (segments) |segment| {
        std.debug.print("Text: {s}, Bold: {}\n", .{
            segment.text,
            segment.style.bold
        });
    }
}
```

## 2. StreamingMarkdown - For Assistant Responses

When rendering streaming assistant responses, use `StreamingMarkdown` to handle incomplete content:

```zig
const StreamingMarkdown = @import("streaming_markdown.zig").StreamingMarkdown;

pub fn handleStream(allocator: std.mem.Allocator) !void {
    var stream = StreamingMarkdown.init(allocator);
    defer stream.deinit();

    // As chunks arrive from SSE stream
    try stream.append("This is the first ");
    try stream.append("part of the message.\n");
    try stream.append("And this is incomplete **bold");

    // Get rendered segments for complete lines
    const segments = stream.getSegments();

    // Get incomplete line (for cursor positioning)
    const incomplete = stream.getIncompleteLine(); // "And this is incomplete **bold"

    // When stream completes
    const all_segments = try stream.finalize();
}
```

## 3. Text Renderer - Draw Segments to Surface

Use the text renderer to draw segments to a vxfw Surface:

```zig
const text = @import("text.zig");
const vaxis = @import("vaxis");

pub fn drawMarkdown(
    surface: *vaxis.vxfw.Surface,
    segments: []const Segment,
) void {
    const result = text.renderSegments(
        surface,
        segments,
        0,          // start_row
        0,          // start_col
        80,         // max_width
        null,       // max_rows (null = unlimited)
    );

    std.debug.print("Used {} rows\n", .{result.rows_used});
    if (result.truncated) {
        std.debug.print("Content was truncated\n", .{});
    }
}

pub fn calculateSpace(segments: []const Segment) u16 {
    return text.calculateHeight(segments, 80);
}
```

## Integration with Chat History

Here's how to integrate with the chat history widget:

```zig
const MarkdownRenderer = @import("../render/markdown.zig").MarkdownRenderer;
const text = @import("../render/text.zig");

pub const AssistantMessageCell = struct {
    content: []const u8,
    renderer: MarkdownRenderer,
    segments: ?[]Segment = null,

    pub fn init(allocator: std.mem.Allocator, content: []const u8) !AssistantMessageCell {
        var renderer = MarkdownRenderer.init(allocator);
        const segments = try renderer.render(content);

        return .{
            .content = content,
            .renderer = renderer,
            .segments = segments,
        };
    }

    pub fn height(self: AssistantMessageCell, width: u16) u16 {
        if (self.segments) |segs| {
            return text.calculateHeight(segs, width);
        }
        return 0;
    }

    pub fn draw(self: *AssistantMessageCell, surface: *vxfw.Surface, row: u16, width: u16) void {
        if (self.segments) |segs| {
            _ = text.renderSegments(surface, segs, row, 0, width, null);
        }
    }
};
```

## Supported Markdown Elements

| Element | Input | Rendered Style |
|---------|-------|----------------|
| H1 | `# Title` | Bold + Cyan + Underline |
| H2 | `## Title` | Bold + Cyan |
| H3-H6 | `### Title` | Bold |
| Bold | `**text**` | Bold |
| Italic | `*text*` | Italic |
| Code | `` `code` `` | Reverse video |
| Code block | ``` ```lang ... ``` ``` | Dim + indented |
| Link | `[text](url)` | Underline + Blue |
| List | `- item` | `  • item` |
| Numbered | `1. item` | `  1. item` |
| Quote | `> text` | Dim + `│ ` prefix |
| Strike | `~~text~~` | Strikethrough |
| HR | `---` | Horizontal line |

## Edge Cases

The parser handles these edge cases gracefully:

- **Unclosed markers**: `**unclosed` → treated as literal text
- **Empty input**: Returns empty segment array
- **Nested markers**: Processes sequentially (limited nesting support)
- **UTF-8 content**: Properly handles multi-byte characters
- **Long lines**: Automatic word wrapping in text renderer
