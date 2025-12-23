const std = @import("std");
const syntax = @import("syntax");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example Zig code
    const zig_code =
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    const x: u32 = 42;
        \\    std.debug.print("Hello, {d}!\n", .{x});
        \\}
    ;

    std.debug.print("\n=== Zig Syntax Highlighting ===\n", .{});
    const zig_segments = try syntax.highlight(allocator, zig_code, .zig);
    defer zig_segments.deinit();

    for (zig_segments.items) |seg| {
        std.debug.print("Token: '{s}' -> Color: {d}\n", .{ seg.text, seg.color });
    }

    // Example JavaScript code
    const js_code = "const foo = async () => { return 42; };";

    std.debug.print("\n=== JavaScript Syntax Highlighting ===\n", .{});
    const js_segments = try syntax.highlight(allocator, js_code, .javascript);
    defer js_segments.deinit();

    for (js_segments.items) |seg| {
        std.debug.print("Token: '{s}' -> Color: {d}\n", .{ seg.text, seg.color });
    }

    // Example Python code
    const python_code =
        \\def hello(name: str) -> int:
        \\    return 42
    ;

    std.debug.print("\n=== Python Syntax Highlighting ===\n", .{});
    const python_segments = try syntax.highlight(allocator, python_code, .python);
    defer python_segments.deinit();

    for (python_segments.items) |seg| {
        std.debug.print("Token: '{s}' -> Color: {d}\n", .{ seg.text, seg.color });
    }

    std.debug.print("\n=== Color Legend ===\n", .{});
    std.debug.print("12 (Blue)    - Keywords\n", .{});
    std.debug.print("10 (Green)   - Strings\n", .{});
    std.debug.print("13 (Magenta) - Numbers\n", .{});
    std.debug.print("8  (Gray)    - Comments\n", .{});
    std.debug.print("14 (Cyan)    - Functions\n", .{});
    std.debug.print("11 (Yellow)  - Types\n", .{});
    std.debug.print("7  (White)   - Default\n", .{});
}
