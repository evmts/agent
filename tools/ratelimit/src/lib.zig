//! Plue Rate Limiter - In-memory rate limiting
//!
//! A native Zig library for request rate limiting using sliding window counter.
//! Thread-safe for concurrent access. Designed to be called from Bun via FFI.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;

pub const RateLimitError = error{
    NotInitialized,
    AllocationError,
    KeyTooLong,
};

/// Rate limit entry for a single key
const Entry = struct {
    count: u32,
    window_start: i64,
};

/// Rate Limiter using sliding window counter algorithm
pub const RateLimiter = struct {
    entries: std.StringHashMap(Entry),
    allocator: Allocator,
    max_requests: u32,
    window_ms: u64,
    mutex: Mutex,

    pub fn init(allocator: Allocator, max_requests: u32, window_ms: u64) RateLimiter {
        return .{
            .entries = std.StringHashMap(Entry).init(allocator),
            .allocator = allocator,
            .max_requests = max_requests,
            .window_ms = window_ms,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *RateLimiter) void {
        // Free all allocated keys
        var iter = self.entries.keyIterator();
        while (iter.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.entries.deinit();
    }

    /// Check if a request should be allowed for the given key
    /// Returns true if allowed, false if rate limited
    pub fn check(self: *RateLimiter, key: []const u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.milliTimestamp();
        const window_start_threshold = now - @as(i64, @intCast(self.window_ms));

        if (self.entries.getPtr(key)) |entry| {
            // Check if window has expired
            if (entry.window_start < window_start_threshold) {
                // Start new window
                entry.count = 1;
                entry.window_start = now;
                return true;
            }

            // Check if under limit
            if (entry.count >= self.max_requests) {
                return false;
            }

            // Increment and allow
            entry.count += 1;
            return true;
        }

        // New key - create entry
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);

        try self.entries.put(key_copy, .{
            .count = 1,
            .window_start = now,
        });

        return true;
    }

    /// Get remaining requests for a key
    pub fn getRemaining(self: *RateLimiter, key: []const u8) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.milliTimestamp();
        const window_start_threshold = now - @as(i64, @intCast(self.window_ms));

        if (self.entries.get(key)) |entry| {
            if (entry.window_start < window_start_threshold) {
                // Window expired, full limit available
                return self.max_requests;
            }
            if (entry.count >= self.max_requests) {
                return 0;
            }
            return self.max_requests - entry.count;
        }

        // Key not found, full limit available
        return self.max_requests;
    }

    /// Reset rate limit for a key
    pub fn reset(self: *RateLimiter, key: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entries.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    /// Cleanup expired entries, returns number removed
    pub fn cleanup(self: *RateLimiter) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.milliTimestamp();
        const window_start_threshold = now - @as(i64, @intCast(self.window_ms));

        var to_remove: std.ArrayListUnmanaged([]const u8) = .empty;
        defer to_remove.deinit(self.allocator);

        // Find expired entries
        var iter = self.entries.iterator();
        while (iter.next()) |kv| {
            if (kv.value_ptr.window_start < window_start_threshold) {
                to_remove.append(self.allocator, kv.key_ptr.*) catch continue;
            }
        }

        // Remove them
        var removed: u32 = 0;
        for (to_remove.items) |key| {
            if (self.entries.fetchRemove(key)) |kv| {
                self.allocator.free(kv.key);
                removed += 1;
            }
        }

        return removed;
    }

    /// Get number of tracked keys
    pub fn count(self: *RateLimiter) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return @intCast(self.entries.count());
    }
};

// ============================================================================
// C FFI Interface for Bun
// ============================================================================

var global_limiter: ?*RateLimiter = null;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Initialize the rate limiter
export fn ratelimit_init(max_requests: u32, window_ms: u64) bool {
    if (global_limiter != null) return true;

    const allocator = gpa.allocator();
    const limiter = allocator.create(RateLimiter) catch return false;
    limiter.* = RateLimiter.init(allocator, max_requests, window_ms);
    global_limiter = limiter;
    return true;
}

/// Cleanup the rate limiter
export fn ratelimit_cleanup() void {
    const allocator = gpa.allocator();
    if (global_limiter) |limiter| {
        limiter.deinit();
        allocator.destroy(limiter);
        global_limiter = null;
    }
}

/// Check if a request is allowed for the given key
/// Returns true if allowed, false if rate limited
export fn ratelimit_check(key: [*:0]const u8) bool {
    const limiter = global_limiter orelse return false;
    const key_slice = std.mem.span(key);
    return limiter.check(key_slice) catch false;
}

/// Get remaining requests for a key
export fn ratelimit_get_remaining(key: [*:0]const u8) u32 {
    const limiter = global_limiter orelse return 0;
    const key_slice = std.mem.span(key);
    return limiter.getRemaining(key_slice);
}

