const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const Diff = @import("diff.zig").Diff;
const DiffStats = @import("diff.zig").DiffStats;
const Hunk = @import("diff.zig").Hunk;
const Line = @import("diff.zig").Line;

/// Color scheme for diff rendering
pub const DiffColors = struct {
    pub const addition: u8 = 10; // Green
    pub const deletion: u8 = 9; // Red
    pub const context: u8 = 7; // White
    pub const header: u8 = 14; // Cyan
    pub const line_number: u8 = 8; // Gray
    pub const file_path: u8 = 12; // Blue
};

/// Widget for rendering a unified diff
pub const DiffWidget = struct {
    diff: *Diff,

    pub fn init(diff: *Diff) DiffWidget {
        return .{ .diff = diff };
    }

    /// Calculate the height needed to render the diff
    pub fn height(self: *const DiffWidget, width: u16) u16 {
        _ = width;
        var h: u16 = 0;

        // File header (2 lines: path + stats)
        h += 2;

        // All hunks
        for (self.diff.hunks.items) |hunk| {
            h += @intCast(hunk.lines.items.len);
        }

        // Padding
        h += 1;

        return h;
    }

    /// Draw the diff widget
    pub fn draw(self: *DiffWidget, surface: *vxfw.Surface, start_row: u16, width: u16) void {
        var row = start_row;

        // Draw file header
        row += self.drawFileHeader(surface, row, width);

        // Draw stats
        row += self.drawStats(surface, row, width);

        // Draw hunks
        for (self.diff.hunks.items) |hunk| {
            row += self.drawHunk(surface, row, width, hunk);
        }
    }

    fn drawFileHeader(self: *DiffWidget, surface: *vxfw.Surface, row: u16, width: u16) u16 {
        const file_path = self.diff.new_file orelse self.diff.old_file orelse "<unknown>";

        // Determine if this is a new file, deleted file, or modified
        const prefix = if (self.diff.old_file == null)
            "+ "
        else if (self.diff.new_file == null)
            "- "
        else
            "~ ";

        const prefix_style = vaxis.Cell.Style{
            .fg = if (self.diff.old_file == null)
                .{ .index = DiffColors.addition }
            else if (self.diff.new_file == null)
                .{ .index = DiffColors.deletion }
            else
                .{ .index = DiffColors.file_path },
            .bold = true,
        };

        var col: u16 = 0;

        // Draw prefix
        for (prefix) |char| {
            if (col >= width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = prefix_style,
            });
            col += 1;
        }

        // Draw file path
        const path_style = vaxis.Cell.Style{
            .fg = .{ .index = DiffColors.file_path },
            .bold = true,
        };

        for (file_path) |char| {
            if (col >= width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = path_style,
            });
            col += 1;
        }

        return 1;
    }

    fn drawStats(self: *DiffWidget, surface: *vxfw.Surface, row: u16, width: u16) u16 {
        const stats = self.diff.getStats();

        var buf: [64]u8 = undefined;
        const stats_text = std.fmt.bufPrint(&buf, "+{d} -{d}", .{ stats.additions, stats.deletions }) catch "+? -?";

        var col: u16 = 2; // Indent

        // Draw additions in green
        const add_str = std.fmt.bufPrint(buf[0..32], "+{d}", .{stats.additions}) catch "+?";
        for (add_str) |char| {
            if (col >= width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = DiffColors.addition } },
            });
            col += 1;
        }

        // Space
        if (col < width) {
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = .{},
            });
            col += 1;
        }

        // Draw deletions in red
        const del_str = std.fmt.bufPrint(buf[32..], "-{d}", .{stats.deletions}) catch "-?";
        for (del_str) |char| {
            if (col >= width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = DiffColors.deletion } },
            });
            col += 1;
        }

        return 1;
    }

    fn drawHunk(self: *DiffWidget, surface: *vxfw.Surface, start_row: u16, width: u16, hunk: Hunk) u16 {
        _ = self;
        var row = start_row;

        var old_line_num = hunk.old_start;
        var new_line_num = hunk.new_start;

        for (hunk.lines.items) |line| {
            if (row >= start_row + 1000) break; // Safety limit

            switch (line.kind) {
                .header => {
                    self.drawHeaderLine(surface, row, width, line.content);
                    row += 1;
                },
                .context => {
                    self.drawContextLine(surface, row, width, old_line_num, new_line_num, line.content);
                    old_line_num += 1;
                    new_line_num += 1;
                    row += 1;
                },
                .addition => {
                    self.drawAdditionLine(surface, row, width, new_line_num, line.content);
                    new_line_num += 1;
                    row += 1;
                },
                .deletion => {
                    self.drawDeletionLine(surface, row, width, old_line_num, line.content);
                    old_line_num += 1;
                    row += 1;
                },
            }
        }

        return row - start_row;
    }

    fn drawHeaderLine(self: *DiffWidget, surface: *vxfw.Surface, row: u16, width: u16, content: []const u8) void {
        _ = self;
        const style = vaxis.Cell.Style{
            .fg = .{ .index = DiffColors.header },
            .bold = true,
        };

        var col: u16 = 0;
        for (content) |char| {
            if (col >= width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
            col += 1;
        }
    }

    fn drawContextLine(self: *DiffWidget, surface: *vxfw.Surface, row: u16, width: u16, old_num: u32, new_num: u32, content: []const u8) void {
        _ = self;
        var col: u16 = 0;

        // Draw line numbers (gutter)
        col += drawLineNumbers(surface, row, width, old_num, new_num);

        // Draw prefix (space)
        if (col < width) {
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = .{ .fg = .{ .index = DiffColors.context } },
            });
            col += 1;
        }

        // Draw content
        const style = vaxis.Cell.Style{ .fg = .{ .index = DiffColors.context } };
        for (content) |char| {
            if (col >= width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
            col += 1;
        }
    }

    fn drawAdditionLine(self: *DiffWidget, surface: *vxfw.Surface, row: u16, width: u16, new_num: u32, content: []const u8) void {
        _ = self;
        var col: u16 = 0;

        // Draw line numbers (empty old, new line number)
        col += drawLineNumbers(surface, row, width, null, new_num);

        // Draw prefix (+)
        if (col < width) {
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = "+", .width = 1 },
                .style = .{ .fg = .{ .index = DiffColors.addition }, .bold = true },
            });
            col += 1;
        }

        // Draw content
        const style = vaxis.Cell.Style{ .fg = .{ .index = DiffColors.addition } };
        for (content) |char| {
            if (col >= width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
            col += 1;
        }
    }

    fn drawDeletionLine(self: *DiffWidget, surface: *vxfw.Surface, row: u16, width: u16, old_num: u32, content: []const u8) void {
        _ = self;
        var col: u16 = 0;

        // Draw line numbers (old line number, empty new)
        col += drawLineNumbers(surface, row, width, old_num, null);

        // Draw prefix (-)
        if (col < width) {
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = "-", .width = 1 },
                .style = .{ .fg = .{ .index = DiffColors.deletion }, .bold = true },
            });
            col += 1;
        }

        // Draw content
        const style = vaxis.Cell.Style{ .fg = .{ .index = DiffColors.deletion } };
        for (content) |char| {
            if (col >= width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
            col += 1;
        }
    }
};

