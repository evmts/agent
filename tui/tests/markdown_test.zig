const std = @import("std");
const testing = std.testing;
const MarkdownRenderer = @import("../render/markdown.zig").MarkdownRenderer;
const StreamingMarkdown = @import("../render/streaming_markdown.zig").StreamingMarkdown;
const text = @import("../render/text.zig");

test "markdown: headers H1" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("# Main Header");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
    try testing.expect(segments[0].style.bold);
    try testing.expectEqual(@as(u8, 14), segments[0].style.fg.?.index);
    try testing.expect(segments[0].style.ul_style == .single);
    try testing.expectEqualStrings("Main Header", segments[0].text);
}

test "markdown: headers H2" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("## Section Header");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
    try testing.expect(segments[0].style.bold);
    try testing.expectEqual(@as(u8, 14), segments[0].style.fg.?.index);
    try testing.expectEqualStrings("Section Header", segments[0].text);
}

test "markdown: headers H3" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("### Subsection");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
    try testing.expect(segments[0].style.bold);
    try testing.expectEqualStrings("Subsection", segments[0].text);
}

test "markdown: bold text" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("This is **bold** text here");
    defer testing.allocator.free(segments);

    var found_bold = false;
    for (segments) |seg| {
        if (seg.style.bold and std.mem.eql(u8, seg.text, "bold")) {
            found_bold = true;
            break;
        }
    }
    try testing.expect(found_bold);
}

test "markdown: italic text" {
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

test "markdown: inline code" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("Use `const x = 10;` for constants");
    defer testing.allocator.free(segments);

    var found_code = false;
    for (segments) |seg| {
        if (seg.style.reverse and std.mem.eql(u8, seg.text, "const x = 10;")) {
            found_code = true;
            break;
        }
    }
    try testing.expect(found_code);
}

test "markdown: code block with language" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render(
        \\```zig
        \\const x = 10;
        \\const y = 20;
        \\```
    );
    defer testing.allocator.free(segments);

    // Should have indented code lines with dim style
    var found_code_line = false;
    for (segments) |seg| {
        if (seg.style.dim and std.mem.indexOf(u8, seg.text, "const x = 10;") != null) {
            found_code_line = true;
            break;
        }
    }
    try testing.expect(found_code_line);
}

test "markdown: unordered list" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("- First item");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
    try testing.expect(std.mem.indexOf(u8, segments[0].text, "•") != null);
}

test "markdown: ordered list" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("1. First item");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
    try testing.expect(std.mem.indexOf(u8, segments[0].text, "1") != null);
}

test "markdown: blockquote" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("> This is a quote");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
    try testing.expect(std.mem.indexOf(u8, segments[0].text, "│") != null);
}

test "markdown: strikethrough" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("This is ~~deleted~~ text");
    defer testing.allocator.free(segments);

    var found_strikethrough = false;
    for (segments) |seg| {
        if (seg.style.strikethrough and std.mem.eql(u8, seg.text, "deleted")) {
            found_strikethrough = true;
            break;
        }
    }
    try testing.expect(found_strikethrough);
}

test "markdown: link" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("[Visit Example](https://example.com)");
    defer testing.allocator.free(segments);

    var found_link = false;
    for (segments) |seg| {
        if (seg.link != null and std.mem.eql(u8, seg.text, "Visit Example")) {
            try testing.expectEqualStrings("https://example.com", seg.link.?);
            try testing.expect(seg.style.ul_style == .single);
            try testing.expectEqual(@as(u8, 12), seg.style.fg.?.index);
            found_link = true;
            break;
        }
    }
    try testing.expect(found_link);
}

test "markdown: horizontal rule" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("---");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
    try testing.expect(std.mem.indexOf(u8, segments[0].text, "─") != null);
}

test "markdown: nested formatting (bold in italic)" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("*italic **bold** text*");
    defer testing.allocator.free(segments);

    // Note: Our simple parser doesn't support full nesting, but it should handle sequential markers
    try testing.expect(segments.len > 0);
}

test "markdown: empty input" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len == 0);
}

