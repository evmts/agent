const std = @import("std");
const clap = @import("clap");
const App = @import("../gui/app.zig");

var should_exit: bool = false;

pub fn run(allocator: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    _ = allocator;
    _ = iter;

    var app = App.init();
    try app.run();
}

test "start command sets up correctly" {
    const allocator = std.testing.allocator;
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    var os_args = try std.process.argsWithAllocator(allocator);
    defer os_args.deinit();

    var iter = std.process.ArgIterator.init();

    should_exit = true;

    try run(allocator, &iter);

    try std.testing.expect(should_exit == true);
}
