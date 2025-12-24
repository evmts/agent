/// IP-based rate limiter for SSH connections
/// Uses sliding window with exponential backoff for repeated failures
const std = @import("std");
const log = std.log.scoped(.ssh_rate_limit);

/// Configuration for rate limiting
pub const Config = struct {
    /// Max connections per IP per window
    max_connections_per_minute: u32 = 20,
    /// Max auth failures before ban
    max_auth_failures: u32 = 5,
    /// Ban duration in seconds (starts at 15 min, doubles each time)
    initial_ban_duration: i64 = 15 * 60,
    /// Max ban duration (24 hours)
    max_ban_duration: i64 = 24 * 60 * 60,
    /// Window size in seconds
    window_seconds: i64 = 60,
};

/// Information about connection attempts from an IP
const AttemptInfo = struct {
    count: u32,
    window_start: i64,
    auth_failures: u32,
    /// Number of times this IP has been banned (for exponential backoff)
    ban_count: u32 = 0,
};

/// Information about a banned IP
const BanInfo = struct {
    expiry: i64,
    ban_count: u32,
};

/// IP-based rate limiter for SSH connections
pub const RateLimiter = struct {
    allocator: std.mem.Allocator,

    /// Track connection attempts per IP
    attempts: std.StringHashMap(AttemptInfo),

    /// Track banned IPs with expiry timestamp
    bans: std.StringHashMap(BanInfo),

    /// Owned IP strings for hash map keys
    owned_keys: std.ArrayListUnmanaged([]u8) = .{},

    mutex: std.Thread.Mutex = .{},

    config: Config,

    pub fn init(allocator: std.mem.Allocator, config: Config) RateLimiter {
        return .{
            .allocator = allocator,
            .attempts = std.StringHashMap(AttemptInfo).init(allocator),
            .bans = std.StringHashMap(BanInfo).init(allocator),
            .config = config,
        };
    }

    pub fn deinit(self: *RateLimiter) void {
        // Free owned keys
        for (self.owned_keys.items) |key| {
            self.allocator.free(key);
        }
        self.owned_keys.deinit(self.allocator);
        self.attempts.deinit();
        self.bans.deinit();
    }

    /// Get or create an owned key for the IP address
    fn getOrCreateKey(self: *RateLimiter, ip: []const u8) ![]const u8 {
        // Check if we already have this key
        if (self.attempts.getKey(ip)) |existing| {
            return existing;
        }
        if (self.bans.getKey(ip)) |existing| {
            return existing;
        }

        // Create a new owned copy
        const owned = try self.allocator.dupe(u8, ip);
        try self.owned_keys.append(self.allocator, owned);
        return owned;
    }

    /// Check if connection should be allowed
    /// Returns error if rate limited or banned
    pub fn checkConnection(self: *RateLimiter, ip: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();

        // Check if IP is banned
        if (self.bans.get(ip)) |ban_info| {
            if (now < ban_info.expiry) {
                const remaining = ban_info.expiry - now;
                log.warn("Connection from banned IP {s}, expires in {d}s", .{
                    ip, remaining,
                });
                return error.IPBanned;
            } else {
                // Ban expired, remove it
                _ = self.bans.remove(ip);
            }
        }

        // Get or create owned key
        const owned_key = self.getOrCreateKey(ip) catch |err| {
            log.err("Failed to allocate key for IP {s}: {}", .{ ip, err });
            return error.OutOfMemory;
        };

        // Get or create attempt info
        const gop = self.attempts.getOrPut(owned_key) catch |err| {
            log.err("Failed to track attempt for IP {s}: {}", .{ ip, err });
            return error.OutOfMemory;
        };
        if (!gop.found_existing) {
            gop.value_ptr.* = .{
                .count = 0,
                .window_start = now,
                .auth_failures = 0,
            };
        }

        const info = gop.value_ptr;

        // Check if we're in a new window
        if (now - info.window_start > self.config.window_seconds) {
            info.count = 0;
            info.window_start = now;
        }

        // Check rate limit
        if (info.count >= self.config.max_connections_per_minute) {
            log.warn("Rate limit exceeded for IP {s}: {d} connections in window", .{
                ip, info.count,
            });
            return error.RateLimitExceeded;
        }

        // Increment counter
        info.count += 1;
    }

    /// Record an authentication failure
    /// May result in IP ban
    pub fn recordAuthFailure(self: *RateLimiter, ip: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();

        if (self.attempts.getPtr(ip)) |info| {
            info.auth_failures += 1;

            if (info.auth_failures >= self.config.max_auth_failures) {
                // Calculate ban duration with exponential backoff
                var ban_duration = self.config.initial_ban_duration;
                var i: u32 = 0;
                while (i < info.ban_count and ban_duration < self.config.max_ban_duration) : (i += 1) {
                    ban_duration = @min(ban_duration * 2, self.config.max_ban_duration);
                }

                // Get or create owned key for ban
                const owned_key = self.getOrCreateKey(ip) catch {
                    log.err("Failed to allocate key for banning IP {s}", .{ip});
                    return;
                };

                // Ban the IP
                self.bans.put(owned_key, .{
                    .expiry = now + ban_duration,
                    .ban_count = info.ban_count + 1,
                }) catch {
                    log.err("Failed to ban IP {s}", .{ip});
                    return;
                };

                log.warn("IP {s} banned for {d}s after {d} auth failures (ban #{d})", .{
                    ip, ban_duration, info.auth_failures, info.ban_count + 1,
                });

                // Update ban count and reset failure counter
                info.ban_count += 1;
                info.auth_failures = 0;
            }
        }
    }

    /// Record a successful authentication (resets failure counter)
    pub fn recordAuthSuccess(self: *RateLimiter, ip: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.attempts.getPtr(ip)) |info| {
            info.auth_failures = 0;
        }
    }

    /// Get the number of currently banned IPs
    pub fn getBannedCount(self: *RateLimiter) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.bans.count();
    }

    /// Check if an IP is currently banned
    pub fn isBanned(self: *RateLimiter, ip: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.bans.get(ip)) |ban_info| {
            return std.time.timestamp() < ban_info.expiry;
        }
        return false;
    }

    /// Cleanup expired entries (call periodically)
    pub fn cleanup(self: *RateLimiter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();

        // Collect keys to remove (can't modify during iteration)
        var bans_to_remove: std.ArrayListUnmanaged([]const u8) = .{};
        defer bans_to_remove.deinit(self.allocator);

        var attempts_to_remove: std.ArrayListUnmanaged([]const u8) = .{};
        defer attempts_to_remove.deinit(self.allocator);

        // Find expired bans
        var ban_iter = self.bans.iterator();
        while (ban_iter.next()) |entry| {
            if (now >= entry.value_ptr.expiry) {
                bans_to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }

        // Find old attempt entries (older than 1 hour)
        var attempt_iter = self.attempts.iterator();
        while (attempt_iter.next()) |entry| {
            if (now - entry.value_ptr.window_start > 3600) {
                attempts_to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }

        // Remove collected entries
        for (bans_to_remove.items) |key| {
            _ = self.bans.remove(key);
        }

        for (attempts_to_remove.items) |key| {
            _ = self.attempts.remove(key);
        }

        if (bans_to_remove.items.len > 0 or attempts_to_remove.items.len > 0) {
            log.info("Cleanup: removed {d} expired bans, {d} old attempt records", .{
                bans_to_remove.items.len, attempts_to_remove.items.len,
            });
        }
    }
};

test "RateLimiter basic operations" {
    const allocator = std.testing.allocator;

    var limiter = RateLimiter.init(allocator, .{
        .max_connections_per_minute = 5,
        .max_auth_failures = 3,
        .initial_ban_duration = 10,
    });
    defer limiter.deinit();

    const test_ip = "192.168.1.100";

    // Should allow initial connections
    try limiter.checkConnection(test_ip);
    try limiter.checkConnection(test_ip);
    try limiter.checkConnection(test_ip);
    try limiter.checkConnection(test_ip);
    try limiter.checkConnection(test_ip);

    // Should deny after limit reached
    try std.testing.expectError(error.RateLimitExceeded, limiter.checkConnection(test_ip));
}

test "RateLimiter auth failure banning" {
    const allocator = std.testing.allocator;

    var limiter = RateLimiter.init(allocator, .{
        .max_auth_failures = 3,
        .initial_ban_duration = 1, // 1 second for testing
    });
    defer limiter.deinit();

    const test_ip = "10.0.0.1";

    // Initial connection should be allowed
    try limiter.checkConnection(test_ip);

    // Record auth failures
    limiter.recordAuthFailure(test_ip);
    try std.testing.expect(!limiter.isBanned(test_ip));

    limiter.recordAuthFailure(test_ip);
    try std.testing.expect(!limiter.isBanned(test_ip));

    limiter.recordAuthFailure(test_ip);
    // Should be banned now
    try std.testing.expect(limiter.isBanned(test_ip));

    // Connection should be denied
    try std.testing.expectError(error.IPBanned, limiter.checkConnection(test_ip));
}

test "RateLimiter auth success resets failures" {
    const allocator = std.testing.allocator;

    var limiter = RateLimiter.init(allocator, .{
        .max_auth_failures = 3,
    });
    defer limiter.deinit();

    const test_ip = "172.16.0.1";

    try limiter.checkConnection(test_ip);

    // Two failures
    limiter.recordAuthFailure(test_ip);
    limiter.recordAuthFailure(test_ip);

    // Success should reset
    limiter.recordAuthSuccess(test_ip);

    // Two more failures should not trigger ban
    limiter.recordAuthFailure(test_ip);
    limiter.recordAuthFailure(test_ip);

    try std.testing.expect(!limiter.isBanned(test_ip));
}
