//! Prometheus-compatible metrics collection for Plue API server.
//!
//! Provides counters, gauges, and histograms for monitoring:
//! - HTTP request counts and latencies
//! - Authentication events
//! - Active connections (sessions, websockets)
//! - Database operations

const std = @import("std");

const log = std.log.scoped(.metrics);

/// Global metrics registry (thread-safe via atomics)
pub const Registry = struct {
    // HTTP metrics
    http_requests_total: RequestCounter = .{},
    http_request_duration_ms: DurationHistogram = .{},

    // Auth metrics
    auth_attempts_total: AuthCounter = .{},

    // Connection metrics
    active_sessions: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
    active_websockets: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
    active_pty_sessions: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

    // Database metrics
    db_queries_total: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    db_query_errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    db_pool_connections: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

    // Input validation metrics (for tracking potential attacks/bugs)
    input_validation_failures: ValidationCounter = .{},

    // Unimplemented endpoint calls (tracks demand for features)
    unimplemented_calls: UnimplementedCounter = .{},

    // Server info
    start_time: i64 = 0,

    pub fn init() void {
        global.start_time = std.time.timestamp();
    }

    /// Record an HTTP request
    pub fn recordRequest(self: *Registry, method: Method, path: []const u8, status: u16, duration_ms: u64) void {
        self.http_requests_total.inc(method, pathCategory(path), status);
        self.http_request_duration_ms.observe(duration_ms);
    }

    /// Record auth attempt
    pub fn recordAuthAttempt(self: *Registry, result: AuthResult, method: AuthMethod) void {
        self.auth_attempts_total.inc(result, method);
    }

    /// Increment active sessions
    pub fn sessionOpened(self: *Registry) void {
        _ = self.active_sessions.fetchAdd(1, .monotonic);
    }

    /// Decrement active sessions
    pub fn sessionClosed(self: *Registry) void {
        _ = self.active_sessions.fetchSub(1, .monotonic);
    }

    /// Increment active websockets
    pub fn websocketOpened(self: *Registry) void {
        _ = self.active_websockets.fetchAdd(1, .monotonic);
    }

    /// Decrement active websockets
    pub fn websocketClosed(self: *Registry) void {
        _ = self.active_websockets.fetchSub(1, .monotonic);
    }

    /// Increment active PTY sessions
    pub fn ptyOpened(self: *Registry) void {
        _ = self.active_pty_sessions.fetchAdd(1, .monotonic);
    }

    /// Decrement active PTY sessions
    pub fn ptyClosed(self: *Registry) void {
        _ = self.active_pty_sessions.fetchSub(1, .monotonic);
    }

    /// Record a database query
    pub fn recordDbQuery(self: *Registry, success: bool) void {
        _ = self.db_queries_total.fetchAdd(1, .monotonic);
        if (!success) {
            _ = self.db_query_errors.fetchAdd(1, .monotonic);
        }
    }

    /// Record input validation failure (for security monitoring)
    pub fn recordValidationFailure(self: *Registry, reason: ValidationReason) void {
        self.input_validation_failures.inc(reason);
    }

    /// Record call to unimplemented endpoint (for feature prioritization)
    pub fn recordUnimplementedCall(self: *Registry, endpoint: UnimplementedEndpoint) void {
        self.unimplemented_calls.inc(endpoint);
    }

    /// Format metrics in Prometheus text format
    pub fn format(self: *const Registry, allocator: std.mem.Allocator) ![]const u8 {
        var output = std.ArrayList(u8){};
        errdefer output.deinit(allocator);

        const writer = output.writer(allocator);

        // Uptime
        const uptime = std.time.timestamp() - self.start_time;
        try writer.print(
            \\# HELP plue_uptime_seconds Server uptime in seconds
            \\# TYPE plue_uptime_seconds gauge
            \\plue_uptime_seconds {d}
            \\
        , .{uptime});

        // HTTP requests
        try writer.print(
            \\# HELP plue_http_requests_total Total HTTP requests
            \\# TYPE plue_http_requests_total counter
            \\
        , .{});
        try self.http_requests_total.format(writer);

        // HTTP duration histogram
        try writer.print(
            \\# HELP plue_http_request_duration_ms HTTP request duration in milliseconds
            \\# TYPE plue_http_request_duration_ms histogram
            \\
        , .{});
        try self.http_request_duration_ms.format(writer);

        // Auth attempts
        try writer.print(
            \\# HELP plue_auth_attempts_total Total authentication attempts
            \\# TYPE plue_auth_attempts_total counter
            \\
        , .{});
        try self.auth_attempts_total.format(writer);

        // Active connections
        try writer.print(
            \\# HELP plue_active_sessions Active user sessions
            \\# TYPE plue_active_sessions gauge
            \\plue_active_sessions {d}
            \\# HELP plue_active_websockets Active WebSocket connections
            \\# TYPE plue_active_websockets gauge
            \\plue_active_websockets {d}
            \\# HELP plue_active_pty_sessions Active PTY sessions
            \\# TYPE plue_active_pty_sessions gauge
            \\plue_active_pty_sessions {d}
            \\
        , .{
            self.active_sessions.load(.monotonic),
            self.active_websockets.load(.monotonic),
            self.active_pty_sessions.load(.monotonic),
        });

        // Database metrics
        try writer.print(
            \\# HELP plue_db_queries_total Total database queries
            \\# TYPE plue_db_queries_total counter
            \\plue_db_queries_total {d}
            \\# HELP plue_db_query_errors_total Total database query errors
            \\# TYPE plue_db_query_errors_total counter
            \\plue_db_query_errors_total {d}
            \\# HELP plue_db_pool_connections Active database pool connections
            \\# TYPE plue_db_pool_connections gauge
            \\plue_db_pool_connections {d}
            \\
        , .{
            self.db_queries_total.load(.monotonic),
            self.db_query_errors.load(.monotonic),
            self.db_pool_connections.load(.monotonic),
        });

        // Input validation failures (security monitoring)
        try writer.print(
            \\# HELP plue_input_validation_failures_total Input validation failures by reason
            \\# TYPE plue_input_validation_failures_total counter
            \\
        , .{});
        try self.input_validation_failures.format(writer);

        // Unimplemented endpoint calls (feature demand tracking)
        try writer.print(
            \\# HELP plue_unimplemented_calls_total Calls to unimplemented endpoints
            \\# TYPE plue_unimplemented_calls_total counter
            \\
        , .{});
        try self.unimplemented_calls.format(writer);

        return output.toOwnedSlice(allocator);
    }
};

