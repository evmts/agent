const std = @import("std");
const net = std.net;
const testing = std.testing;
const bindings = @import("bindings.zig");

pub const SecurityError = error{
    RateLimitExceeded,
    TooManyConnections,
    ConnectionTimeout,
    InvalidAddress,
} || error{OutOfMemory};

pub const RateLimiter = struct {
    attempts: std.HashMap(u32, AttemptRecord, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    max_attempts: u32,
    window_seconds: u32,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    const AttemptRecord = struct {
        count: u32,
        first_attempt: i64,
        last_attempt: i64,
    };

    pub fn init(allocator: std.mem.Allocator, max_attempts: u32, window_seconds: u32) RateLimiter {
        return RateLimiter{
            .attempts = std.HashMap(u32, AttemptRecord, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .max_attempts = max_attempts,
            .window_seconds = window_seconds,
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *RateLimiter) void {
        self.attempts.deinit();
    }

    pub fn checkConnection(self: *RateLimiter, address: net.Address) SecurityError!bool {
        const ip_hash = self.hashAddress(address);
        const now = std.time.timestamp();

        self.mutex.lock();
        defer self.mutex.unlock();

        const gop = self.attempts.getOrPut(ip_hash) catch return SecurityError.OutOfMemory;
        
        if (!gop.found_existing) {
            gop.value_ptr.* = AttemptRecord{
                .count = 1,
                .first_attempt = now,
                .last_attempt = now,
            };
            return true;
        }

        const record = gop.value_ptr;
        
        // Reset window if enough time has passed
        if (now - record.first_attempt > self.window_seconds) {
            record.count = 1;
            record.first_attempt = now;
            record.last_attempt = now;
            return true;
        }

        record.count += 1;
        record.last_attempt = now;

        if (record.count > self.max_attempts) {
            std.log.warn("Rate limit exceeded for IP hash: {d}", .{ip_hash});
            return SecurityError.RateLimitExceeded;
        }

        return true;
    }

    pub fn recordFailedAuth(self: *RateLimiter, address: net.Address) SecurityError!void {
        const ip_hash = self.hashAddress(address);
        const now = std.time.timestamp();

        self.mutex.lock();
        defer self.mutex.unlock();

        const gop = self.attempts.getOrPut(ip_hash) catch return SecurityError.OutOfMemory;
        
        if (!gop.found_existing) {
            gop.value_ptr.* = AttemptRecord{
                .count = 1,
                .first_attempt = now,
                .last_attempt = now,
            };
            return;
        }

        const record = gop.value_ptr;
        
        // Reset window if enough time has passed
        if (now - record.first_attempt > self.window_seconds) {
            record.count = 1;
            record.first_attempt = now;
        } else {
            record.count += 1;
        }
        
        record.last_attempt = now;
    }

    pub fn cleanupExpired(self: *RateLimiter) void {
        const now = std.time.timestamp();
        
        self.mutex.lock();
        defer self.mutex.unlock();

        var iterator = self.attempts.iterator();
        var keys_to_remove = std.ArrayList(u32).init(self.allocator);
        defer keys_to_remove.deinit();

        while (iterator.next()) |entry| {
            if (now - entry.value_ptr.last_attempt > self.window_seconds * 2) {
                keys_to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        for (keys_to_remove.items) |key| {
            _ = self.attempts.remove(key);
        }
    }

    fn hashAddress(self: *RateLimiter, address: net.Address) u32 {
        _ = self;
        switch (address.any.family) {
            std.posix.AF.INET => {
                return @as(u32, @bitCast(address.in.sa.addr));
            },
            std.posix.AF.INET6 => {
                const bytes = std.mem.asBytes(&address.in6.sa.addr);
                return std.hash.crc.Crc32.hash(bytes);
            },
            else => return 0,
        }
    }
};

pub const ConnectionTracker = struct {
    connections: std.HashMap(u32, ConnectionInfo, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    max_connections: u32,
    max_connections_per_ip: u32,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    total_connections: u32,

    const ConnectionInfo = struct {
        count: u32,
        first_connection: i64,
    };

    pub fn init(allocator: std.mem.Allocator, max_connections: u32, max_connections_per_ip: u32) ConnectionTracker {
        return ConnectionTracker{
            .connections = std.HashMap(u32, ConnectionInfo, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .max_connections = max_connections,
            .max_connections_per_ip = max_connections_per_ip,
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
            .total_connections = 0,
        };
    }

    pub fn deinit(self: *ConnectionTracker) void {
        self.connections.deinit();
    }

    pub fn add(self: *ConnectionTracker, address: net.Address) SecurityError!void {
        const ip_hash = self.hashAddress(address);
        const now = std.time.timestamp();

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.total_connections >= self.max_connections) {
            return SecurityError.TooManyConnections;
        }

        const gop = self.connections.getOrPut(ip_hash) catch return SecurityError.OutOfMemory;
        
        if (!gop.found_existing) {
            gop.value_ptr.* = ConnectionInfo{
                .count = 1,
                .first_connection = now,
            };
        } else {
            if (gop.value_ptr.count >= self.max_connections_per_ip) {
                return SecurityError.TooManyConnections;
            }
            gop.value_ptr.count += 1;
        }

        self.total_connections += 1;
    }

    pub fn remove(self: *ConnectionTracker, address: net.Address) void {
        const ip_hash = self.hashAddress(address);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.connections.getPtr(ip_hash)) |info| {
            info.count -= 1;
            if (info.count == 0) {
                _ = self.connections.remove(ip_hash);
            }
            
            if (self.total_connections > 0) {
                self.total_connections -= 1;
            }
        }
    }

    pub fn getConnectionCount(self: *ConnectionTracker) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.total_connections;
    }

    fn hashAddress(self: *ConnectionTracker, address: net.Address) u32 {
        _ = self;
        switch (address.any.family) {
            std.posix.AF.INET => {
                return @as(u32, @bitCast(address.in.sa.addr));
            },
            std.posix.AF.INET6 => {
                const bytes = std.mem.asBytes(&address.in6.sa.addr);
                return std.hash.crc.Crc32.hash(bytes);
            },
            else => return 0,
        }
    }
};

pub const KeyType = enum(u8) {
    User = 1,
    Deploy = 2,
    Principal = 3,
};

pub const KeyInfo = struct {
    key_type: KeyType,
    fingerprint: []const u8,
    key_id: i64,
};

pub fn logAuthenticationAttempt(
    remote_addr: []const u8,
    username: []const u8,
    authenticated: bool,
    key_info: ?KeyInfo,
    error_reason: ?[]const u8,
) void {
    if (authenticated) {
        if (key_info) |ki| {
            switch (ki.key_type) {
                .Deploy => std.log.info("SSH: Deploy key authentication success from {s} (fingerprint: {s})", 
                    .{ remote_addr, ki.fingerprint }),
                .Principal => std.log.info("SSH: Principal authentication success from {s} (principal: {s})", 
                    .{ remote_addr, username }),
                .User => std.log.info("SSH: User authentication success from {s} (user: {s})", 
                    .{ remote_addr, username }),
            }
        }
    } else {
        if (error_reason) |reason| {
            std.log.warn("Failed authentication attempt from {s}: {s}", .{ remote_addr, reason });
        }
        // Standard message for fail2ban
        std.log.warn("Failed authentication attempt from {s}", .{remote_addr});
    }
}

pub fn logCommandExecution(
    user_id: i64,
    username: []const u8,
    command: []const u8,
    repo_path: []const u8,
    success: bool,
) void {
    if (success) {
        std.log.info("SSH: User {s} ({d}) executed '{s}' on repository '{s}'", 
            .{ username, user_id, command, repo_path });
    } else {
        std.log.warn("SSH: User {s} ({d}) failed to execute '{s}' on repository '{s}'", 
            .{ username, user_id, command, repo_path });
    }
}

pub fn logSecurityEvent(
    event_type: []const u8,
    remote_addr: []const u8,
    details: []const u8,
) void {
    std.log.warn("SSH Security Event: {s} from {s} - {s}", 
        .{ event_type, remote_addr, details });
}

// Tests
test "RateLimiter allows connections within limit" {
    const allocator = testing.allocator;
    var rate_limiter = RateLimiter.init(allocator, 5, 300);
    defer rate_limiter.deinit();

    const addr = try net.Address.parseIp4("192.168.1.100", 22);

    // Should allow first 5 connections
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const allowed = try rate_limiter.checkConnection(addr);
        try testing.expect(allowed);
    }

    // 6th connection should be blocked
    try testing.expectError(SecurityError.RateLimitExceeded, rate_limiter.checkConnection(addr));
}

test "RateLimiter resets after window expires" {
    const allocator = testing.allocator;
    var rate_limiter = RateLimiter.init(allocator, 2, 1); // 1 second window
    defer rate_limiter.deinit();

    const addr = try net.Address.parseIp4("192.168.1.100", 22);

    // Exhaust limit
    _ = try rate_limiter.checkConnection(addr);
    _ = try rate_limiter.checkConnection(addr);
    try testing.expectError(SecurityError.RateLimitExceeded, rate_limiter.checkConnection(addr));

    // Wait for window to expire (simulate by modifying time)
    std.time.sleep(1100 * std.time.ns_per_ms); // 1.1 seconds

    // Should allow connections again
    const allowed = try rate_limiter.checkConnection(addr);
    try testing.expect(allowed);
}

test "RateLimiter handles different IP addresses separately" {
    const allocator = testing.allocator;
    var rate_limiter = RateLimiter.init(allocator, 2, 300);
    defer rate_limiter.deinit();

    const addr1 = try net.Address.parseIp4("192.168.1.100", 22);
    const addr2 = try net.Address.parseIp4("192.168.1.101", 22);

    // Exhaust limit for addr1
    _ = try rate_limiter.checkConnection(addr1);
    _ = try rate_limiter.checkConnection(addr1);
    try testing.expectError(SecurityError.RateLimitExceeded, rate_limiter.checkConnection(addr1));

    // addr2 should still be allowed
    const allowed = try rate_limiter.checkConnection(addr2);
    try testing.expect(allowed);
}

test "ConnectionTracker enforces global connection limit" {
    const allocator = testing.allocator;
    var tracker = ConnectionTracker.init(allocator, 2, 10);
    defer tracker.deinit();

    const addr1 = try net.Address.parseIp4("192.168.1.100", 22);
    const addr2 = try net.Address.parseIp4("192.168.1.101", 22);

    // Add connections up to limit
    try tracker.add(addr1);
    try tracker.add(addr2);

    // Third connection should fail
    try testing.expectError(SecurityError.TooManyConnections, tracker.add(addr1));

    // Verify count
    try testing.expectEqual(@as(u32, 2), tracker.getConnectionCount());
}

test "ConnectionTracker enforces per-IP connection limit" {
    const allocator = testing.allocator;
    var tracker = ConnectionTracker.init(allocator, 10, 2);
    defer tracker.deinit();

    const addr = try net.Address.parseIp4("192.168.1.100", 22);

    // Add connections up to per-IP limit
    try tracker.add(addr);
    try tracker.add(addr);

    // Third connection from same IP should fail
    try testing.expectError(SecurityError.TooManyConnections, tracker.add(addr));
}

test "ConnectionTracker properly removes connections" {
    const allocator = testing.allocator;
    var tracker = ConnectionTracker.init(allocator, 10, 10);
    defer tracker.deinit();

    const addr = try net.Address.parseIp4("192.168.1.100", 22);

    // Add connection
    try tracker.add(addr);
    try testing.expectEqual(@as(u32, 1), tracker.getConnectionCount());

    // Remove connection
    tracker.remove(addr);
    try testing.expectEqual(@as(u32, 0), tracker.getConnectionCount());

    // Should be able to add again
    try tracker.add(addr);
    try testing.expectEqual(@as(u32, 1), tracker.getConnectionCount());
}

test "RateLimiter cleanup removes expired entries" {
    const allocator = testing.allocator;
    var rate_limiter = RateLimiter.init(allocator, 5, 1); // 1 second window
    defer rate_limiter.deinit();

    const addr = try net.Address.parseIp4("192.168.1.100", 22);

    // Make some attempts
    _ = try rate_limiter.checkConnection(addr);
    try testing.expect(rate_limiter.attempts.count() == 1);

    // Wait longer than cleanup threshold
    std.time.sleep(2100 * std.time.ns_per_ms); // 2.1 seconds

    // Cleanup should remove expired entries
    rate_limiter.cleanupExpired();
    try testing.expect(rate_limiter.attempts.count() == 0);
}

test "RateLimiter recordFailedAuth increases attempt count" {
    const allocator = testing.allocator;
    var rate_limiter = RateLimiter.init(allocator, 3, 300);
    defer rate_limiter.deinit();

    const addr = try net.Address.parseIp4("192.168.1.100", 22);

    // Record failed auth attempts
    try rate_limiter.recordFailedAuth(addr);
    try rate_limiter.recordFailedAuth(addr);
    try rate_limiter.recordFailedAuth(addr);

    // Next connection attempt should be blocked
    try testing.expectError(SecurityError.RateLimitExceeded, rate_limiter.checkConnection(addr));
}

test "logAuthenticationAttempt handles all key types" {
    // Test User key
    logAuthenticationAttempt(
        "192.168.1.100",
        "testuser",
        true,
        KeyInfo{ .key_type = .User, .fingerprint = "SHA256:test", .key_id = 1 },
        null,
    );

    // Test Deploy key
    logAuthenticationAttempt(
        "192.168.1.100",
        "deploy",
        true,
        KeyInfo{ .key_type = .Deploy, .fingerprint = "SHA256:deploy", .key_id = 2 },
        null,
    );

    // Test Principal key
    logAuthenticationAttempt(
        "192.168.1.100",
        "principal@example.com",
        true,
        KeyInfo{ .key_type = .Principal, .fingerprint = "SHA256:principal", .key_id = 3 },
        null,
    );

    // Test failed auth
    logAuthenticationAttempt(
        "192.168.1.100",
        "baduser",
        false,
        null,
        "Invalid key",
    );
}

test "logCommandExecution logs success and failure" {
    logCommandExecution(123, "testuser", "git-upload-pack", "owner/repo", true);
    logCommandExecution(123, "testuser", "git-upload-pack", "owner/repo", false);
}

test "logSecurityEvent logs security events" {
    logSecurityEvent("RATE_LIMIT", "192.168.1.100", "Too many attempts");
}