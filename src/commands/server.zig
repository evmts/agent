const std = @import("std");
const clap = @import("clap");
const Server = @import("../server/server.zig");

pub fn run(allocator: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    _ = iter;
    
    std.log.info("Starting Plue API server...", .{});
    
    var server = try Server.init(allocator);
    defer server.deinit();
    
    std.log.info("Server listening on http://localhost:8000", .{});
    try server.listen();
}

test "server command initializes" {
    const allocator = std.testing.allocator;
    
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    
    var iter = std.process.ArgIterator.init();
    
    try std.testing.expectError(error.PermissionDenied, run(allocator, &iter));
}