/// HTTP methods for metrics
pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    OPTIONS,
    HEAD,
    OTHER,

    pub fn fromString(s: []const u8) Method {
        if (std.mem.eql(u8, s, "GET")) return .GET;
        if (std.mem.eql(u8, s, "POST")) return .POST;
        if (std.mem.eql(u8, s, "PUT")) return .PUT;
        if (std.mem.eql(u8, s, "PATCH")) return .PATCH;
        if (std.mem.eql(u8, s, "DELETE")) return .DELETE;
        if (std.mem.eql(u8, s, "OPTIONS")) return .OPTIONS;
        if (std.mem.eql(u8, s, "HEAD")) return .HEAD;
        return .OTHER;
    }

    pub fn toString(self: Method) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .PATCH => "PATCH",
            .DELETE => "DELETE",
            .OPTIONS => "OPTIONS",
            .HEAD => "HEAD",
            .OTHER => "OTHER",
        };
    }
};

/// Path categories for grouping
pub const PathCategory = enum {
    health,
    auth,
    api_users,
    api_repos,
    api_issues,
    api_sessions,
    api_messages,
    api_workflows,
    pty,
    metrics,
    other,

    pub fn toString(self: PathCategory) []const u8 {
        return switch (self) {
            .health => "/health",
            .auth => "/api/auth/*",
            .api_users => "/api/users/*",
            .api_repos => "/api/:user/:repo/*",
            .api_issues => "/api/:user/:repo/issues/*",
            .api_sessions => "/api/sessions/*",
            .api_messages => "/api/sessions/:id/messages/*",
            .api_workflows => "/api/:user/:repo/workflows/*",
            .pty => "/pty/*",
            .metrics => "/metrics",
            .other => "other",
        };
    }
};

