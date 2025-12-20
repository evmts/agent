const std = @import("std");
const httpz = @import("httpz");
const config = @import("config.zig");
const db = @import("lib/db.zig");
const routes = @import("routes.zig");

const log = std.log.scoped(.server);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load configuration
    const cfg = config.load();
    log.info("Starting server on {s}:{d}", .{ cfg.host, cfg.port });

    // Initialize database pool
    const uri = try std.Uri.parse(cfg.database_url);
    const pool = try db.Pool.initUri(allocator, uri, .{
        .size = 10,
        .timeout = 10_000,
    });
    defer pool.deinit();

    log.info("Database pool initialized", .{});

    // Create server context
    var ctx = Context{
        .allocator = allocator,
        .pool = pool,
        .config = cfg,
    };

    // Initialize HTTP server
    var server = try httpz.Server(*Context).init(allocator, .{
        .port = cfg.port,
        .address = cfg.host,
    }, &ctx);
    defer server.deinit();

    // Configure routes
    try routes.configure(&server);

    log.info("Server listening on http://{s}:{d}", .{ cfg.host, cfg.port });

    // Start server (blocking)
    server.listen() catch |err| {
        log.err("Server error: {}", .{err});
        return err;
    };
}

/// Server context passed to all request handlers
pub const Context = struct {
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    config: config.Config,
    // User set by auth middleware
    user: ?User = null,
    session_key: ?[]const u8 = null,
};

pub const User = struct {
    id: i64,
    username: []const u8,
    email: ?[]const u8,
    display_name: ?[]const u8,
    is_admin: bool,
    is_active: bool,
    wallet_address: ?[]const u8,
};

test {
    std.testing.refAllDecls(@This());
}