test "markdown: unclosed bold marker" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("**unclosed bold");
    defer testing.allocator.free(segments);

    // Should handle gracefully (treat as literal)
    try testing.expect(segments.len > 0);
}

test "markdown: unclosed italic marker" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("*unclosed italic");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
}

test "markdown: unclosed code marker" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const segments = try renderer.render("`unclosed code");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
}

test "streaming: complete line" {
    var stream = StreamingMarkdown.init(testing.allocator);
    defer stream.deinit();

    try stream.append("# Header\n");
    const segments = stream.getSegments();

    try testing.expect(segments.len > 0);
    try testing.expect(segments[0].style.bold);
}

test "streaming: incomplete line" {
    var stream = StreamingMarkdown.init(testing.allocator);
    defer stream.deinit();

    try stream.append("Partial **bold");
    const incomplete = stream.getIncompleteLine();
    try testing.expectEqualStrings("Partial **bold", incomplete);
}

test "streaming: finalize incomplete content" {
    var stream = StreamingMarkdown.init(testing.allocator);
    defer stream.deinit();

    try stream.append("This is incomplete");
    const segments = try stream.finalize();

    try testing.expect(segments.len > 0);
}

test "streaming: multiple chunks" {
    var stream = StreamingMarkdown.init(testing.allocator);
    defer stream.deinit();

    try stream.append("First");
    try stream.append(" line\n");
    try stream.append("Second line\n");

    const segments = stream.getSegments();
    try testing.expect(segments.len >= 2);
}

test "streaming: clear buffer" {
    var stream = StreamingMarkdown.init(testing.allocator);
    defer stream.deinit();

    try stream.append("Text\n");
    try testing.expect(stream.getSegments().len > 0);

    stream.clear();
    try testing.expectEqual(@as(usize, 0), stream.getSegments().len);
}

test "text: calculate height single line" {
    const segments = [_]@import("../render/markdown.zig").Segment{
        .{ .text = "Hello world", .style = .{} },
    };

    const height = text.calculateHeight(&segments, 80);
    try testing.expectEqual(@as(u16, 1), height);
}

test "text: calculate height with newlines" {
    const segments = [_]@import("../render/markdown.zig").Segment{
        .{ .text = "Line 1\nLine 2\nLine 3", .style = .{} },
    };

    const height = text.calculateHeight(&segments, 80);
    try testing.expectEqual(@as(u16, 3), height);
}

test "text: calculate height with wrapping" {
    const segments = [_]@import("../render/markdown.zig").Segment{
        .{ .text = "This is a very long line that will definitely wrap around", .style = .{} },
    };

    const height = text.calculateHeight(&segments, 20);
    try testing.expect(height > 1);
}

test "complex markdown document" {
    var renderer = MarkdownRenderer.init(testing.allocator);

    const markdown =
        \\# Main Title
        \\
        \\This is a **paragraph** with *italic* and `code` elements.
        \\
        \\## Features
        \\
        \\- First feature
        \\- Second feature with **bold**
        \\- Third feature
        \\
        \\### Code Example
        \\
        \\```zig
        \\const x = 10;
        \\```
        \\
        \\Check [documentation](https://example.com) for more.
    ;

    const segments = try renderer.render(markdown);
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);

    // Verify various elements are present
    var has_h1 = false;
    var has_bold = false;
    var has_italic = false;
    var has_code = false;
    var has_list = false;
    var has_link = false;

    for (segments) |seg| {
        if (seg.style.bold and seg.style.fg != null and seg.style.fg.?.index == 14) has_h1 = true;
        if (seg.style.bold and std.mem.eql(u8, seg.text, "paragraph")) has_bold = true;
        if (seg.style.italic and std.mem.eql(u8, seg.text, "italic")) has_italic = true;
        if (seg.style.reverse and std.mem.eql(u8, seg.text, "code")) has_code = true;
        if (std.mem.indexOf(u8, seg.text, "•") != null) has_list = true;
        if (seg.link != null) has_link = true;
    }

    try testing.expect(has_h1);
    try testing.expect(has_bold);
    try testing.expect(has_italic);
    try testing.expect(has_code);
    try testing.expect(has_list);
    try testing.expect(has_link);
}