fn pathCategory(path: []const u8) PathCategory {
    if (std.mem.startsWith(u8, path, "/health")) return .health;
    if (std.mem.startsWith(u8, path, "/metrics")) return .metrics;
    if (std.mem.startsWith(u8, path, "/pty")) return .pty;
    if (std.mem.startsWith(u8, path, "/api/auth")) return .auth;
    if (std.mem.startsWith(u8, path, "/api/users")) return .api_users;
    if (std.mem.startsWith(u8, path, "/api/sessions")) {
        if (std.mem.indexOf(u8, path, "/messages")) |_| return .api_messages;
        return .api_sessions;
    }
    if (std.mem.indexOf(u8, path, "/issues")) |_| return .api_issues;
    if (std.mem.indexOf(u8, path, "/workflows")) |_| return .api_workflows;
    if (std.mem.startsWith(u8, path, "/api/")) return .api_repos;
    return .other;
}

/// Auth result types
pub const AuthResult = enum {
    success,
    failed,
    invalid_signature,
    invalid_nonce,
    expired,
    rate_limited,

    pub fn toString(self: AuthResult) []const u8 {
        return switch (self) {
            .success => "success",
            .failed => "failed",
            .invalid_signature => "invalid_signature",
            .invalid_nonce => "invalid_nonce",
            .expired => "expired",
            .rate_limited => "rate_limited",
        };
    }
};

/// Auth methods
pub const AuthMethod = enum {
    siwe,
    api_token,
    session,

    pub fn toString(self: AuthMethod) []const u8 {
        return switch (self) {
            .siwe => "siwe",
            .api_token => "api_token",
            .session => "session",
        };
    }
};

/// Input validation failure reasons (for security monitoring)
pub const ValidationReason = enum {
    null_byte,
    control_char,
    oversized_input,
    invalid_pagination,
    invalid_format,
    path_traversal,

    pub fn toString(self: ValidationReason) []const u8 {
        return switch (self) {
            .null_byte => "null_byte",
            .control_char => "control_char",
            .oversized_input => "oversized_input",
            .invalid_pagination => "invalid_pagination",
            .invalid_format => "invalid_format",
            .path_traversal => "path_traversal",
        };
    }
};

/// Unimplemented endpoints (for feature demand tracking)
pub const UnimplementedEndpoint = enum {
    session_abort,
    session_undo,
    session_restore,
    session_revert,
    session_unrevert,
    operation_undo,

    pub fn toString(self: UnimplementedEndpoint) []const u8 {
        return switch (self) {
            .session_abort => "session_abort",
            .session_undo => "session_undo",
            .session_restore => "session_restore",
            .session_revert => "session_revert",
            .session_unrevert => "session_unrevert",
            .operation_undo => "operation_undo",
        };
    }
};

