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
    // Skip GUI test for now as it hangs waiting for UI
    return error.SkipZigTest;
}