/// Reset rate limit for a key
export fn ratelimit_reset(key: [*:0]const u8) void {
    const limiter = global_limiter orelse return;
    const key_slice = std.mem.span(key);
    limiter.reset(key_slice);
}

/// Cleanup expired entries, returns number removed
export fn ratelimit_expire() u32 {
    const limiter = global_limiter orelse return 0;
    return limiter.cleanup();
}

/// Get number of tracked keys
export fn ratelimit_count() u32 {
    const limiter = global_limiter orelse return 0;
    return limiter.count();
}

// ============================================================================
// Tests
// ============================================================================

test "basic rate limiting" {
    const allocator = std.testing.allocator;

    var limiter = RateLimiter.init(allocator, 3, 1000); // 3 requests per second
    defer limiter.deinit();

    // First 3 requests should succeed
    try std.testing.expect(try limiter.check("user1"));
    try std.testing.expect(try limiter.check("user1"));
    try std.testing.expect(try limiter.check("user1"));

    // 4th request should be rate limited
    try std.testing.expect(!try limiter.check("user1"));
    try std.testing.expect(!try limiter.check("user1"));
}

test "different keys are independent" {
    const allocator = std.testing.allocator;

    var limiter = RateLimiter.init(allocator, 2, 1000);
    defer limiter.deinit();

    // Use up user1's limit
    try std.testing.expect(try limiter.check("user1"));
    try std.testing.expect(try limiter.check("user1"));
    try std.testing.expect(!try limiter.check("user1"));

    // user2 should still have full limit
    try std.testing.expect(try limiter.check("user2"));
    try std.testing.expect(try limiter.check("user2"));
    try std.testing.expect(!try limiter.check("user2"));
}

test "get remaining requests" {
    const allocator = std.testing.allocator;

    var limiter = RateLimiter.init(allocator, 5, 1000);
    defer limiter.deinit();

    try std.testing.expectEqual(@as(u32, 5), limiter.getRemaining("user1"));

    _ = try limiter.check("user1");
    try std.testing.expectEqual(@as(u32, 4), limiter.getRemaining("user1"));

    _ = try limiter.check("user1");
    _ = try limiter.check("user1");
    try std.testing.expectEqual(@as(u32, 2), limiter.getRemaining("user1"));
}

test "reset clears limit" {
    const allocator = std.testing.allocator;

    var limiter = RateLimiter.init(allocator, 2, 1000);
    defer limiter.deinit();

    // Use up limit
    _ = try limiter.check("user1");
    _ = try limiter.check("user1");
    try std.testing.expect(!try limiter.check("user1"));

    // Reset
    limiter.reset("user1");

    // Should have full limit again
    try std.testing.expect(try limiter.check("user1"));
    try std.testing.expect(try limiter.check("user1"));
}

test "window expiration" {
    const allocator = std.testing.allocator;

    // Very short window for testing
    var limiter = RateLimiter.init(allocator, 2, 50); // 50ms window
    defer limiter.deinit();

    // Use up limit
    _ = try limiter.check("user1");
    _ = try limiter.check("user1");
    try std.testing.expect(!try limiter.check("user1"));

    // Wait for window to expire
    std.Thread.sleep(60 * std.time.ns_per_ms);

    // Should have full limit again
    try std.testing.expect(try limiter.check("user1"));
}

test "cleanup removes expired entries" {
    const allocator = std.testing.allocator;

    var limiter = RateLimiter.init(allocator, 10, 50); // 50ms window
    defer limiter.deinit();

    // Create some entries
    _ = try limiter.check("user1");
    _ = try limiter.check("user2");
    _ = try limiter.check("user3");

    try std.testing.expectEqual(@as(u32, 3), limiter.count());

    // Wait for expiration
    std.Thread.sleep(60 * std.time.ns_per_ms);

    // Cleanup should remove all expired
    const removed = limiter.cleanup();
    try std.testing.expectEqual(@as(u32, 3), removed);
    try std.testing.expectEqual(@as(u32, 0), limiter.count());
}

test "count tracks entries" {
    const allocator = std.testing.allocator;

    var limiter = RateLimiter.init(allocator, 10, 1000);
    defer limiter.deinit();

    try std.testing.expectEqual(@as(u32, 0), limiter.count());

    _ = try limiter.check("user1");
    try std.testing.expectEqual(@as(u32, 1), limiter.count());

    _ = try limiter.check("user2");
    try std.testing.expectEqual(@as(u32, 2), limiter.count());

    // Same key doesn't increase count
    _ = try limiter.check("user1");
    try std.testing.expectEqual(@as(u32, 2), limiter.count());
}