/// Counter for HTTP requests by method/path/status
const RequestCounter = struct {
    // Using a fixed-size array for common status codes
    // Index: method(8) * path_category(11) * status_bucket(5) = 440 slots
    counts: [8 * 11 * 5]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** (8 * 11 * 5),

    fn statusBucket(status: u16) usize {
        return switch (status / 100) {
            2 => 0, // 2xx
            3 => 1, // 3xx
            4 => 2, // 4xx
            5 => 3, // 5xx
            else => 4,
        };
    }

    fn index(method: Method, path: PathCategory, status: u16) usize {
        const method_idx: usize = @intFromEnum(method);
        const path_idx: usize = @intFromEnum(path);
        return method_idx * 11 * 5 + path_idx * 5 + statusBucket(status);
    }

    pub fn inc(self: *RequestCounter, method: Method, path: PathCategory, status: u16) void {
        const idx = index(method, path, status);
        _ = self.counts[idx].fetchAdd(1, .monotonic);
    }

    pub fn format(self: *const RequestCounter, writer: anytype) !void {
        const methods = [_]Method{ .GET, .POST, .PUT, .PATCH, .DELETE, .OPTIONS, .HEAD, .OTHER };
        const paths = [_]PathCategory{ .health, .auth, .api_users, .api_repos, .api_issues, .api_sessions, .api_messages, .api_workflows, .pty, .metrics, .other };
        const statuses = [_][]const u8{ "2xx", "3xx", "4xx", "5xx", "other" };

        for (methods) |method| {
            for (paths) |path| {
                for (statuses, 0..) |status_str, status_idx| {
                    const method_idx: usize = @intFromEnum(method);
                    const path_idx: usize = @intFromEnum(path);
                    const idx = method_idx * 11 * 5 + path_idx * 5 + status_idx;
                    const count = self.counts[idx].load(.monotonic);
                    if (count > 0) {
                        try writer.print("plue_http_requests_total{{method=\"{s}\",path=\"{s}\",status=\"{s}\"}} {d}\n", .{
                            method.toString(),
                            path.toString(),
                            status_str,
                            count,
                        });
                    }
                }
            }
        }
    }
};

/// Counter for auth attempts
const AuthCounter = struct {
    // result(6) * method(3) = 18 slots
    counts: [6 * 3]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** (6 * 3),

    pub fn inc(self: *AuthCounter, result: AuthResult, method: AuthMethod) void {
        const idx = @intFromEnum(result) * 3 + @intFromEnum(method);
        _ = self.counts[idx].fetchAdd(1, .monotonic);
    }

    pub fn format(self: *const AuthCounter, writer: anytype) !void {
        const results = [_]AuthResult{ .success, .failed, .invalid_signature, .invalid_nonce, .expired, .rate_limited };
        const methods = [_]AuthMethod{ .siwe, .api_token, .session };

        for (results) |result| {
            for (methods) |method| {
                const idx = @intFromEnum(result) * 3 + @intFromEnum(method);
                const count = self.counts[idx].load(.monotonic);
                if (count > 0) {
                    try writer.print("plue_auth_attempts_total{{result=\"{s}\",method=\"{s}\"}} {d}\n", .{
                        result.toString(),
                        method.toString(),
                        count,
                    });
                }
            }
        }
    }
};

/// Counter for input validation failures (security monitoring)
const ValidationCounter = struct {
    // 6 validation reasons
    counts: [6]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** 6,

    pub fn inc(self: *ValidationCounter, reason: ValidationReason) void {
        const idx = @intFromEnum(reason);
        _ = self.counts[idx].fetchAdd(1, .monotonic);
    }

    pub fn format(self: *const ValidationCounter, writer: anytype) !void {
        const reasons = [_]ValidationReason{ .null_byte, .control_char, .oversized_input, .invalid_pagination, .invalid_format, .path_traversal };

        for (reasons) |reason| {
            const idx = @intFromEnum(reason);
            const count = self.counts[idx].load(.monotonic);
            if (count > 0) {
                try writer.print("plue_input_validation_failures_total{{reason=\"{s}\"}} {d}\n", .{
                    reason.toString(),
                    count,
                });
            }
        }
    }
};

/// Counter for unimplemented endpoint calls (feature demand tracking)
const UnimplementedCounter = struct {
    // 6 unimplemented endpoints
    counts: [6]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** 6,

    pub fn inc(self: *UnimplementedCounter, endpoint: UnimplementedEndpoint) void {
        const idx = @intFromEnum(endpoint);
        _ = self.counts[idx].fetchAdd(1, .monotonic);
    }

    pub fn format(self: *const UnimplementedCounter, writer: anytype) !void {
        const endpoints = [_]UnimplementedEndpoint{ .session_abort, .session_undo, .session_restore, .session_revert, .session_unrevert, .operation_undo };

        for (endpoints) |endpoint| {
            const idx = @intFromEnum(endpoint);
            const count = self.counts[idx].load(.monotonic);
            if (count > 0) {
                try writer.print("plue_unimplemented_calls_total{{endpoint=\"{s}\"}} {d}\n", .{
                    endpoint.toString(),
                    count,
                });
            }
        }
    }
};

