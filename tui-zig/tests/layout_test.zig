const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const VStack = @import("../src/widgets/layout.zig").VStack;
const HStack = @import("../src/widgets/layout.zig").HStack;
const ScrollView = @import("../src/widgets/scroll_view.zig").ScrollView;
const Border = @import("../src/widgets/border.zig").Border;
const Modal = @import("../src/widgets/modal.zig").Modal;

const Text = @import("../../libvaxis/src/vxfw/Text.zig");

test "VStack: fixed height allocation" {
    const text1: Text = .{ .text = "abc" };
    const text2: Text = .{ .text = "def" };
    const text3: Text = .{ .text = "ghi" };

    const stack: VStack = .{
        .children = &.{
            .{ .widget = text1.widget(), .height = .{ .fixed = 2 } },
            .{ .widget = text2.widget(), .height = .{ .fixed = 3 } },
            .{ .widget = text3.widget(), .height = .{ .fixed = 1 } },
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

    // Total height should be 2 + 3 + 1 = 6
    try std.testing.expectEqual(6, surface.size.height);
    try std.testing.expectEqual(3, surface.children.len);

    // Check child positions
    try std.testing.expectEqual(0, surface.children[0].origin.row);
    try std.testing.expectEqual(2, surface.children[1].origin.row);
    try std.testing.expectEqual(5, surface.children[2].origin.row);
}

test "VStack: flex height allocation" {
    const text1: Text = .{ .text = "a" };
    const text2: Text = .{ .text = "b" };

    const stack: VStack = .{
        .children = &.{
            .{ .widget = text1.widget(), .height = .{ .fixed = 2 } },
            .{ .widget = text2.widget(), .height = .{ .flex = 1 } },
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

    // First child is fixed at 2, second gets remaining 8
    try std.testing.expectEqual(2, surface.children.len);
    try std.testing.expectEqual(2, surface.children[0].surface.size.height);
    try std.testing.expectEqual(8, surface.children[1].surface.size.height);
}

test "VStack: fill height allocation" {
    const text1: Text = .{ .text = "a" };
    const text2: Text = .{ .text = "b" };
    const text3: Text = .{ .text = "c" };

    const stack: VStack = .{
        .children = &.{
            .{ .widget = text1.widget(), .height = .{ .fixed = 2 } },
            .{ .widget = text2.widget(), .height = .fill },
            .{ .widget = text3.widget(), .height = .fill },
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

    // First is 2, remaining 8 split between two fill children = 4 each
    try std.testing.expectEqual(3, surface.children.len);
    try std.testing.expectEqual(2, surface.children[0].surface.size.height);
    try std.testing.expectEqual(4, surface.children[1].surface.size.height);
    try std.testing.expectEqual(4, surface.children[2].surface.size.height);
}

test "HStack: fixed width allocation" {
    const text1: Text = .{ .text = "abc" };
    const text2: Text = .{ .text = "def" };

    const stack: HStack = .{
        .children = &.{
            .{ .widget = text1.widget(), .width = .{ .fixed = 5 } },
            .{ .widget = text2.widget(), .width = .{ .fixed = 5 } },
        },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    vxfw.DrawContext.init(.unicode);

    const ctx: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 20, .height = 10 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    const surface = try stack.widget().draw(ctx);

    // Total width should be 5 + 5 = 10
    try std.testing.expectEqual(10, surface.size.width);
    try std.testing.expectEqual(2, surface.children.len);

    // Check child positions
    try std.testing.expectEqual(0, surface.children[0].origin.col);
    try std.testing.expectEqual(5, surface.children[1].origin.col);
}

test "ScrollView: scroll offset clamping" {
    const text: Text = .{ .text = "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10" };

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
        .max = .{ .width = 20, .height = 5 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    // Initial draw
    _ = try scroll_view.widget().draw(ctx);
    try std.testing.expectEqual(0, offset);

    // Scroll down
    scroll_view.scrollDown(3);
    _ = try scroll_view.widget().draw(ctx);
    try std.testing.expectEqual(3, offset);

    // Scroll to end
    scroll_view.scrollToEnd();
    _ = try scroll_view.widget().draw(ctx);
    // Content is 10 lines, viewport is 5, so max offset is 5
    try std.testing.expectEqual(5, offset);

    // Scroll up
    scroll_view.scrollUp(2);
    _ = try scroll_view.widget().draw(ctx);
    try std.testing.expectEqual(3, offset);

    // Scroll to top
    scroll_view.scrollUp(10);
    try std.testing.expectEqual(0, offset);
}

test "ScrollView: ensureVisible" {
    const text: Text = .{ .text = "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10" };

    var offset: usize = 0;
    var scroll_view: ScrollView = .{
        .content = text.widget(),
        .scroll_offset = &offset,
    };

    // Ensure row 7 is visible with viewport height of 5
    scroll_view.ensureVisible(7, 5);
    try std.testing.expectEqual(3, offset); // Scroll to show row 7 at bottom

    // Ensure row 2 is visible
    scroll_view.ensureVisible(2, 5);
    try std.testing.expectEqual(2, offset); // Scroll to show row 2 at top

    // Row already visible - no change
    const prev_offset = offset;
    scroll_view.ensureVisible(3, 5);
    try std.testing.expectEqual(prev_offset, offset);
}

test "Border: all styles render correctly" {
    const text: Text = .{ .text = "test" };

    const styles = [_]Border.Style{ .single, .double, .rounded, .heavy };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    vxfw.DrawContext.init(.unicode);

    for (styles) |style| {
        var border: Border = .{
            .child = text.widget(),
            .style = style,
        };

        const ctx: vxfw.DrawContext = .{
            .arena = arena.allocator(),
            .min = .{},
            .max = .{ .width = 10, .height = 10 },
            .cell_size = .{ .width = 10, .height = 20 },
        };

        const surface = try border.widget().draw(ctx);

        // Border adds 2 to each dimension
        try std.testing.expect(surface.size.width >= 2);
        try std.testing.expect(surface.size.height >= 2);
        try std.testing.expectEqual(1, surface.children.len);
    }
}

test "Border: with title" {
    const text: Text = .{ .text = "content" };

    var border: Border = .{
        .child = text.widget(),
        .style = .rounded,
        .title = "Test Title",
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    vxfw.DrawContext.init(.unicode);

    const ctx: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 20, .height = 10 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    const surface = try border.widget().draw(ctx);
    try std.testing.expect(surface.size.width > 0);
    try std.testing.expect(surface.size.height > 0);
}

test "Modal: centered positioning" {
    const text: Text = .{ .text = "Modal content" };

    var modal: Modal = .{
        .content = text.widget(),
        .title = "Test",
        .width = .{ .fixed = 40 },
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

    // Modal should be full screen
    try std.testing.expectEqual(80, surface.size.width);
    try std.testing.expectEqual(24, surface.size.height);

    // Should have 1 child (the modal content)
    try std.testing.expectEqual(1, surface.children.len);

    // Modal should be centered: (80 - 40) / 2 = 20 for col
    // (24 - 10) / 2 = 7 for row
    try std.testing.expectEqual(20, surface.children[0].origin.col);
    try std.testing.expectEqual(7, surface.children[0].origin.row);
}

test "Modal: percentage sizing" {
    const text: Text = .{ .text = "content" };

    var modal: Modal = .{
        .content = text.widget(),
        .title = "Test",
        .width = .{ .percentage = 50 },
        .height = .{ .percentage = 50 },
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
    try std.testing.expectEqual(80, surface.size.width);
    try std.testing.expectEqual(24, surface.size.height);

    // Modal content should be 50% of screen = 40x12
    const child = surface.children[0].surface;
    try std.testing.expectEqual(40, child.size.width);
    try std.testing.expectEqual(12, child.size.height);
}
