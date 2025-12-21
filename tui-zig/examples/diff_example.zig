const std = @import("std");
const diff_module = @import("../src/render/diff.zig");
const DiffWidget = @import("../src/render/diff_widget.zig").DiffWidget;

/// Example usage of the diff parser and widget
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example diff text (like from git diff)
    const example_diff =
        \\--- a/src/main.zig
        \\+++ b/src/main.zig
        \\@@ -1,7 +1,8 @@
        \\ const std = @import("std");
        \\
        \\ pub fn main() !void {
        \\-    std.debug.print("Hello, world!\n", .{});
        \\+    const message = "Hello, Plue!";
        \\+    std.debug.print("{s}\n", .{message});
        \\ }
    ;

    // Parse the diff
    var diff = try diff_module.parse(allocator, example_diff);
    defer diff.deinit();

    // Print statistics
    const stats = diff.getStats();
    std.debug.print("Diff Statistics:\n", .{});
    std.debug.print("  Files changed: {d}\n", .{stats.files_changed});
    std.debug.print("  Lines added: {d}\n", .{stats.additions});
    std.debug.print("  Lines deleted: {d}\n", .{stats.deletions});
    std.debug.print("\n", .{});

    // Print file paths
    std.debug.print("Files:\n", .{});
    std.debug.print("  Old: {s}\n", .{diff.old_file orelse "N/A"});
    std.debug.print("  New: {s}\n", .{diff.new_file orelse "N/A"});
    std.debug.print("\n", .{});

    // Print hunks
    std.debug.print("Hunks: {d}\n", .{diff.hunks.items.len});
    for (diff.hunks.items, 0..) |hunk, i| {
        std.debug.print("  Hunk {d}:\n", .{i + 1});
        std.debug.print("    Old: lines {d}-{d}\n", .{ hunk.old_start, hunk.old_start + hunk.old_count - 1 });
        std.debug.print("    New: lines {d}-{d}\n", .{ hunk.new_start, hunk.new_start + hunk.new_count - 1 });
        std.debug.print("    Lines: {d}\n", .{hunk.lines.items.len});

        // Print line details
        for (hunk.lines.items) |line| {
            const prefix = switch (line.kind) {
                .header => "@@",
                .addition => "+ ",
                .deletion => "- ",
                .context => "  ",
            };
            std.debug.print("      {s}{s}\n", .{ prefix, line.content });
        }
    }

    // Note: To actually render the diff in a TUI, you would:
    // 1. Create a vxfw.Surface
    // 2. Create a DiffWidget with the parsed diff
    // 3. Call widget.draw(surface, row, width)
    std.debug.print("\nTo render in TUI:\n", .{});
    std.debug.print("  var widget = DiffWidget.init(&diff);\n", .{});
    std.debug.print("  widget.draw(surface, start_row, width);\n", .{});
}
