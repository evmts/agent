//! Session Cleanup Service
//!
//! Periodically cleans up expired sessions and nonces from the database.
//! Runs as a background service with configurable interval.

const std = @import("std");
const db = @import("../lib/db.zig");

const log = std.log.scoped(.session_cleanup);

/// Configuration for the session cleanup service
pub const Config = struct {
    /// Cleanup interval in milliseconds (default: 5 minutes)
    cleanup_interval_ms: u64 = 5 * 60 * 1000,
};

/// Session Cleanup Service
pub const SessionCleanup = struct {
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    config: Config,
    running: std.atomic.Value(bool),
    thread: ?std.Thread,

    pub fn init(allocator: std.mem.Allocator, pool: *db.Pool, config: Config) SessionCleanup {
        return .{
            .allocator = allocator,
            .pool = pool,
            .config = config,
            .running = std.atomic.Value(bool).init(false),
            .thread = null,
        };
    }

    pub fn deinit(self: *SessionCleanup) void {
        self.stop();
    }

    /// Start the cleanup service in a background thread
    pub fn start(self: *SessionCleanup) !void {
        if (self.running.load(.acquire)) {
            return error.AlreadyRunning;
        }

        self.running.store(true, .release);

        // Run initial cleanup
        self.cleanupOnce() catch |err| {
            log.err("Initial cleanup failed: {}", .{err});
        };

        // Start background thread
        self.thread = try std.Thread.spawn(.{}, cleanupThread, .{self});

        log.info("Session cleanup service started (interval: {}ms)", .{self.config.cleanup_interval_ms});
    }

    /// Stop the cleanup service
    pub fn stop(self: *SessionCleanup) void {
        if (!self.running.load(.acquire)) {
            return;
        }

        self.running.store(false, .release);

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        log.info("Session cleanup service stopped", .{});
    }

    /// Background thread that periodically cleans up expired sessions
    fn cleanupThread(self: *SessionCleanup) void {
        log.info("Cleanup thread started", .{});

        while (self.running.load(.acquire)) {
            // Sleep for cleanup interval
            std.Thread.sleep(self.config.cleanup_interval_ms * std.time.ns_per_ms);

            // Perform cleanup
            self.cleanupOnce() catch |err| {
                log.err("Cleanup error: {}", .{err});
            };
        }

        log.info("Cleanup thread stopped", .{});
    }

    /// Perform a single cleanup operation
    fn cleanupOnce(self: *SessionCleanup) !void {
        // Cleanup expired sessions
        const cleaned_sessions = try db.cleanupExpiredSessions(self.pool);
        if (cleaned_sessions) |count| {
            if (count > 0) {
                log.info("Cleaned up {d} expired session(s)", .{count});
            }
        }

        // Cleanup expired nonces
        const cleaned_nonces = try db.cleanupExpiredNonces(self.pool);
        if (cleaned_nonces) |count| {
            if (count > 0) {
                log.info("Cleaned up {d} expired nonce(s)", .{count});
            }
        }

        // Cleanup expired rate limits
        const cleaned_rate_limits = try db.cleanupExpiredRateLimits(self.pool);
        if (cleaned_rate_limits) |count| {
            if (count > 0) {
                log.info("Cleaned up {d} expired rate limit(s)", .{count});
            }
        }
    }
};

test "SessionCleanup init/deinit" {
    const allocator = std.testing.allocator;

    // Mock pool (would use real pool in integration tests)
    var mock_pool: db.Pool = undefined;

    var cleanup = SessionCleanup.init(allocator, &mock_pool, .{});
    defer cleanup.deinit();

    try std.testing.expect(!cleanup.running.load(.acquire));
}

test "Config default values" {
    const config = Config{};

    // Default cleanup interval is 5 minutes (300,000 ms)
    try std.testing.expectEqual(@as(u64, 5 * 60 * 1000), config.cleanup_interval_ms);
}

test "Config custom interval" {
    const config = Config{
        .cleanup_interval_ms = 60 * 1000, // 1 minute
    };

    try std.testing.expectEqual(@as(u64, 60 * 1000), config.cleanup_interval_ms);
}

test "SessionCleanup initial state" {
    const allocator = std.testing.allocator;

    var mock_pool: db.Pool = undefined;

    var cleanup = SessionCleanup.init(allocator, &mock_pool, .{
        .cleanup_interval_ms = 1000,
    });
    defer cleanup.deinit();

    // Should not be running initially
    try std.testing.expect(!cleanup.running.load(.acquire));

    // Thread should be null initially
    try std.testing.expect(cleanup.thread == null);

    // Config should be set correctly
    try std.testing.expectEqual(@as(u64, 1000), cleanup.config.cleanup_interval_ms);
}

test "SessionCleanup stop when not running" {
    const allocator = std.testing.allocator;

    var mock_pool: db.Pool = undefined;

    var cleanup = SessionCleanup.init(allocator, &mock_pool, .{});

    // Stopping when not running should not cause issues
    cleanup.stop();

    try std.testing.expect(!cleanup.running.load(.acquire));
}
