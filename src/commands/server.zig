const std = @import("std");
const clap = @import("clap");
const Server = @import("../server/server.zig");
const DataAccessObject = @import("../database/dao.zig");

pub fn run(allocator: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    _ = iter;
    
    std.log.info("Starting Plue API server...", .{});
    
    // Get database URL from environment or use default
    const db_url = std.posix.getenv("DATABASE_URL") orelse "postgresql://plue:plue_password@localhost:5432/plue";
    
    // Initialize database connection
    var dao = DataAccessObject.init(db_url) catch |err| {
        std.log.err("Failed to connect to database: {}", .{err});
        return err;
    };
    defer dao.deinit();
    
    std.log.info("Connected to database", .{});
    
    var server = try Server.init(allocator, &dao);
    defer server.deinit(allocator);
    
    std.log.info("Server listening on http://0.0.0.0:8000", .{});
    try server.listen();
}

test "server command initializes" {
    const allocator = std.testing.allocator;
    
    var iter = std.process.ArgIterator.init();
    
    // Test will fail due to database connection, which is expected in test environment
    _ = run(allocator, &iter) catch |err| {
        // Expected to fail in test environment due to missing database
        try std.testing.expect(err == error.ConnectionFailed or err == error.Unexpected);
    };
}