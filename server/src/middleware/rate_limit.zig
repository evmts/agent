//! In-memory rate limiting middleware
//!
//! Uses a simple hash map for rate limit storage.
//! For distributed deployments, consider using Redis or PostgreSQL-based rate limiting.

const std = @import("std");
const httpz = @import("httpz");
const db = @import("db");
const Context = @import("../main.zig").Context;

const log = std.log.scoped(.rate_limit);

pub const RateLimitConfig = struct {
    max_requests: u32,
    window_seconds: u32,
    skip_on_success: bool = false,
};

/// Preset configurations for different endpoints
pub const presets = struct {
    /// Login endpoint: 5 requests per minute
    pub const login = RateLimitConfig{
        .max_requests = 5,
        .window_seconds = 60,
        .skip_on_success = true,
    };

    /// Register endpoint: 3 requests per minute
    pub const register = RateLimitConfig{
        .max_requests = 3,
        .window_seconds = 60,
    };

    /// Password reset: 3 requests per hour
    pub const password_reset = RateLimitConfig{
        .max_requests = 3,
        .window_seconds = 3600,
    };

    /// General auth endpoints: 10 requests per minute
    pub const auth = RateLimitConfig{
        .max_requests = 10,
        .window_seconds = 60,
        .skip_on_success = true,
    };

    /// General API endpoints: 100 requests per 15 minutes
    pub const api = RateLimitConfig{
        .max_requests = 100,
        .window_seconds = 900,
    };

    /// Email operations: 3 emails per hour
    pub const email = RateLimitConfig{
        .max_requests = 3,
        .window_seconds = 3600,
    };
};

/// In-memory rate limit entry
const RateLimitEntry = struct {
    count: u32,
    window_start: i64,
};

/// Global in-memory rate limit store
var rate_limit_store: ?std.StringHashMap(RateLimitEntry) = null;
var store_mutex: std.Thread.Mutex = .{};

fn initStore(allocator: std.mem.Allocator) void {
    store_mutex.lock();
    defer store_mutex.unlock();
    if (rate_limit_store == null) {
        rate_limit_store = std.StringHashMap(RateLimitEntry).init(allocator);
    }
}

/// Check rate limit for a key (in-memory implementation)
fn checkRateLimitInMemory(key: []const u8, config: RateLimitConfig, allocator: std.mem.Allocator) !struct { allowed: bool, count: u32 } {
    initStore(allocator);

    store_mutex.lock();
    defer store_mutex.unlock();

    const now = std.time.timestamp();
    var store = &rate_limit_store.?;

    // Try to get or create entry
    const gop = try store.getOrPut(key);
    if (!gop.found_existing) {
        // Need to dupe the key for long-term storage
        const owned_key = try allocator.dupe(u8, key);
        gop.key_ptr.* = owned_key;
        gop.value_ptr.* = RateLimitEntry{
            .count = 1,
            .window_start = now,
        };
        return .{ .allowed = true, .count = 1 };
    }

    const entry = gop.value_ptr;

    // Check if window expired
    if (now - entry.window_start >= @as(i64, config.window_seconds)) {
        // Reset window
        entry.count = 1;
        entry.window_start = now;
        return .{ .allowed = true, .count = 1 };
    }

    // Increment and check
    entry.count += 1;
    return .{
        .allowed = entry.count <= config.max_requests,
        .count = entry.count,
    };
}

/// Get rate limit key from request (IP address)
fn getRateLimitKey(req: *httpz.Request, allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
    const ip = req.headers.get("x-forwarded-for") orelse
        req.headers.get("x-real-ip") orelse
        "unknown";

    return try std.fmt.allocPrint(allocator, "{s}:{s}", .{ prefix, ip });
}

/// Create rate limit middleware with given configuration
pub fn rateLimitMiddleware(
    config: RateLimitConfig,
    key_prefix: []const u8,
) fn (*Context, *httpz.Request, *httpz.Response) anyerror!bool {
    return struct {
        fn handler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
            // Generate rate limit key
            const key = try getRateLimitKey(req, ctx.allocator, key_prefix);
            defer ctx.allocator.free(key);

            // Check rate limit using in-memory store
            const result = checkRateLimitInMemory(key, config, ctx.allocator) catch |err| {
                log.err("Rate limit check failed: {}", .{err});
                // On error, allow the request (fail open)
                return true;
            };

            if (!result.allowed) {
                res.status = 429;
                res.content_type = .JSON;

                // Add rate limit headers
                var limit_buf: [32]u8 = undefined;
                const limit_str = try std.fmt.bufPrint(&limit_buf, "{d}", .{config.max_requests});
                res.headers.add("X-RateLimit-Limit", limit_str);

                var remaining_buf: [32]u8 = undefined;
                const remaining_str = try std.fmt.bufPrint(&remaining_buf, "0", .{});
                res.headers.add("X-RateLimit-Remaining", remaining_str);

                var retry_buf: [32]u8 = undefined;
                const retry_str = try std.fmt.bufPrint(&retry_buf, "{d}", .{config.window_seconds});
                res.headers.add("Retry-After", retry_str);

                try res.writer().writeAll("{\"error\":\"Too many requests\"}");
                log.info("Rate limited: {s} (count: {d})", .{ key, result.count });
                return false;
            }

            // Add rate limit headers for allowed requests
            var limit_buf: [32]u8 = undefined;
            const limit_str = try std.fmt.bufPrint(&limit_buf, "{d}", .{config.max_requests});
            res.headers.add("X-RateLimit-Limit", limit_str);

            var remaining_buf: [32]u8 = undefined;
            const remaining = config.max_requests - result.count;
            const remaining_str = try std.fmt.bufPrint(&remaining_buf, "{d}", .{remaining});
            res.headers.add("X-RateLimit-Remaining", remaining_str);

            return true;
        }
    }.handler;
}

/// Cleanup expired rate limit entries
/// This should be called periodically (e.g., from a background service)
pub fn cleanupExpired(pool: *db.Pool) !void {
    const deleted = try db.cleanupExpiredRateLimits(pool);
    if (deleted) |count| {
        if (count > 0) {
            log.debug("Cleaned up {d} expired rate limit entries", .{count});
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "rate limit config defaults" {
    const config = RateLimitConfig{
        .max_requests = 10,
        .window_seconds = 60,
    };

    try std.testing.expectEqual(false, config.skip_on_success);
}

test "rate limit presets" {
    // Test login preset
    try std.testing.expectEqual(@as(u32, 5), presets.login.max_requests);
    try std.testing.expectEqual(@as(u32, 60), presets.login.window_seconds);
    try std.testing.expect(presets.login.skip_on_success);

    // Test register preset
    try std.testing.expectEqual(@as(u32, 3), presets.register.max_requests);
    try std.testing.expectEqual(@as(u32, 60), presets.register.window_seconds);

    // Test password reset preset
    try std.testing.expectEqual(@as(u32, 3), presets.password_reset.max_requests);
    try std.testing.expectEqual(@as(u32, 3600), presets.password_reset.window_seconds);

    // Test API preset
    try std.testing.expectEqual(@as(u32, 100), presets.api.max_requests);
    try std.testing.expectEqual(@as(u32, 900), presets.api.window_seconds);

    // Test email preset
    try std.testing.expectEqual(@as(u32, 3), presets.email.max_requests);
    try std.testing.expectEqual(@as(u32, 3600), presets.email.window_seconds);
}
