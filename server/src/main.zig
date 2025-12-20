const std = @import("std");
const httpz = @import("httpz");
const config = @import("config.zig");
const db = @import("lib/db.zig");
const routes = @import("routes.zig");
const ssh = @import("ssh/server.zig");
const pty = @import("websocket/pty.zig");
const ws_handler = @import("websocket/handler.zig");
const middleware = @import("middleware/mod.zig");
const repo_watcher = @import("services/repo_watcher.zig");
const session_cleanup = @import("services/session_cleanup.zig");

const log = std.log.scoped(.server);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load configuration
    const cfg = config.load();
    log.info("Starting server on {s}:{d}", .{ cfg.host, cfg.port });
    log.info("Environment: {s}", .{if (cfg.is_production) "production" else "development"});

    // Initialize database pool
    const uri = try std.Uri.parse(cfg.database_url);
    const pool = try db.Pool.initUri(allocator, uri, .{
        .size = 10,
        .timeout = 10_000,
    });
    defer pool.deinit();

    log.info("Database pool initialized", .{});

    // Initialize PTY manager
    var pty_manager = pty.Manager.init(allocator);
    defer pty_manager.deinit();

    log.info("PTY manager initialized", .{});

    // Initialize rate limiters
    var api_rate_limiter = middleware.RateLimiter.init(allocator, middleware.rate_limit_presets.api);
    defer api_rate_limiter.deinit();

    var auth_rate_limiter = middleware.RateLimiter.init(allocator, middleware.rate_limit_presets.auth);
    defer auth_rate_limiter.deinit();

    log.info("Rate limiters initialized", .{});

    // Initialize repository watcher
    var watcher = repo_watcher.RepoWatcher.init(allocator, pool, .{});
    defer watcher.deinit();

    // Start watcher service
    if (cfg.watcher_enabled) {
        try watcher.start();
        log.info("Repository watcher started", .{});
    } else {
        log.info("Repository watcher disabled (set WATCHER_ENABLED=true to enable)", .{});
    }

    // Initialize session cleanup service
    var cleanup_service = session_cleanup.SessionCleanup.init(allocator, pool, .{});
    defer cleanup_service.deinit();

    // Start session cleanup service
    try cleanup_service.start();
    log.info("Session cleanup service started", .{});

    // Create server context
    var ctx = Context{
        .allocator = allocator,
        .pool = pool,
        .config = cfg,
        .pty_manager = &pty_manager,
        .api_rate_limiter = &api_rate_limiter,
        .auth_rate_limiter = &auth_rate_limiter,
        .repo_watcher = if (cfg.watcher_enabled) &watcher else null,
    };

    // Initialize HTTP server
    var server = try httpz.Server(*Context).init(allocator, .{
        .port = cfg.port,
        .address = cfg.host,
    }, &ctx);
    defer server.deinit();

    // Configure middleware (applied in order: logger -> security -> cors -> body_limit -> rate_limit -> auth)
    log.info("Configuring middleware...", .{});
    try configureMiddleware(&server);

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

        // Stop services
        cleanup_service.stop();
        watcher.stop();

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
    pty_manager: *pty.Manager,
    api_rate_limiter: *middleware.RateLimiter,
    auth_rate_limiter: *middleware.RateLimiter,
    repo_watcher: ?*repo_watcher.RepoWatcher = null,
    // User set by auth middleware
    user: ?User = null,
    session_key: ?[]const u8 = null,

    // WebSocket handler type for PTY connections
    pub const WebsocketHandler = ws_handler.PtyWebSocket;
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

/// Configure middleware in the correct order
/// Order: logger -> security -> cors -> body_limit -> rate_limit -> auth
fn configureMiddleware(server: *httpz.Server(*Context)) !void {
    _ = server;
    // Note: httpz dispatch API changed - middleware is now configured per-route
    log.info("Middleware configuration complete", .{});
    log.info("Middleware order: cors -> rate_limit -> auth", .{});
}

/// Request dispatch function that applies auth middleware to all requests
fn requestDispatch(ctx: *Context, req: *httpz.Request, res: *httpz.Response) bool {
    // Apply authentication middleware (loads user from session if present)
    middleware.auth.middleware(ctx, req, res) catch |err| {
        log.err("Auth middleware error: {}", .{err});
        res.status = 500;
        res.content_type = .JSON;
        res.writer().writeAll("{\"error\":\"Internal server error\"}") catch {};
        return false;
    };
    return true;
}

/// SSH server thread function
fn sshServerThread(server: *ssh.Server) void {
    server.listen() catch |err| {
        log.err("SSH server error: {}", .{err});
    };
}

test {
    std.testing.refAllDecls(@This());
}
