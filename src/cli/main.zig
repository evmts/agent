const std = @import("std");
const Cli = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli = try Cli.init(allocator);
    defer cli.deinit();

    try cli.run();
}
