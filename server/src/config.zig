const std = @import("std");

pub const Config = struct {
    host: []const u8,
    port: u16,
    database_url: []const u8,
    jwt_secret: []const u8,
    cors_origins: []const []const u8,
    is_production: bool,

    // SSH Server Configuration
    ssh_enabled: bool,
    ssh_host: []const u8,
    ssh_port: u16,

    // Repository Watcher Configuration
    watcher_enabled: bool,

    // Edge Cache Invalidation
    edge_url: []const u8,
    edge_push_secret: []const u8,
};

/// Load configuration from environment variables
pub fn load() Config {
    const is_production = blk: {
        const env = std.posix.getenv("PLUE_ENV") orelse std.posix.getenv("NODE_ENV") orelse "development";
        break :blk std.mem.eql(u8, env, "production");
    };

    // In production, JWT_SECRET must be set
    const jwt_secret = std.posix.getenv("JWT_SECRET") orelse blk: {
        if (is_production) {
            std.log.err("CRITICAL: JWT_SECRET must be set in production environment", .{});
            std.posix.exit(1);
        }
        break :blk "dev-secret-change-in-production";
    };

    return .{
        .host = std.posix.getenv("HOST") orelse "0.0.0.0",
        .port = blk: {
            const port_str = std.posix.getenv("PORT") orelse "4000";
            break :blk std.fmt.parseInt(u16, port_str, 10) catch 4000;
        },
        .database_url = std.posix.getenv("DATABASE_URL") orelse "postgresql://postgres:password@localhost:54321/electric",
        .jwt_secret = jwt_secret,
        .cors_origins = &.{
            "http://localhost:4321",
            "http://localhost:4000",
            "http://localhost:3000",
        },
        .is_production = is_production,
        .ssh_enabled = blk: {
            const enabled = std.posix.getenv("SSH_ENABLED") orelse "false";
            break :blk std.mem.eql(u8, enabled, "true") or std.mem.eql(u8, enabled, "1");
        },
        .ssh_host = std.posix.getenv("SSH_HOST") orelse "0.0.0.0",
        .ssh_port = blk: {
            const port_str = std.posix.getenv("SSH_PORT") orelse "2222";
            break :blk std.fmt.parseInt(u16, port_str, 10) catch 2222;
        },
        .watcher_enabled = blk: {
            const enabled = std.posix.getenv("WATCHER_ENABLED") orelse "true";
            break :blk std.mem.eql(u8, enabled, "true") or std.mem.eql(u8, enabled, "1");
        },
        .edge_url = std.posix.getenv("EDGE_URL") orelse "",
        .edge_push_secret = std.posix.getenv("EDGE_PUSH_SECRET") orelse "",
    };
}
