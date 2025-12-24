const std = @import("std");
const markdown = @import("../render/markdown.zig");
const syntax = @import("../render/syntax.zig");

test "markdown code block with zig syntax highlighting" {
    const allocator = std.testing.allocator;
    var renderer = markdown.MarkdownRenderer.init(allocator);

    const md =
        \\```zig
        \\const x: u32 = 42;
        \\pub fn main() void {}
        \\```
    ;

    const segments = try renderer.render(md);
    defer allocator.free(segments);

    // Should have multiple segments with different colors
    var has_keyword = false;
    var has_type = false;
    var has_number = false;

    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "const") or std.mem.eql(u8, seg.text, "pub") or std.mem.eql(u8, seg.text, "fn")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.keyword) {
                    has_keyword = true;
                }
            }
        }
        if (std.mem.eql(u8, seg.text, "u32")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.type) {
                    has_type = true;
                }
            }
        }
        if (std.mem.eql(u8, seg.text, "42")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.number) {
                    has_number = true;
                }
            }
        }
    }

    try std.testing.expect(has_keyword);
    try std.testing.expect(has_type);
    try std.testing.expect(has_number);
}

test "markdown code block with javascript syntax highlighting" {
    const allocator = std.testing.allocator;
    var renderer = markdown.MarkdownRenderer.init(allocator);

    const md =
        \\```javascript
        \\const foo = async () => { return 42; };
        \\```
    ;

    const segments = try renderer.render(md);
    defer allocator.free(segments);

    var has_const = false;
    var has_async = false;

    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "const")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.keyword) {
                    has_const = true;
                }
            }
        }
        if (std.mem.eql(u8, seg.text, "async")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.keyword) {
                    has_async = true;
                }
            }
        }
    }

    try std.testing.expect(has_const);
    try std.testing.expect(has_async);
}

test "markdown code block with python syntax highlighting" {
    const allocator = std.testing.allocator;
    var renderer = markdown.MarkdownRenderer.init(allocator);

    const md =
        \\```python
        \\def hello():
        \\    return 42
        \\```
    ;

    const segments = try renderer.render(md);
    defer allocator.free(segments);

    var has_def = false;
    var has_return = false;

    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "def")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.keyword) {
                    has_def = true;
                }
            }
        }
        if (std.mem.eql(u8, seg.text, "return")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.keyword) {
                    has_return = true;
                }
            }
        }
    }

    try std.testing.expect(has_def);
    try std.testing.expect(has_return);
}

test "markdown code block without language" {
    const allocator = std.testing.allocator;
    var renderer = markdown.MarkdownRenderer.init(allocator);

    const md =
        \\```
        \\some code 123 "string"
        \\```
    ;

    const segments = try renderer.render(md);
    defer allocator.free(segments);

    // Should still have segments (numbers and strings highlighted)
    try std.testing.expect(segments.len > 0);

    var has_number = false;
    var has_string = false;

    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "123")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.number) {
                    has_number = true;
                }
            }
        }
        if (std.mem.eql(u8, seg.text, "\"string\"")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.string) {
                    has_string = true;
                }
            }
        }
    }

    try std.testing.expect(has_number);
    try std.testing.expect(has_string);
}

test "markdown mixed content with code block" {
    const allocator = std.testing.allocator;
    var renderer = markdown.MarkdownRenderer.init(allocator);

    const md =
        \\# Header
        \\
        \\Some text with **bold** and `inline code`.
        \\
        \\```zig
        \\const x = 42;
        \\```
        \\
        \\More text.
    ;

    const segments = try renderer.render(md);
    defer allocator.free(segments);

    // Should have header, bold, inline code, and syntax-highlighted code
    try std.testing.expect(segments.len > 10);

    var has_header = false;
    var has_bold = false;
    var has_inline_code = false;
    var has_zig_keyword = false;

    for (segments) |seg| {
        if (std.mem.indexOf(u8, seg.text, "Header") != null and seg.style.bold) {
            has_header = true;
        }
        if (std.mem.eql(u8, seg.text, "bold") and seg.style.bold) {
            has_bold = true;
        }
        if (std.mem.eql(u8, seg.text, "inline code") and seg.style.reverse) {
            has_inline_code = true;
        }
        if (std.mem.eql(u8, seg.text, "const")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.keyword) {
                    has_zig_keyword = true;
                }
            }
        }
    }

    try std.testing.expect(has_header);
    try std.testing.expect(has_bold);
    try std.testing.expect(has_inline_code);
    try std.testing.expect(has_zig_keyword);
}

test "markdown multiline code block" {
    const allocator = std.testing.allocator;
    var renderer = markdown.MarkdownRenderer.init(allocator);

    const md =
        \\```rust
        \\fn main() {
        \\    let x: u32 = 42;
        \\    println!("hello");
        \\}
        \\```
    ;

    const segments = try renderer.render(md);
    defer allocator.free(segments);

    var has_fn = false;
    var has_let = false;
    var has_u32 = false;

    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "fn")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.keyword) has_fn = true;
            }
        }
        if (std.mem.eql(u8, seg.text, "let")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.keyword) has_let = true;
            }
        }
        if (std.mem.eql(u8, seg.text, "u32")) {
            if (seg.style.fg) |fg| {
                if (fg.index == syntax.Colors.type) has_u32 = true;
            }
        }
    }

    try std.testing.expect(has_fn);
    try std.testing.expect(has_let);
    try std.testing.expect(has_u32);
}
