//! Rate limiting middleware
//!
//! In-memory rate limiter with configurable limits and time windows.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;

const log = std.log.scoped(.rate_limit);

pub const RateLimitConfig = struct {
    max_requests: u32,
    window_ms: u64,
    skip_on_success: bool = false,
};

/// Preset configurations
pub const presets = struct {
    /// Auth rate limit: 5 attempts per 15 minutes
    pub const auth = RateLimitConfig{
        .max_requests = 5,
        .window_ms = 15 * 60 * 1000,
        .skip_on_success = true,
    };

    /// API rate limit: 100 requests per 15 minutes
    pub const api = RateLimitConfig{
        .max_requests = 100,
        .window_ms = 15 * 60 * 1000,
    };

    /// Email rate limit: 3 emails per hour
    pub const email = RateLimitConfig{
        .max_requests = 3,
        .window_ms = 60 * 60 * 1000,
    };
};

const Entry = struct {
    count: u32,
    reset_at: i64,
};

/// In-memory rate limit store
/// NOTE: This is per-server instance, not shared across servers
pub const RateLimiter = struct {
    entries: std.StringHashMap(Entry),
    config: RateLimitConfig,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, config: RateLimitConfig) RateLimiter {
        return .{
            .entries = std.StringHashMap(Entry).init(allocator),
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RateLimiter) void {
        var it = self.entries.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.entries.deinit();
    }

    /// Check if request should be rate limited
    /// Returns true if allowed, false if rate limited
    pub fn check(self: *RateLimiter, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.milliTimestamp();

        if (self.entries.get(key)) |entry| {
            // Check if window expired
            if (now >= entry.reset_at) {
                // Reset window
                self.entries.put(key, .{
                    .count = 1,
                    .reset_at = now + @as(i64, @intCast(self.config.window_ms)),
                }) catch return true;
                return true;
            }

            // Check if over limit
            if (entry.count >= self.config.max_requests) {
                return false;
            }

            // Increment count
            self.entries.put(key, .{
                .count = entry.count + 1,
                .reset_at = entry.reset_at,
            }) catch return true;
            return true;
        }

        // New entry
        const key_copy = self.allocator.dupe(u8, key) catch return true;
        self.entries.put(key_copy, .{
            .count = 1,
            .reset_at = now + @as(i64, @intCast(self.config.window_ms)),
        }) catch {
            self.allocator.free(key_copy);
            return true;
        };
        return true;
    }

    /// Get remaining requests for a key
    pub fn remaining(self: *RateLimiter, key: []const u8) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.milliTimestamp();

        if (self.entries.get(key)) |entry| {
            if (now >= entry.reset_at) {
                return self.config.max_requests;
            }
            if (entry.count >= self.config.max_requests) {
                return 0;
            }
            return self.config.max_requests - entry.count;
        }
        return self.config.max_requests;
    }
};

/// Create rate limit middleware with given configuration
pub fn rateLimitMiddleware(
    limiter: *RateLimiter,
) fn (*Context, *httpz.Request, *httpz.Response) anyerror!bool {
    return struct {
        fn handler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
            _ = ctx;

            // Get client IP as key
            const key = req.headers.get("x-forwarded-for") orelse
                req.headers.get("x-real-ip") orelse
                "unknown";

            if (!limiter.check(key)) {
                res.status = .@"Too Many Requests";
                res.content_type = .JSON;

                const remaining = limiter.remaining(key);
                var buf: [32]u8 = undefined;
                const remaining_str = try std.fmt.bufPrint(&buf, "{d}", .{remaining});
                res.headers.put("X-RateLimit-Remaining", remaining_str);

                try res.writer().writeAll("{\"error\":\"Too many requests\"}");
                return false;
            }

            return true;
        }
    }.handler;
}

test "rate limiter basic" {
    const allocator = std.testing.allocator;

    var limiter = RateLimiter.init(allocator, .{
        .max_requests = 3,
        .window_ms = 1000,
    });
    defer limiter.deinit();

    // Should allow first 3 requests
    try std.testing.expect(limiter.check("test"));
    try std.testing.expect(limiter.check("test"));
    try std.testing.expect(limiter.check("test"));

    // 4th should be blocked
    try std.testing.expect(!limiter.check("test"));

    // Different key should work
    try std.testing.expect(limiter.check("other"));
}
