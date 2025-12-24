/// Tracks and limits concurrent SSH connections
const std = @import("std");
const log = std.log.scoped(.ssh_connections);

/// Configuration for connection limiting
pub const Config = struct {
    /// Max concurrent connections total
    max_total_connections: u32 = 100,
    /// Max concurrent connections per IP
    max_per_ip_connections: u32 = 10,
};

/// Tracks and limits concurrent SSH connections
pub const ConnectionLimiter = struct {
    allocator: std.mem.Allocator,

    /// Current active connections per IP
    connections_per_ip: std.StringHashMap(u32),

    /// Owned IP strings for hash map keys
    owned_keys: std.ArrayListUnmanaged([]u8) = .{},

    /// Total active connections
    total_connections: std.atomic.Value(u32),

    mutex: std.Thread.Mutex = .{},

    config: Config,

    pub fn init(allocator: std.mem.Allocator, config: Config) ConnectionLimiter {
        return .{
            .allocator = allocator,
            .connections_per_ip = std.StringHashMap(u32).init(allocator),
            .total_connections = std.atomic.Value(u32).init(0),
            .config = config,
        };
    }

    pub fn deinit(self: *ConnectionLimiter) void {
        for (self.owned_keys.items) |key| {
            self.allocator.free(key);
        }
        self.owned_keys.deinit(self.allocator);
        self.connections_per_ip.deinit();
    }

    /// Get or create an owned key for the IP address
    fn getOrCreateKey(self: *ConnectionLimiter, ip: []const u8) ![]const u8 {
        if (self.connections_per_ip.getKey(ip)) |existing| {
            return existing;
        }

        const owned = try self.allocator.dupe(u8, ip);
        try self.owned_keys.append(self.allocator, owned);
        return owned;
    }

    /// Try to acquire a connection slot
    /// Returns error if limits exceeded
    pub fn acquire(self: *ConnectionLimiter, ip: []const u8) !void {
        // Check total limit first (atomic, no lock needed)
        const total = self.total_connections.load(.seq_cst);
        if (total >= self.config.max_total_connections) {
            log.warn("Total connection limit reached: {d}/{d}", .{
                total, self.config.max_total_connections,
            });
            return error.TooManyConnections;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        // Get or create owned key
        const owned_key = try self.getOrCreateKey(ip);

        // Get or create per-IP count
        const gop = try self.connections_per_ip.getOrPut(owned_key);
        const current = if (gop.found_existing) gop.value_ptr.* else 0;

        if (current >= self.config.max_per_ip_connections) {
            log.warn("Per-IP connection limit reached for {s}: {d}/{d}", .{
                ip, current, self.config.max_per_ip_connections,
            });
            return error.TooManyConnectionsFromIP;
        }

        // Acquire slot
        gop.value_ptr.* = current + 1;
        _ = self.total_connections.fetchAdd(1, .seq_cst);

        log.debug("Connection acquired for {s}: {d} from IP, {d} total", .{
            ip, current + 1, self.total_connections.load(.seq_cst),
        });
    }

    /// Release a connection slot
    pub fn release(self: *ConnectionLimiter, ip: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.connections_per_ip.getPtr(ip)) |count| {
            if (count.* > 0) {
                count.* -= 1;
            }
        }

        const prev = self.total_connections.fetchSub(1, .seq_cst);
        if (prev == 0) {
            // Underflow protection - this shouldn't happen but be safe
            _ = self.total_connections.fetchAdd(1, .seq_cst);
            log.warn("Connection count underflow detected for {s}", .{ip});
        } else {
            log.debug("Connection released for {s}: {d} total remaining", .{
                ip, prev - 1,
            });
        }
    }

    /// Get current total connection count
    pub fn getTotal(self: *ConnectionLimiter) u32 {
        return self.total_connections.load(.seq_cst);
    }

    /// Get connection count for a specific IP
    pub fn getCountForIP(self: *ConnectionLimiter, ip: []const u8) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.connections_per_ip.get(ip) orelse 0;
    }

    /// Get the number of unique IPs with active connections
    pub fn getUniqueIPCount(self: *ConnectionLimiter) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        var count: usize = 0;
        var iter = self.connections_per_ip.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* > 0) {
                count += 1;
            }
        }
        return count;
    }

    /// Cleanup entries with zero connections
    pub fn cleanup(self: *ConnectionLimiter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var to_remove: std.ArrayListUnmanaged([]const u8) = .{};
        defer to_remove.deinit(self.allocator);

        var iter = self.connections_per_ip.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* == 0) {
                to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |key| {
            _ = self.connections_per_ip.remove(key);
        }

        if (to_remove.items.len > 0) {
            log.debug("Cleaned up {d} stale IP entries", .{to_remove.items.len});
        }
    }
};

test "ConnectionLimiter basic operations" {
    const allocator = std.testing.allocator;

    var limiter = ConnectionLimiter.init(allocator, .{
        .max_total_connections = 5,
        .max_per_ip_connections = 3,
    });
    defer limiter.deinit();

    const ip1 = "192.168.1.1";
    const ip2 = "192.168.1.2";

    // Acquire connections for ip1
    try limiter.acquire(ip1);
    try limiter.acquire(ip1);
    try limiter.acquire(ip1);

    try std.testing.expectEqual(@as(u32, 3), limiter.getTotal());
    try std.testing.expectEqual(@as(u32, 3), limiter.getCountForIP(ip1));

    // Should fail - per-IP limit reached
    try std.testing.expectError(error.TooManyConnectionsFromIP, limiter.acquire(ip1));

    // But ip2 should still work
    try limiter.acquire(ip2);
    try limiter.acquire(ip2);

    try std.testing.expectEqual(@as(u32, 5), limiter.getTotal());

    // Total limit reached
    try std.testing.expectError(error.TooManyConnections, limiter.acquire(ip2));

    // Release some
    limiter.release(ip1);
    try std.testing.expectEqual(@as(u32, 4), limiter.getTotal());
    try std.testing.expectEqual(@as(u32, 2), limiter.getCountForIP(ip1));
}

test "ConnectionLimiter cleanup" {
    const allocator = std.testing.allocator;

    var limiter = ConnectionLimiter.init(allocator, .{});
    defer limiter.deinit();

    const ip = "10.0.0.1";

    try limiter.acquire(ip);
    try std.testing.expectEqual(@as(usize, 1), limiter.getUniqueIPCount());

    limiter.release(ip);
    try std.testing.expectEqual(@as(u32, 0), limiter.getCountForIP(ip));

    limiter.cleanup();
    // Entry should be removed after cleanup
}
