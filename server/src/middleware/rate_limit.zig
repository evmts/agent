//! Distributed rate limiting middleware
//!
//! Uses PostgreSQL for rate limit storage, enabling rate limits to be
//! shared across all server instances behind a load balancer.

const std = @import("std");
const httpz = @import("httpz");
const db = @import("../lib/db.zig");
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

/// Distributed rate limiter using PostgreSQL
pub const RateLimiter = struct {
    pool: *db.Pool,
    config: RateLimitConfig,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, pool: *db.Pool, config: RateLimitConfig) RateLimiter {
        return .{
            .pool = pool,
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RateLimiter) void {
        _ = self;
        // No cleanup needed - pool is managed externally
    }

    /// Check if request should be rate limited
    /// Returns true if allowed, false if rate limited
    pub fn check(self: *RateLimiter, key: []const u8) !bool {
        const result = try db.checkRateLimit(
            self.pool,
            key,
            @intCast(self.config.max_requests),
            @intCast(self.config.window_seconds),
        );
        return result.allowed;
    }

    /// Get remaining requests for a key
    pub fn getState(self: *RateLimiter, key: []const u8) !db.RateLimitResult {
        return try db.getRateLimitState(
            self.pool,
            key,
            @intCast(self.config.max_requests),
        );
    }
};

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
            // Create rate limiter for this request
            var limiter = RateLimiter.init(ctx.allocator, ctx.pool, config);
            defer limiter.deinit();

            // Generate rate limit key
            const key = try getRateLimitKey(req, ctx.allocator, key_prefix);
            defer ctx.allocator.free(key);

            // Check rate limit
            const allowed = limiter.check(key) catch |err| {
                log.err("Rate limit check failed: {}", .{err});
                // On error, allow the request (fail open)
                return true;
            };

            if (!allowed) {
                // Get current state for headers
                const state = limiter.getState(key) catch |err| {
                    log.err("Failed to get rate limit state: {}", .{err});
                    res.status = 429;
                    res.content_type = .JSON;
                    try res.writer().writeAll("{\"error\":\"Too many requests\"}");
                    return false;
                };

                res.status = 429;
                res.content_type = .JSON;

                // Add rate limit headers
                var buf: [64]u8 = undefined;

                // X-RateLimit-Limit
                const limit_str = try std.fmt.bufPrint(&buf, "{d}", .{state.limit});
                res.headers.add("X-RateLimit-Limit", limit_str);

                // X-RateLimit-Remaining
                const remaining = if (state.count >= state.limit) 0 else state.limit - state.count;
                const remaining_str = try std.fmt.bufPrint(&buf, "{d}", .{remaining});
                res.headers.add("X-RateLimit-Remaining", remaining_str);

                // X-RateLimit-Reset (Unix timestamp)
                const reset_str = try std.fmt.bufPrint(&buf, "{d}", .{state.reset_at});
                res.headers.add("X-RateLimit-Reset", reset_str);

                // Retry-After (seconds until reset)
                const now = std.time.timestamp();
                const retry_after = if (state.reset_at > now) state.reset_at - now else 0;
                const retry_str = try std.fmt.bufPrint(&buf, "{d}", .{retry_after});
                res.headers.add("Retry-After", retry_str);

                try res.writer().writeAll("{\"error\":\"Too many requests\"}");
                return false;
            }

            // Add rate limit headers for successful requests too
            const state = limiter.getState(key) catch {
                // If we can't get state, just continue without headers
                return true;
            };

            var buf: [64]u8 = undefined;

            const limit_str = try std.fmt.bufPrint(&buf, "{d}", .{state.limit});
            res.headers.add("X-RateLimit-Limit", limit_str);

            const remaining = if (state.count >= state.limit) 0 else state.limit - state.count;
            const remaining_str = try std.fmt.bufPrint(&buf, "{d}", .{remaining});
            res.headers.add("X-RateLimit-Remaining", remaining_str);

            const reset_str = try std.fmt.bufPrint(&buf, "{d}", .{state.reset_at});
            res.headers.add("X-RateLimit-Reset", reset_str);

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