/// Draw line numbers in the gutter (old | new)
/// Returns the number of columns used
fn drawLineNumbers(surface: *vxfw.Surface, row: u16, width: u16, old_num: ?u32, new_num: ?u32) u16 {
    var col: u16 = 0;
    const gutter_style = vaxis.Cell.Style{ .fg = .{ .index = DiffColors.line_number }, .dim = true };

    var buf: [16]u8 = undefined;

    // Old line number (or empty)
    const old_str = if (old_num) |num|
        std.fmt.bufPrint(&buf, "{d:4}", .{num}) catch "   ?"
    else
        "    ";

    for (old_str) |char| {
        if (col >= width) return col;
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
            .style = gutter_style,
        });
        col += 1;
    }

    // Separator
    if (col < width) {
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = "|", .width = 1 },
            .style = gutter_style,
        });
        col += 1;
    }

    // New line number (or empty)
    const new_str = if (new_num) |num|
        std.fmt.bufPrint(&buf, "{d:4}", .{num}) catch "   ?"
    else
        "    ";

    for (new_str) |char| {
        if (col >= width) return col;
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
            .style = gutter_style,
        });
        col += 1;
    }

    // Space separator
    if (col < width) {
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = .{},
        });
        col += 1;
    }

    return col;
}

// Tests
test "diff widget height calculation" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/test.txt
        \\+++ b/test.txt
        \\@@ -1,3 +1,3 @@
        \\ line1
        \\-old line
        \\+new line
        \\ line3
    ;

    var diff = try @import("diff.zig").parse(allocator, diff_text);
    defer diff.deinit();

    var widget = DiffWidget.init(&diff);
    const h = widget.height(80);

    // File header (1) + stats (1) + hunk lines (5) + padding (1) = 8
    try std.testing.expectEqual(@as(u16, 8), h);
}

test "diff colors constants" {
    try std.testing.expectEqual(@as(u8, 10), DiffColors.addition);
    try std.testing.expectEqual(@as(u8, 9), DiffColors.deletion);
    try std.testing.expectEqual(@as(u8, 7), DiffColors.context);
    try std.testing.expectEqual(@as(u8, 14), DiffColors.header);
    try std.testing.expectEqual(@as(u8, 8), DiffColors.line_number);
    try std.testing.expectEqual(@as(u8, 12), DiffColors.file_path);
}
