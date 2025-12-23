const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Allocator = std.mem.Allocator;

/// Border decoration widget
pub const Border = struct {
    child: vxfw.Widget,
    title: ?[]const u8 = null,
    style: Style = .single,
    color: vaxis.Color = .default,

    pub const Style = enum {
        none,
        single,
        double,
        rounded,
        heavy,
    };

    const Glyphs = struct {
        top_left: []const u8,
        top_right: []const u8,
        bottom_left: []const u8,
        bottom_right: []const u8,
        horizontal: []const u8,
        vertical: []const u8,
    };

    const glyphs = struct {
        const single: Glyphs = .{
            .top_left = "┌",
            .top_right = "┐",
            .bottom_left = "└",
            .bottom_right = "┘",
            .horizontal = "─",
            .vertical = "│",
        };
        const double: Glyphs = .{
            .top_left = "╔",
            .top_right = "╗",
            .bottom_left = "╚",
            .bottom_right = "╝",
            .horizontal = "═",
            .vertical = "║",
        };
        const rounded: Glyphs = .{
            .top_left = "╭",
            .top_right = "╮",
            .bottom_left = "╰",
            .bottom_right = "╯",
            .horizontal = "─",
            .vertical = "│",
        };
        const heavy: Glyphs = .{
            .top_left = "┏",
            .top_right = "┓",
            .bottom_left = "┗",
            .bottom_right = "┛",
            .horizontal = "━",
            .vertical = "┃",
        };
    };

    pub fn widget(self: *Border) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *Border = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    pub fn draw(self: *Border, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        if (self.style == .none) {
            return try self.child.draw(ctx);
        }

        std.debug.assert(ctx.max.width != null);
        std.debug.assert(ctx.max.height != null);

        const max_size = ctx.max.size();

        // Draw child in inner area (shrink by border width)
        const inner_width = max_size.width -| 2;
        const inner_height = max_size.height -| 2;

        const inner_ctx = ctx.withConstraints(
            .{ .width = inner_width, .height = inner_height },
            .{ .width = inner_width, .height = inner_height },
        );

        const child_surface = try self.child.draw(inner_ctx);

        const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
        children[0] = .{
            .origin = .{ .row = 1, .col = 1 },
            .surface = child_surface,
            .z_index = 0,
        };

        // Create surface with border
        const surface_size: vxfw.Size = .{
            .width = child_surface.size.width + 2,
            .height = child_surface.size.height + 2,
        };

        var surface = try vxfw.Surface.initWithChildren(ctx.arena, self.widget(), surface_size, children);

        const g = switch (self.style) {
            .single => glyphs.single,
            .double => glyphs.double,
            .rounded => glyphs.rounded,
            .heavy => glyphs.heavy,
            .none => unreachable,
        };

        const border_style = vaxis.Cell.Style{ .fg = self.color };

        const right_edge = surface_size.width - 1;
        const bottom_edge = surface_size.height - 1;

        // Draw corners
        surface.writeCell(0, 0, .{
            .char = .{ .grapheme = g.top_left, .width = 1 },
            .style = border_style,
        });
        surface.writeCell(right_edge, 0, .{
            .char = .{ .grapheme = g.top_right, .width = 1 },
            .style = border_style,
        });
        surface.writeCell(0, bottom_edge, .{
            .char = .{ .grapheme = g.bottom_left, .width = 1 },
            .style = border_style,
        });
        surface.writeCell(right_edge, bottom_edge, .{
            .char = .{ .grapheme = g.bottom_right, .width = 1 },
            .style = border_style,
        });

        // Draw horizontal lines
        for (1..surface_size.width - 1) |col| {
            surface.writeCell(@intCast(col), 0, .{
                .char = .{ .grapheme = g.horizontal, .width = 1 },
                .style = border_style,
            });
            surface.writeCell(@intCast(col), bottom_edge, .{
                .char = .{ .grapheme = g.horizontal, .width = 1 },
                .style = border_style,
            });
        }

        // Draw vertical lines
        for (1..surface_size.height - 1) |row| {
            surface.writeCell(0, @intCast(row), .{
                .char = .{ .grapheme = g.vertical, .width = 1 },
                .style = border_style,
            });
            surface.writeCell(right_edge, @intCast(row), .{
                .char = .{ .grapheme = g.vertical, .width = 1 },
                .style = border_style,
            });
        }

        // Draw title if present
        if (self.title) |title| {
            const title_start: u16 = 2;
            const title_style = vaxis.Cell.Style{ .fg = self.color, .bold = true };

            var col = title_start;
            for (title) |char| {
                if (col >= surface_size.width - 2) break;
                surface.writeCell(col, 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = title_style,
                });
                col += 1;
            }
        }

        return surface;
    }
};

test "Border: basic decoration" {
    const Text = @import("../../../libvaxis/src/vxfw/Text.zig");
    const text: Text = .{ .text = "abc" };

    var border: Border = .{
        .child = text.widget(),
        .style = .single,
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    vxfw.DrawContext.init(.unicode);

    const ctx: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 10, .height = 10 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    const surface = try border.widget().draw(ctx);
    // Border adds 2 to width and height
    try std.testing.expectEqual(5, surface.size.width);
    try std.testing.expectEqual(3, surface.size.height);
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
