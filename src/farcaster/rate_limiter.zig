const std = @import("std");

/// Rate limiter for API calls with sliding window algorithm
pub const RateLimiter = struct {
    const Self = @This();
    
    const Window = struct {
        start_time: i64,
        count: u32,
    };
    
    mutex: std.Thread.Mutex,
    windows: std.StringHashMap(Window),
    max_requests: u32,
    window_ms: i64,
    enabled: bool,
    
    pub fn init(allocator: std.mem.Allocator, max_requests: u32, window_ms: i64) Self {
        return .{
            .mutex = .{},
            .windows = std.StringHashMap(Window).init(allocator),
            .max_requests = max_requests,
            .window_ms = window_ms,
            .enabled = true,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.windows.deinit();
    }
    
    pub fn setEnabled(self: *Self, enabled: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = enabled;
    }
    
    /// Check if request is allowed under rate limit
    pub fn checkLimit(self: *Self, key: []const u8) !void {
        if (!self.enabled) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const now = std.time.milliTimestamp();
        
        // Clean up expired windows periodically
        if (@mod(@as(u32, @intCast(now)), 10000) == 0) {
            self.cleanupExpiredWindows(now);
        }
        
        if (self.windows.getPtr(key)) |window| {
            if (now - window.start_time >= self.window_ms) {
                // Reset window
                window.start_time = now;
                window.count = 1;
            } else if (window.count >= self.max_requests) {
                std.log.warn("Rate limit exceeded for key: {s}", .{key});
                return error.RateLimitExceeded;
            } else {
                window.count += 1;
            }
        } else {
            try self.windows.put(key, .{
                .start_time = now,
                .count = 1,
            });
        }
    }
    
    /// Get current rate limit status for a key
    pub fn getStatus(self: *Self, key: []const u8) struct { used: u32, max: u32, reset_in_ms: i64 } {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const now = std.time.milliTimestamp();
        
        if (self.windows.get(key)) |window| {
            const reset_in = @max(0, window.start_time + self.window_ms - now);
            return .{
                .used = window.count,
                .max = self.max_requests,
                .reset_in_ms = reset_in,
            };
        }
        
        return .{
            .used = 0,
            .max = self.max_requests,
            .reset_in_ms = 0,
        };
    }
    
    /// Clean up expired windows to prevent memory leaks
    fn cleanupExpiredWindows(self: *Self, now: i64) void {
        var iter = self.windows.iterator();
        var keys_to_remove = std.ArrayList([]const u8).init(self.windows.allocator);
        defer keys_to_remove.deinit();
        
        while (iter.next()) |entry| {
            if (now - entry.value_ptr.start_time >= self.window_ms * 2) {
                keys_to_remove.append(entry.key_ptr.*) catch continue;
            }
        }
        
        for (keys_to_remove.items) |key| {
            _ = self.windows.remove(key);
        }
    }
};