const std = @import("std");

pub fn execute(allocator: std.mem.Allocator, global_options: anytype) !void {
    _ = allocator;
    _ = global_options;
    
    const stdout = std.io.getStdOut().writer();
    try stdout.print("scrap command not yet implemented\n", .{});
}