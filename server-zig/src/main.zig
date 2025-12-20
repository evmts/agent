const std = @import("std");
const httpz = @import("httpz");
const config = @import("config.zig");
const db = @import("lib/db.zig");
const routes = @import("routes.zig");
const ssh = @import("ssh/server.zig");

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

    log.info("HTTP server listening on http://{s}:{d}", .{ cfg.host, cfg.port });

    // Start SSH server if enabled
    var ssh_server: ?ssh.Server = null;
    var ssh_thread: ?std.Thread = null;

    if (cfg.ssh_enabled) {
        log.info("Starting SSH server on {s}:{d}", .{ cfg.ssh_host, cfg.ssh_port });

        const ssh_config = ssh.Config{
            .host = cfg.ssh_host,
            .port = cfg.ssh_port,
            .host_key_path = "data/ssh_host_key",
        };

        var server_instance = ssh.Server.init(allocator, ssh_config, pool);
        ssh_server = server_instance;

        // Start SSH server in separate thread
        ssh_thread = try std.Thread.spawn(.{}, sshServerThread, .{&server_instance});

        log.info("SSH server started successfully", .{});
    } else {
        log.info("SSH server disabled (set SSH_ENABLED=true to enable)", .{});
    }

    // Start HTTP server (blocking)
    server.listen() catch |err| {
        log.err("Server error: {}", .{err});

        // Stop SSH server if running
        if (ssh_server) |*ssh_srv| {
            ssh_srv.stop();
        }
        if (ssh_thread) |thread| {
            thread.join();
        }

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

/// SSH server thread function
fn sshServerThread(server: *ssh.Server) void {
    server.listen() catch |err| {
        log.err("SSH server error: {}", .{err});
    };
}

test {
    std.testing.refAllDecls(@This());
}
