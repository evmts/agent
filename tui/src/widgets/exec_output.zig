const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

/// Widget for displaying command execution output with ANSI support
pub const ExecOutput = struct {
    allocator: std.mem.Allocator,
    command: []const u8,
    working_dir: ?[]const u8 = null,
    output: std.ArrayList(u8),
    is_running: bool = false,
    exit_code: ?i32 = null,
    start_time: ?i64 = null,

    pub fn init(allocator: std.mem.Allocator, command: []const u8) ExecOutput {
        return .{
            .allocator = allocator,
            .command = command,
            .output = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *ExecOutput) void {
        self.output.deinit();
    }

    pub fn appendOutput(self: *ExecOutput, data: []const u8) !void {
        try self.output.appendSlice(data);
    }

    pub fn widget(self: *ExecOutput) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = ExecOutput.draw,
        };
    }

    fn draw(userdata: ?*anyopaque, ctx: vxfw.DrawContext) vxfw.DrawResult {
        const self: *ExecOutput = @ptrCast(@alignCast(userdata orelse return .{ .surface = null }));
        const width: u31 = @intCast(ctx.max.width orelse 80);
        const max_height: u31 = @intCast(ctx.max.height orelse 24);

        // Calculate height based on output
        const content_height = self.calculateHeight(width);
        const height: u31 = @min(content_height + 2, max_height);

        var surface = vxfw.Surface.init(ctx.arena, self.widget(), width, height) catch return .{ .surface = null };

        var row: u16 = 0;

        // Command header
        row = self.drawCommandHeader(&surface, row, @intCast(width));

        // Output with ANSI parsing
        row = self.drawOutput(&surface, row, @intCast(width), @intCast(height));

        // Footer with exit code
        if (self.exit_code != null and row < height) {
            self.drawFooter(&surface, row, @intCast(width));
        }

        return .{ .surface = surface };
    }

    fn drawCommandHeader(self: *ExecOutput, surface: *vxfw.Surface, row: u16, width: u16) u16 {
        var col: u16 = 0;

        // Prompt
        const prompt = "$ ";
        for (prompt) |char| {
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 10 }, .bold = true },
            });
            col += 1;
        }

        // Command
        for (self.command) |char| {
            if (col >= width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 15 } },
            });
            col += 1;
        }

        // Running indicator
        if (self.is_running) {
            const indicator = " [running]";
            for (indicator) |char| {
                if (col >= width) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 14 } },
                });
                col += 1;
            }
        }

        return row + 1;
    }

    fn drawOutput(self: *ExecOutput, surface: *vxfw.Surface, start_row: u16, width: u16, max_height: u16) u16 {
        var row = start_row;
        var col: u16 = 0;
        var current_style = vaxis.Cell.Style{};

        var i: usize = 0;
        const output = self.output.items;

        while (i < output.len and row < max_height -| 1) {
            const char = output[i];

            // Handle ANSI escape sequences
            if (char == 0x1b and i + 1 < output.len and output[i + 1] == '[') {
                i += 2;
                const result = self.parseAnsiSequence(output[i..]);
                current_style = self.mergeStyles(current_style, result.style);
                i += result.consumed;
                continue;
            }

            // Handle newline
            if (char == '\n') {
                row += 1;
                col = 0;
                i += 1;
                continue;
            }

            // Handle carriage return
            if (char == '\r') {
                col = 0;
                i += 1;
                continue;
            }

            // Handle tab
            if (char == '\t') {
                const tab_width = 4 - (col % 4);
                col += tab_width;
                i += 1;
                continue;
            }

            // Skip non-printable characters
            if (char < 32 and char != '\t') {
                i += 1;
                continue;
            }

            // Wrap
            if (col >= width) {
                row += 1;
                col = 0;
            }

            // Draw character
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = current_style,
            });
            col += 1;
            i += 1;
        }

        return row + 1;
    }

    const AnsiResult = struct {
        style: vaxis.Cell.Style,
        consumed: usize,
    };

    fn parseAnsiSequence(self: *ExecOutput, data: []const u8) AnsiResult {
        _ = self;
        var style = vaxis.Cell.Style{};
        var num: u8 = 0;
        var consumed: usize = 0;

        for (data, 0..) |char, i| {
            consumed = i + 1;
            if (char >= '0' and char <= '9') {
                num = num *| 10 +| (char - '0');
            } else if (char == ';' or char == 'm') {
                // Apply SGR code
                switch (num) {
                    0 => style = .{}, // Reset
                    1 => style.bold = true,
                    2 => style.dim = true,
                    3 => style.italic = true,
                    4 => style.ul_style = .single,
                    7 => style.reverse = true,
                    9 => style.strikethrough = true,
                    30 => style.fg = .{ .index = 0 },
                    31 => style.fg = .{ .index = 1 },
                    32 => style.fg = .{ .index = 2 },
                    33 => style.fg = .{ .index = 3 },
                    34 => style.fg = .{ .index = 4 },
                    35 => style.fg = .{ .index = 5 },
                    36 => style.fg = .{ .index = 6 },
                    37 => style.fg = .{ .index = 7 },
                    40 => style.bg = .{ .index = 0 },
                    41 => style.bg = .{ .index = 1 },
                    42 => style.bg = .{ .index = 2 },
                    43 => style.bg = .{ .index = 3 },
                    44 => style.bg = .{ .index = 4 },
                    45 => style.bg = .{ .index = 5 },
                    46 => style.bg = .{ .index = 6 },
                    47 => style.bg = .{ .index = 7 },
                    90 => style.fg = .{ .index = 8 },
                    91 => style.fg = .{ .index = 9 },
                    92 => style.fg = .{ .index = 10 },
                    93 => style.fg = .{ .index = 11 },
                    94 => style.fg = .{ .index = 12 },
                    95 => style.fg = .{ .index = 13 },
                    96 => style.fg = .{ .index = 14 },
                    97 => style.fg = .{ .index = 15 },
                    else => {},
                }
                num = 0;

                if (char == 'm') {
                    return .{ .style = style, .consumed = consumed };
                }
            } else {
                return .{ .style = style, .consumed = consumed };
            }
        }

        return .{ .style = style, .consumed = consumed };
    }

    fn mergeStyles(self: *ExecOutput, base: vaxis.Cell.Style, new: vaxis.Cell.Style) vaxis.Cell.Style {
        _ = self;
        var result = base;
        if (new.fg != .default) result.fg = new.fg;
        if (new.bg != .default) result.bg = new.bg;
        if (new.bold) result.bold = true;
        if (new.dim) result.dim = true;
        if (new.italic) result.italic = true;
        if (new.reverse) result.reverse = true;
        if (new.strikethrough) result.strikethrough = true;
        if (new.ul_style != .off) result.ul_style = new.ul_style;
        return result;
    }

    fn drawFooter(self: *ExecOutput, surface: *vxfw.Surface, row: u16, width: u16) void {
        var col: u16 = 0;

        // Separator
        for (0..width) |c| {
            surface.writeCell(@intCast(c), row, .{
                .char = .{ .grapheme = "-", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Exit code
        if (self.exit_code) |code| {
            const is_success = code == 0;
            const icon: []const u8 = if (is_success) "[ok]" else "[fail]";
            const color: vaxis.Color = if (is_success) .{ .index = 10 } else .{ .index = 9 };

            for (icon) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = color },
                });
                col += 1;
            }

            if (code != 0) {
                const code_text = " exit ";
                for (code_text) |char| {
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = .{ .fg = .{ .index = 8 } },
                    });
                    col += 1;
                }

                // Write exit code digits
                var code_buf: [16]u8 = undefined;
                const code_str = std.fmt.bufPrint(&code_buf, "{d}", .{code}) catch "?";
                for (code_str) |char| {
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = .{ .fg = .{ .index = 9 } },
                    });
                    col += 1;
                }
            }
        }
    }

    fn calculateHeight(self: *ExecOutput, width: u31) u31 {
        if (width == 0) return 1;
        var lines: u31 = 1;
        var col: u31 = 0;

        for (self.output.items) |char| {
            if (char == '\n') {
                lines += 1;
                col = 0;
            } else {
                col += 1;
                if (col >= width) {
                    lines += 1;
                    col = 0;
                }
            }
        }

        return lines;
    }
};
