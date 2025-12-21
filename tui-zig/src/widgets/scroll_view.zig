const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Allocator = std.mem.Allocator;

/// Scrollable container widget
pub const ScrollView = struct {
    content: vxfw.Widget,
    scroll_offset: *usize,
    content_height: usize = 0,
    show_scrollbar: bool = true,

    pub fn widget(self: *ScrollView) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = typeErasedEventHandler,
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *ScrollView = @ptrCast(@alignCast(ptr));
        return self.handleEvent(ctx, event);
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *ScrollView = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    pub fn handleEvent(self: *ScrollView, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.page_up, .{})) {
                    self.scrollUp(10);
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.page_down, .{})) {
                    self.scrollDown(10);
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.home, .{})) {
                    self.scroll_offset.* = 0;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.end, .{})) {
                    self.scrollToEnd();
                    ctx.consumeAndRedraw();
                }
            },
            .mouse => |mouse| {
                switch (mouse.button) {
                    .wheel_up => {
                        self.scrollUp(3);
                        ctx.consumeAndRedraw();
                    },
                    .wheel_down => {
                        self.scrollDown(3);
                        ctx.consumeAndRedraw();
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    pub fn draw(self: *ScrollView, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        std.debug.assert(ctx.max.width != null);
        std.debug.assert(ctx.max.height != null);

        const max_size = ctx.max.size();

        // Calculate content width (leave room for scrollbar)
        const content_width = if (self.show_scrollbar) max_size.width -| 1 else max_size.width;

        // Draw content with unlimited height to measure
        const content_ctx = ctx.withConstraints(
            .{ .width = content_width, .height = 0 },
            .{ .width = content_width, .height = null }, // unlimited height
        );

        const content_surface = try self.content.draw(content_ctx);
        self.content_height = content_surface.size.height;

        // Clamp scroll offset
        const max_scroll = if (self.content_height > max_size.height)
            self.content_height - max_size.height
        else
            0;
        if (self.scroll_offset.* > max_scroll) {
            self.scroll_offset.* = max_scroll;
        }

        // Create viewport surface
        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), max_size);

        // Copy visible portion of content
        const visible_start = self.scroll_offset.*;
        const visible_end = @min(visible_start + max_size.height, self.content_height);

        if (content_surface.buffer.len > 0) {
            for (visible_start..visible_end) |src_row| {
                const dst_row = src_row - visible_start;
                if (dst_row >= max_size.height) break;

                for (0..content_width) |col| {
                    if (col >= content_surface.size.width) break;

                    const src_idx = src_row * content_surface.size.width + col;
                    if (src_idx < content_surface.buffer.len) {
                        const cell = content_surface.buffer[src_idx];
                        surface.writeCell(@intCast(col), @intCast(dst_row), cell);
                    }
                }
            }
        }

        // Draw scrollbar
        if (self.show_scrollbar and self.content_height > max_size.height) {
            self.drawScrollbar(&surface, max_size);
        }

        return surface;
    }

    fn drawScrollbar(self: *ScrollView, surface: *vxfw.Surface, size: vxfw.Size) void {
        const col = size.width - 1;

        // Calculate thumb position and size
        const thumb_height = @max(1, @min(size.height, size.height * size.height / @as(u16, @intCast(self.content_height))));
        const scroll_range = self.content_height - size.height;
        const thumb_pos: u16 = if (scroll_range > 0)
            @intCast(@min(size.height - thumb_height, self.scroll_offset.* * (size.height - thumb_height) / scroll_range))
        else
            0;

        // Draw track
        for (0..size.height) |row| {
            const is_thumb = row >= thumb_pos and row < thumb_pos + thumb_height;
            surface.writeCell(col, @intCast(row), .{
                .char = .{ .grapheme = if (is_thumb) "█" else "░", .width = 1 },
                .style = .{ .fg = .{ .index = if (is_thumb) 7 else 8 } },
            });
        }
    }

    fn scrollUp(self: *ScrollView, lines: usize) void {
        if (self.scroll_offset.* >= lines) {
            self.scroll_offset.* -= lines;
        } else {
            self.scroll_offset.* = 0;
        }
    }

    fn scrollDown(self: *ScrollView, lines: usize) void {
        self.scroll_offset.* += lines;
        // Clamping happens in draw
    }

    fn scrollToEnd(self: *ScrollView) void {
        self.scroll_offset.* = std.math.maxInt(usize);
        // Will be clamped in draw
    }

    pub fn ensureVisible(self: *ScrollView, row: usize, viewport_height: usize) void {
        if (row < self.scroll_offset.*) {
            self.scroll_offset.* = row;
        } else if (row >= self.scroll_offset.* + viewport_height) {
            self.scroll_offset.* = row -| (viewport_height - 1);
        }
    }
};

test "ScrollView: basic scrolling" {
    const Text = @import("../../../libvaxis/src/vxfw/Text.zig");
    const text: Text = .{ .text = "line1\nline2\nline3\nline4\nline5" };

    var offset: usize = 0;
    var scroll_view: ScrollView = .{
        .content = text.widget(),
        .scroll_offset = &offset,
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    vxfw.DrawContext.init(.unicode);

    const ctx: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 10, .height = 3 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    _ = try scroll_view.widget().draw(ctx);
    try std.testing.expectEqual(0, offset);

    scroll_view.scrollDown(2);
    _ = try scroll_view.widget().draw(ctx);
    try std.testing.expectEqual(2, offset);
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
