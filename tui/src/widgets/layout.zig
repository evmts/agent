const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Allocator = std.mem.Allocator;

/// Vertical stack layout that allocates space to children
pub const VStack = struct {
    children: []const Child,
    spacing: u16 = 0,

    pub const Child = struct {
        widget: vxfw.Widget,
        height: Height,

        pub const Height = union(enum) {
            fixed: u16,
            flex: u16, // flex weight
            fill, // take remaining space
        };
    };

    pub fn widget(self: *const VStack) vxfw.Widget {
        return .{
            .userdata = @constCast(self),
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *const VStack = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    pub fn draw(self: *const VStack, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        std.debug.assert(ctx.max.height != null);
        std.debug.assert(ctx.max.width != null);

        if (self.children.len == 0) {
            return vxfw.Surface.init(ctx.arena, self.widget(), ctx.min);
        }

        const max_size = ctx.max.size();

        // Calculate fixed heights and flex totals
        var fixed_height: u16 = 0;
        var flex_total: u16 = 0;
        var fill_count: u16 = 0;

        for (self.children) |child| {
            switch (child.height) {
                .fixed => |h| fixed_height += h,
                .flex => |w| flex_total += w,
                .fill => fill_count += 1,
            }
        }

        // Add spacing
        if (self.children.len > 1) {
            const spacing_total = (self.children.len - 1) * self.spacing;
            fixed_height += @intCast(spacing_total);
        }

        const remaining = max_size.height -| fixed_height;
        const flex_unit: u16 = if (flex_total > 0) remaining / flex_total else 0;
        const fill_height: u16 = if (fill_count > 0)
            (remaining -| (flex_unit * flex_total)) / fill_count
        else
            0;

        // Draw children
        var children = try ctx.arena.alloc(vxfw.SubSurface, self.children.len);
        var y: u16 = 0;
        var max_width: u16 = 0;

        for (self.children, 0..) |child, i| {
            const child_height: u16 = switch (child.height) {
                .fixed => |h| h,
                .flex => |w| flex_unit * w,
                .fill => fill_height,
            };

            const child_ctx = ctx.withConstraints(
                .{ .width = 0, .height = child_height },
                .{ .width = max_size.width, .height = child_height },
            );

            const surf = try child.widget.draw(child_ctx);
            max_width = @max(max_width, surf.size.width);

            children[i] = .{
                .origin = .{ .row = y, .col = 0 },
                .surface = surf,
                .z_index = 0,
            };

            y += surf.size.height;
            if (i < self.children.len - 1) {
                y += self.spacing;
            }
        }

        return .{
            .size = .{ .width = max_width, .height = y },
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }
};

/// Horizontal stack layout
pub const HStack = struct {
    children: []const Child,
    spacing: u16 = 0,

    pub const Child = struct {
        widget: vxfw.Widget,
        width: Width,

        pub const Width = union(enum) {
            fixed: u16,
            flex: u16,
            fill,
        };
    };

    pub fn widget(self: *const HStack) vxfw.Widget {
        return .{
            .userdata = @constCast(self),
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *const HStack = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    pub fn draw(self: *const HStack, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        std.debug.assert(ctx.max.width != null);
        std.debug.assert(ctx.max.height != null);

        if (self.children.len == 0) {
            return vxfw.Surface.init(ctx.arena, self.widget(), ctx.min);
        }

        const max_size = ctx.max.size();

        var fixed_width: u16 = 0;
        var flex_total: u16 = 0;
        var fill_count: u16 = 0;

        for (self.children) |child| {
            switch (child.width) {
                .fixed => |w| fixed_width += w,
                .flex => |w| flex_total += w,
                .fill => fill_count += 1,
            }
        }

        if (self.children.len > 1) {
            const spacing_total = (self.children.len - 1) * self.spacing;
            fixed_width += @intCast(spacing_total);
        }

        const remaining = max_size.width -| fixed_width;
        const flex_unit: u16 = if (flex_total > 0) remaining / flex_total else 0;
        const fill_width: u16 = if (fill_count > 0)
            (remaining -| (flex_unit * flex_total)) / fill_count
        else
            0;

        var children = try ctx.arena.alloc(vxfw.SubSurface, self.children.len);
        var x: u16 = 0;
        var max_height: u16 = 0;

        for (self.children, 0..) |child, i| {
            const child_width: u16 = switch (child.width) {
                .fixed => |w| w,
                .flex => |w| flex_unit * w,
                .fill => fill_width,
            };

            const child_ctx = ctx.withConstraints(
                .{ .width = child_width, .height = 0 },
                .{ .width = child_width, .height = max_size.height },
            );

            const surf = try child.widget.draw(child_ctx);
            max_height = @max(max_height, surf.size.height);

            children[i] = .{
                .origin = .{ .row = 0, .col = x },
                .surface = surf,
                .z_index = 0,
            };

            x += surf.size.width;
            if (i < self.children.len - 1) {
                x += self.spacing;
            }
        }

        return .{
            .size = .{ .width = x, .height = max_height },
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }
};

test "VStack: basic layout" {
    const Text = @import("../../../libvaxis/src/vxfw/Text.zig");
    const text1: Text = .{ .text = "abc" };
    const text2: Text = .{ .text = "def" };

    const stack: VStack = .{
        .children = &.{
            .{ .widget = text1.widget(), .height = .{ .fixed = 1 } },
            .{ .widget = text2.widget(), .height = .{ .fixed = 1 } },
        },
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

    const surface = try stack.widget().draw(ctx);
    try std.testing.expectEqual(2, surface.size.height);
    try std.testing.expectEqual(2, surface.children.len);
}

test "HStack: basic layout" {
    const Text = @import("../../../libvaxis/src/vxfw/Text.zig");
    const text1: Text = .{ .text = "abc" };
    const text2: Text = .{ .text = "def" };

    const stack: HStack = .{
        .children = &.{
            .{ .widget = text1.widget(), .width = .{ .fixed = 3 } },
            .{ .widget = text2.widget(), .width = .{ .fixed = 3 } },
        },
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

    const surface = try stack.widget().draw(ctx);
    try std.testing.expectEqual(6, surface.size.width);
    try std.testing.expectEqual(2, surface.children.len);
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
