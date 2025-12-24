const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const EmptyState = struct {
    title: []const u8 = "Welcome to Plue",
    subtitle: []const u8 = "Type a message to start chatting",
    hints: []const Hint = &.{
        .{ .key = "/help", .description = "Show available commands" },
        .{ .key = "/model", .description = "Change the AI model" },
        .{ .key = "/new", .description = "Create a new session" },
    },

    pub const Hint = struct {
        key: []const u8,
        description: []const u8,
    };

    pub fn widget(self: *EmptyState) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = EmptyState.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *EmptyState = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Calculate vertical center
        const content_height: u16 = 2 + @as(u16, @intCast(self.hints.len)) + 2;
        const start_row = (size.height -| content_height) / 2;

        // Draw title
        const title_col = (size.width -| @as(u16, @intCast(self.title.len))) / 2;
        for (self.title, 0..) |char, i| {
            surface.writeCell(@intCast(title_col + i), start_row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Draw subtitle
        const sub_col = (size.width -| @as(u16, @intCast(self.subtitle.len))) / 2;
        for (self.subtitle, 0..) |char, i| {
            surface.writeCell(@intCast(sub_col + i), start_row + 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Draw hints
        var row = start_row + 3;
        for (self.hints) |hint| {
            const hint_text = hint.key ++ " - " ++ hint.description;
            const hint_col = (size.width -| @as(u16, @intCast(hint_text.len))) / 2;

            // Key part
            var col = hint_col;
            for (hint.key) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 12 }, .bold = true },
                });
                col += 1;
            }

            // Separator
            for (" - ") |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
                col += 1;
            }

            // Description
            for (hint.description) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 7 } },
                });
                col += 1;
            }

            row += 1;
        }

        return surface;
    }
};
