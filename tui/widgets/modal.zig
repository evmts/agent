const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const Border = @import("border.zig").Border;

const Allocator = std.mem.Allocator;

/// Modal overlay widget
pub const Modal = struct {
    content: vxfw.Widget,
    title: []const u8,
    width: Width = .{ .percentage = 60 },
    height: Height = .{ .percentage = 60 },
    on_close: ?*const fn () void = null,

    pub const Width = union(enum) {
        fixed: u16,
        percentage: u8,
    };

    pub const Height = union(enum) {
        fixed: u16,
        percentage: u8,
    };

    pub fn widget(self: *Modal) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = typeErasedEventHandler,
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *Modal = @ptrCast(@alignCast(ptr));
        return self.handleEvent(ctx, event);
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *Modal = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    pub fn handleEvent(self: *Modal, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.escape, .{})) {
                    if (self.on_close) |close| {
                        close();
                    }
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    pub fn draw(self: *Modal, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        std.debug.assert(ctx.max.width != null);
        std.debug.assert(ctx.max.height != null);

        const max_size = ctx.max.size();

        // Calculate modal size
        const modal_width: u16 = switch (self.width) {
            .fixed => |w| @min(w, max_size.width),
            .percentage => |p| @intCast(@as(u32, max_size.width) * p / 100),
        };
        const modal_height: u16 = switch (self.height) {
            .fixed => |h| @min(h, max_size.height),
            .percentage => |p| @intCast(@as(u32, max_size.height) * p / 100),
        };

        // Calculate position (centered)
        const x = (max_size.width -| modal_width) / 2;
        const y = (max_size.height -| modal_height) / 2;

        // Create surface with dimmed background
        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), max_size);

        // Draw dim background
        const dim_style = vaxis.Cell.Style{ .bg = .{ .rgb = .{ 0, 0, 0 } }, .dim = true };
        for (0..max_size.height) |row| {
            for (0..max_size.width) |col| {
                surface.writeCell(@intCast(col), @intCast(row), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = dim_style,
                });
            }
        }

        // Draw modal content with border
        var border = Border{
            .child = self.content,
            .title = self.title,
            .style = .rounded,
            .color = .{ .index = 14 }, // Cyan
        };

        const modal_ctx = ctx.withConstraints(
            .{ .width = modal_width, .height = modal_height },
            .{ .width = modal_width, .height = modal_height },
        );

        const modal_surface = try border.widget().draw(modal_ctx);

        const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
        children[0] = .{
            .origin = .{ .row = y, .col = x },
            .surface = modal_surface,
            .z_index = 1,
        };

        return .{
            .size = max_size,
            .widget = self.widget(),
            .buffer = surface.buffer,
            .children = children,
        };
    }
};

test "Modal: basic overlay" {
    const Text = @import("../../../libvaxis/src/vxfw/Text.zig");
    const text: Text = .{ .text = "Modal Content" };

    var modal: Modal = .{
        .content = text.widget(),
        .title = "Test Modal",
        .width = .{ .fixed = 30 },
        .height = .{ .fixed = 10 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    vxfw.DrawContext.init(.unicode);

    const ctx: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 80, .height = 24 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    const surface = try modal.widget().draw(ctx);
    // Modal surface is full screen
    try std.testing.expectEqual(80, surface.size.width);
    try std.testing.expectEqual(24, surface.size.height);
    // Has 1 child (the modal content)
    try std.testing.expectEqual(1, surface.children.len);
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
