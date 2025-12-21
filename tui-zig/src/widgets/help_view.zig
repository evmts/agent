const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const registry = @import("../commands/registry.zig");

/// Widget for displaying help information
pub const HelpView = struct {
    scroll_offset: usize = 0,
    on_close: ?*const fn () void = null,

    pub fn widget(self: *HelpView) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = HelpView.handleEvent,
            .drawFn = HelpView.draw,
        };
    }

    fn handleEvent(userdata: ?*anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) void {
        const self: *HelpView = @ptrCast(@alignCast(userdata orelse return));

        switch (event) {
            .key_press => |key| {
                if (key.codepoint == vaxis.Key.escape or key.codepoint == 'q') {
                    if (self.on_close) |cb| cb();
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.page_up or key.codepoint == 'k') {
                    if (self.scroll_offset > 0) self.scroll_offset -= 1;
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.page_down or key.codepoint == 'j') {
                    self.scroll_offset += 1;
                    ctx.request_redraw = true;
                }
            },
            else => {},
        }
    }

    fn draw(userdata: ?*anyopaque, ctx: vxfw.DrawContext) vxfw.DrawResult {
        const self: *HelpView = @ptrCast(@alignCast(userdata orelse return .{ .surface = null }));
        const width: u31 = @intCast(ctx.max.width orelse 80);
        const height: u31 = @intCast(ctx.max.height orelse 24);

        var surface = vxfw.Surface.init(ctx.arena, self.widget(), width, height) catch return .{ .surface = null };

        // Title
        const title = "Help - Available Commands";
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(i + 2), 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Separator
        for (0..width) |col| {
            surface.writeCell(@intCast(col), 1, .{
                .char = .{ .grapheme = "-", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Commands
        var row: u16 = 3;
        var cmd_idx: usize = 0;
        for (registry.COMMANDS) |cmd| {
            // Skip if scrolled past
            if (cmd_idx < self.scroll_offset) {
                cmd_idx += 1;
                continue;
            }

            if (row >= height -| 2) break;

            // Command name
            var col: u16 = 2;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = "/", .width = 1 },
                .style = .{ .fg = .{ .index = 14 } },
            });
            col += 1;

            for (cmd.name) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 14 }, .bold = true },
                });
                col += 1;
            }

            // Args
            for (cmd.args) |arg| {
                col += 1;
                const bracket: []const u8 = if (arg.required) "<" else "[";
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = bracket, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
                col += 1;

                for (arg.name) |char| {
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = .{ .fg = .{ .index = 11 } },
                    });
                    col += 1;
                }

                const close_bracket: []const u8 = if (arg.required) ">" else "]";
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = close_bracket, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
                col += 1;
            }

            // Description (aligned)
            col = 25;
            for (cmd.description) |char| {
                if (col >= width -| 2) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 7 } },
                });
                col += 1;
            }

            row += 1;
            cmd_idx += 1;
        }

        // Footer hint
        const hint = "Press ESC or q to close, j/k to scroll";
        for (hint, 0..) |char, i| {
            surface.writeCell(@intCast(i + 2), @intCast(height -| 1), .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        return .{ .surface = surface };
    }

    /// Format help for a specific command
    pub fn formatCommandHelp(allocator: std.mem.Allocator, cmd: *const registry.Command) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);

        try result.appendSlice("/");
        try result.appendSlice(cmd.name);

        for (cmd.args) |arg| {
            try result.appendSlice(" ");
            if (arg.required) {
                try result.appendSlice("<");
            } else {
                try result.appendSlice("[");
            }
            try result.appendSlice(arg.name);
            if (arg.required) {
                try result.appendSlice(">");
            } else {
                try result.appendSlice("]");
            }
        }

        try result.appendSlice("\n\n");
        try result.appendSlice(cmd.description);

        if (cmd.aliases.len > 0) {
            try result.appendSlice("\n\nAliases: ");
            for (cmd.aliases, 0..) |alias, i| {
                if (i > 0) try result.appendSlice(", ");
                try result.appendSlice("/");
                try result.appendSlice(alias);
            }
        }

        if (cmd.examples.len > 0) {
            try result.appendSlice("\n\nExamples:\n");
            for (cmd.examples) |example| {
                try result.appendSlice("  ");
                try result.appendSlice(example);
                try result.appendSlice("\n");
            }
        }

        return result.toOwnedSlice();
    }
};