/// Histogram for request durations
const DurationHistogram = struct {
    // Buckets: 1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, +Inf
    buckets: [13]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** 13,
    sum: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    const bucket_bounds = [_]u64{ 1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000 };

    pub fn observe(self: *DurationHistogram, value: u64) void {
        _ = self.sum.fetchAdd(value, .monotonic);
        _ = self.count.fetchAdd(1, .monotonic);

        // Increment all buckets where value <= bound
        for (bucket_bounds, 0..) |bound, i| {
            if (value <= bound) {
                _ = self.buckets[i].fetchAdd(1, .monotonic);
            }
        }
        // Always increment +Inf bucket
        _ = self.buckets[12].fetchAdd(1, .monotonic);
    }

    pub fn format(self: *const DurationHistogram, writer: anytype) !void {
        for (bucket_bounds, 0..) |bound, i| {
            try writer.print("plue_http_request_duration_ms_bucket{{le=\"{d}\"}} {d}\n", .{
                bound,
                self.buckets[i].load(.monotonic),
            });
        }
        try writer.print("plue_http_request_duration_ms_bucket{{le=\"+Inf\"}} {d}\n", .{
            self.buckets[12].load(.monotonic),
        });
        try writer.print("plue_http_request_duration_ms_sum {d}\n", .{
            self.sum.load(.monotonic),
        });
        try writer.print("plue_http_request_duration_ms_count {d}\n", .{
            self.count.load(.monotonic),
        });
    }
};

/// Global metrics registry instance
pub var global: Registry = .{};

/// Initialize metrics (call once at startup)
pub fn init() void {
    Registry.init();
    log.info("Metrics initialized", .{});
}

// ============================================================================
// Tests
// ============================================================================

test "path categorization" {
    try std.testing.expectEqual(PathCategory.health, pathCategory("/health"));
    try std.testing.expectEqual(PathCategory.auth, pathCategory("/api/auth/siwe/nonce"));
    try std.testing.expectEqual(PathCategory.api_sessions, pathCategory("/api/sessions/123"));
    try std.testing.expectEqual(PathCategory.api_messages, pathCategory("/api/sessions/123/messages"));
    try std.testing.expectEqual(PathCategory.api_issues, pathCategory("/api/user/repo/issues/1"));
    try std.testing.expectEqual(PathCategory.pty, pathCategory("/pty/abc123"));
    try std.testing.expectEqual(PathCategory.metrics, pathCategory("/metrics"));
}

test "request counter" {
    var counter = RequestCounter{};
    counter.inc(.GET, .health, 200);
    counter.inc(.GET, .health, 200);
    counter.inc(.POST, .auth, 401);

    const idx_health = RequestCounter.index(.GET, .health, 200);
    try std.testing.expectEqual(@as(u64, 2), counter.counts[idx_health].load(.monotonic));

    const idx_auth = RequestCounter.index(.POST, .auth, 401);
    try std.testing.expectEqual(@as(u64, 1), counter.counts[idx_auth].load(.monotonic));
}

test "duration histogram" {
    var hist = DurationHistogram{};
    hist.observe(5);
    hist.observe(50);
    hist.observe(500);

    try std.testing.expectEqual(@as(u64, 3), hist.count.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 555), hist.sum.load(.monotonic));

    // 5ms falls in buckets: 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, +Inf
    // But we're testing incremental, so:
    // - 5: in bucket 1 (5ms) and above
    // - 50: in bucket 4 (50ms) and above
    // - 500: in bucket 7 (500ms) and above
    try std.testing.expect(hist.buckets[1].load(.monotonic) >= 1); // 5ms bucket
    try std.testing.expect(hist.buckets[12].load(.monotonic) == 3); // +Inf always has all
}
