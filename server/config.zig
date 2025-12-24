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

    // SSH Security Configuration
    ssh_max_connections: u32,
    ssh_max_per_ip_connections: u32,
    ssh_rate_limit_per_minute: u32,
    ssh_max_auth_failures: u32,
    ssh_initial_ban_duration: i64,
    ssh_max_ban_duration: i64,

    // Repository Watcher Configuration
    watcher_enabled: bool,

    // Edge Cache Invalidation
    edge_url: []const u8,
    edge_push_secret: []const u8,

    // mTLS Configuration
    // When enabled, the server requires client certificates signed by the CA
    // at mtls_ca_path. This ensures only Cloudflare can connect to the origin.
    mtls_enabled: bool,
    mtls_ca_path: ?[]const u8,
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
        .database_url = std.posix.getenv("DATABASE_URL") orelse "postgresql://postgres:password@localhost:54321/plue",
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
            // Default to port 22 for Cloudflare Spectrum compatibility
            const port_str = std.posix.getenv("SSH_PORT") orelse "22";
            break :blk std.fmt.parseInt(u16, port_str, 10) catch 22;
        },
        // SSH Security Configuration
        .ssh_max_connections = blk: {
            const val = std.posix.getenv("SSH_MAX_CONNECTIONS") orelse "100";
            break :blk std.fmt.parseInt(u32, val, 10) catch 100;
        },
        .ssh_max_per_ip_connections = blk: {
            const val = std.posix.getenv("SSH_MAX_PER_IP_CONNECTIONS") orelse "10";
            break :blk std.fmt.parseInt(u32, val, 10) catch 10;
        },
        .ssh_rate_limit_per_minute = blk: {
            const val = std.posix.getenv("SSH_RATE_LIMIT_PER_MINUTE") orelse "20";
            break :blk std.fmt.parseInt(u32, val, 10) catch 20;
        },
        .ssh_max_auth_failures = blk: {
            const val = std.posix.getenv("SSH_MAX_AUTH_FAILURES") orelse "5";
            break :blk std.fmt.parseInt(u32, val, 10) catch 5;
        },
        .ssh_initial_ban_duration = blk: {
            // Default: 15 minutes (900 seconds)
            const val = std.posix.getenv("SSH_INITIAL_BAN_DURATION") orelse "900";
            break :blk std.fmt.parseInt(i64, val, 10) catch 900;
        },
        .ssh_max_ban_duration = blk: {
            // Default: 24 hours (86400 seconds)
            const val = std.posix.getenv("SSH_MAX_BAN_DURATION") orelse "86400";
            break :blk std.fmt.parseInt(i64, val, 10) catch 86400;
        },
        .watcher_enabled = blk: {
            const enabled = std.posix.getenv("WATCHER_ENABLED") orelse "true";
            break :blk std.mem.eql(u8, enabled, "true") or std.mem.eql(u8, enabled, "1");
        },
        .edge_url = std.posix.getenv("EDGE_URL") orelse "",
        .edge_push_secret = std.posix.getenv("EDGE_PUSH_SECRET") orelse "",
        .mtls_enabled = blk: {
            const enabled = std.posix.getenv("PLUE_MTLS_ENABLED") orelse "false";
            break :blk std.mem.eql(u8, enabled, "true") or std.mem.eql(u8, enabled, "1");
        },
        .mtls_ca_path = std.posix.getenv("PLUE_MTLS_CA_PATH"),
    };
}
