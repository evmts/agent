/// Health check endpoint for SSH server monitoring
const std = @import("std");
const rate_limit = @import("rate_limit.zig");
const connection_limit = @import("connection_limit.zig");

/// SSH server health status
pub const HealthStatus = struct {
    /// Whether the server is accepting connections
    healthy: bool,
    /// Server running state
    running: bool,
    /// Current number of active connections
    total_connections: u32,
    /// Maximum allowed connections
    max_connections: u32,
    /// Number of currently banned IPs
    banned_ips: usize,
    /// Number of unique IPs with active connections
    unique_ips: usize,
    /// Server uptime in seconds
    uptime_seconds: i64,
    /// Connection capacity percentage (0-100)
    capacity_percent: u8,

    /// Convert to JSON for HTTP health endpoint
    pub fn toJson(self: HealthStatus, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();

        try std.json.stringify(self, .{}, buffer.writer());

        return buffer.toOwnedSlice();
    }

    /// Check if server is in a healthy state
    pub fn isHealthy(self: HealthStatus) bool {
        // Healthy if running and not at capacity
        return self.healthy and self.running and self.capacity_percent < 90;
    }

    /// Get a human-readable status message
    pub fn statusMessage(self: HealthStatus) []const u8 {
        if (!self.running) {
            return "Server not running";
        }
        if (self.capacity_percent >= 95) {
            return "Critical: Near connection limit";
        }
        if (self.capacity_percent >= 80) {
            return "Warning: High connection load";
        }
        if (self.banned_ips > 100) {
            return "Warning: Many banned IPs";
        }
        return "Healthy";
    }
};

/// Get current health status from server components
pub fn getHealthStatus(
    running: bool,
    start_time: i64,
    connection_limiter: *connection_limit.ConnectionLimiter,
    rate_limiter: *rate_limit.RateLimiter,
) HealthStatus {
    const now = std.time.timestamp();
    const total = connection_limiter.getTotal();
    const max = connection_limiter.config.max_total_connections;

    const capacity_percent: u8 = if (max > 0)
        @intCast(@min(100, (total * 100) / max))
    else
        0;

    return .{
        .healthy = running and capacity_percent < 100,
        .running = running,
        .total_connections = total,
        .max_connections = max,
        .banned_ips = rate_limiter.getBannedCount(),
        .unique_ips = connection_limiter.getUniqueIPCount(),
        .uptime_seconds = now - start_time,
        .capacity_percent = capacity_percent,
    };
}

/// Detailed health metrics for monitoring systems
pub const DetailedMetrics = struct {
    // Connection metrics
    active_connections: u32,
    connections_per_ip_limit: u32,
    total_connection_limit: u32,

    // Rate limiting metrics
    banned_ip_count: usize,
    rate_limit_per_minute: u32,
    max_auth_failures: u32,

    // Uptime
    uptime_seconds: i64,

    pub fn toPrometheus(self: DetailedMetrics, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();

        const writer = buffer.writer();

        try writer.print(
            \\# HELP ssh_active_connections Current number of active SSH connections
            \\# TYPE ssh_active_connections gauge
            \\ssh_active_connections {d}
            \\
            \\# HELP ssh_connection_limit_total Maximum total SSH connections allowed
            \\# TYPE ssh_connection_limit_total gauge
            \\ssh_connection_limit_total {d}
            \\
            \\# HELP ssh_connection_limit_per_ip Maximum SSH connections per IP
            \\# TYPE ssh_connection_limit_per_ip gauge
            \\ssh_connection_limit_per_ip {d}
            \\
            \\# HELP ssh_banned_ips Current number of banned IPs
            \\# TYPE ssh_banned_ips gauge
            \\ssh_banned_ips {d}
            \\
            \\# HELP ssh_rate_limit_per_minute SSH connection rate limit per minute
            \\# TYPE ssh_rate_limit_per_minute gauge
            \\ssh_rate_limit_per_minute {d}
            \\
            \\# HELP ssh_max_auth_failures Max auth failures before ban
            \\# TYPE ssh_max_auth_failures gauge
            \\ssh_max_auth_failures {d}
            \\
            \\# HELP ssh_uptime_seconds SSH server uptime in seconds
            \\# TYPE ssh_uptime_seconds counter
            \\ssh_uptime_seconds {d}
            \\
        , .{
            self.active_connections,
            self.total_connection_limit,
            self.connections_per_ip_limit,
            self.banned_ip_count,
            self.rate_limit_per_minute,
            self.max_auth_failures,
            self.uptime_seconds,
        });

        return buffer.toOwnedSlice();
    }
};

/// Get detailed metrics for Prometheus/monitoring
pub fn getDetailedMetrics(
    start_time: i64,
    connection_limiter: *connection_limit.ConnectionLimiter,
    rate_limiter: *rate_limit.RateLimiter,
) DetailedMetrics {
    const now = std.time.timestamp();

    return .{
        .active_connections = connection_limiter.getTotal(),
        .connections_per_ip_limit = connection_limiter.config.max_per_ip_connections,
        .total_connection_limit = connection_limiter.config.max_total_connections,
        .banned_ip_count = rate_limiter.getBannedCount(),
        .rate_limit_per_minute = rate_limiter.config.max_connections_per_minute,
        .max_auth_failures = rate_limiter.config.max_auth_failures,
        .uptime_seconds = now - start_time,
    };
}

test "HealthStatus JSON serialization" {
    const allocator = std.testing.allocator;

    const status = HealthStatus{
        .healthy = true,
        .running = true,
        .total_connections = 50,
        .max_connections = 100,
        .banned_ips = 5,
        .unique_ips = 25,
        .uptime_seconds = 3600,
        .capacity_percent = 50,
    };

    const json = try status.toJson(allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"healthy\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_connections\":50") != null);
}

test "HealthStatus isHealthy" {
    var status = HealthStatus{
        .healthy = true,
        .running = true,
        .total_connections = 50,
        .max_connections = 100,
        .banned_ips = 5,
        .unique_ips = 25,
        .uptime_seconds = 3600,
        .capacity_percent = 50,
    };

    try std.testing.expect(status.isHealthy());

    // Not healthy at high capacity
    status.capacity_percent = 95;
    try std.testing.expect(!status.isHealthy());

    // Not healthy when not running
    status.capacity_percent = 50;
    status.running = false;
    try std.testing.expect(!status.isHealthy());
}

test "HealthStatus statusMessage" {
    var status = HealthStatus{
        .healthy = true,
        .running = true,
        .total_connections = 50,
        .max_connections = 100,
        .banned_ips = 5,
        .unique_ips = 25,
        .uptime_seconds = 3600,
        .capacity_percent = 50,
    };

    try std.testing.expectEqualStrings("Healthy", status.statusMessage());

    status.running = false;
    try std.testing.expectEqualStrings("Server not running", status.statusMessage());

    status.running = true;
    status.capacity_percent = 96;
    try std.testing.expectEqualStrings("Critical: Near connection limit", status.statusMessage());
}
