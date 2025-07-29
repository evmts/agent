const std = @import("std");
const testing = std.testing;

pub const MemoryBackendError = error{
    StorageLimitExceeded,
    ObjectNotFound,
    OutOfMemory,
};

pub const MemoryConfig = struct {
    max_size_bytes: u64,
    eviction_policy: EvictionPolicy = .lru,
};

pub const EvictionPolicy = enum {
    lru,  // Least Recently Used
    lfu,  // Least Frequently Used  
    fifo, // First In, First Out
    random,
};

const ObjectInfo = struct {
    data: []u8,
    last_accessed: i64,
    access_count: u64,
    created_at: i64,
};

pub const MemoryBackend = struct {
    config: MemoryConfig,
    allocator: std.mem.Allocator,
    storage: std.StringHashMap(ObjectInfo),
    current_size: u64,
    access_order: std.ArrayList([]const u8), // For LRU tracking
    
    pub fn init(allocator: std.mem.Allocator, config: MemoryConfig) !MemoryBackend {
        return MemoryBackend{
            .allocator = allocator,
            .config = config,
            .storage = std.StringHashMap(ObjectInfo).init(allocator),
            .current_size = 0,
            .access_order = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *MemoryBackend) void {
        // Free all stored data
        var iterator = self.storage.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
        }
        self.storage.deinit();
        
        // Free access order tracking
        for (self.access_order.items) |oid| {
            // Keys are already freed above, so we don't free them again
            _ = oid;
        }
        self.access_order.deinit();
    }
    
    pub fn putObject(self: *MemoryBackend, oid: []const u8, content: []const u8) !void {
        // Check if adding this object would exceed size limit
        const content_size = content.len;
        var projected_size = self.current_size + content_size;
        
        // If object already exists, subtract its current size
        if (self.storage.get(oid)) |existing| {
            projected_size -= existing.data.len;
        }
        
        // Perform eviction if necessary
        while (projected_size > self.config.max_size_bytes and self.storage.count() > 0) {
            try self.evictObject();
            projected_size = self.current_size + content_size;
            if (self.storage.get(oid)) |existing| {
                projected_size -= existing.data.len;
            }
        }
        
        // Final check - if still too large, reject
        if (projected_size > self.config.max_size_bytes) {
            return error.StorageLimitExceeded;
        }
        
        // Store the object
        const oid_copy = try self.allocator.dupe(u8, oid);
        errdefer self.allocator.free(oid_copy);
        
        const data_copy = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(data_copy);
        
        const now = std.time.timestamp();
        const object_info = ObjectInfo{
            .data = data_copy,
            .last_accessed = now,
            .access_count = 1,
            .created_at = now,
        };
        
        // Remove existing entry if it exists
        if (self.storage.fetchRemove(oid)) |existing| {
            self.current_size -= existing.value.data.len;
            self.allocator.free(existing.key);
            self.allocator.free(existing.value.data);
            
            // Remove from access order
            for (self.access_order.items, 0..) |tracked_oid, i| {
                if (std.mem.eql(u8, tracked_oid, oid)) {
                    _ = self.access_order.swapRemove(i);
                    break;
                }
            }
        }
        
        try self.storage.put(oid_copy, object_info);
        self.current_size += content_size;
        
        // Add to access tracking
        try self.access_order.append(oid_copy);
    }
    
    pub fn getObject(self: *MemoryBackend, oid: []const u8) ![]u8 {
        var entry = self.storage.getPtr(oid) orelse return error.ObjectNotFound;
        
        // Update access information
        entry.last_accessed = std.time.timestamp();
        entry.access_count += 1;
        
        // Update LRU order (move to end)
        for (self.access_order.items, 0..) |tracked_oid, i| {
            if (std.mem.eql(u8, tracked_oid, oid)) {
                const moved_oid = self.access_order.swapRemove(i);
                try self.access_order.append(moved_oid);
                break;
            }
        }
        
        return try self.allocator.dupe(u8, entry.data);
    }
    
    pub fn deleteObject(self: *MemoryBackend, oid: []const u8) !void {
        const removed = self.storage.fetchRemove(oid) orelse return error.ObjectNotFound;
        
        self.current_size -= removed.value.data.len;
        self.allocator.free(removed.key);
        self.allocator.free(removed.value.data);
        
        // Remove from access order
        for (self.access_order.items, 0..) |tracked_oid, i| {
            if (std.mem.eql(u8, tracked_oid, oid)) {
                _ = self.access_order.swapRemove(i);
                break;
            }
        }
    }
    
    pub fn objectExists(self: *MemoryBackend, oid: []const u8) bool {
        return self.storage.contains(oid);
    }
    
    pub fn getObjectSize(self: *MemoryBackend, oid: []const u8) !u64 {
        const entry = self.storage.get(oid) orelse return error.ObjectNotFound;
        return entry.data.len;
    }
    
    pub fn getCurrentSize(self: *MemoryBackend) u64 {
        return self.current_size;
    }
    
    pub fn getObjectCount(self: *MemoryBackend) u32 {
        return @intCast(self.storage.count());
    }
    
    pub fn clear(self: *MemoryBackend) void {
        var iterator = self.storage.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
        }
        self.storage.clearAndFree();
        self.access_order.clearAndFree();
        self.current_size = 0;
    }
    
    fn evictObject(self: *MemoryBackend) !void {
        if (self.storage.count() == 0) return;
        
        const oid_to_evict = switch (self.config.eviction_policy) {
            .lru => try self.findLruObject(),
            .lfu => try self.findLfuObject(),
            .fifo => try self.findFifoObject(),
            .random => try self.findRandomObject(),
        };
        
        try self.deleteObject(oid_to_evict);
    }
    
    fn findLruObject(self: *MemoryBackend) ![]const u8 {
        // LRU is the first item in access_order
        if (self.access_order.items.len == 0) return error.ObjectNotFound;
        return self.access_order.items[0];
    }
    
    fn findLfuObject(self: *MemoryBackend) ![]const u8 {
        var min_access_count: u64 = std.math.maxInt(u64);
        var lfu_oid: ?[]const u8 = null;
        
        var iterator = self.storage.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.access_count < min_access_count) {
                min_access_count = entry.value_ptr.access_count;
                lfu_oid = entry.key_ptr.*;
            }
        }
        
        return lfu_oid orelse error.ObjectNotFound;
    }
    
    fn findFifoObject(self: *MemoryBackend) ![]const u8 {
        var oldest_time: i64 = std.math.maxInt(i64);
        var fifo_oid: ?[]const u8 = null;
        
        var iterator = self.storage.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.created_at < oldest_time) {
                oldest_time = entry.value_ptr.created_at;
                fifo_oid = entry.key_ptr.*;
            }
        }
        
        return fifo_oid orelse error.ObjectNotFound;
    }
    
    fn findRandomObject(self: *MemoryBackend) ![]const u8 {
        if (self.storage.count() == 0) return error.ObjectNotFound;
        
        var prng = std.Random.DefaultPrng.init(@bitCast(std.time.timestamp()));
        const random_index = prng.random().uintLessThan(u32, @intCast(self.storage.count()));
        
        var iterator = self.storage.iterator();
        var current_index: u32 = 0;
        while (iterator.next()) |entry| {
            if (current_index == random_index) {
                return entry.key_ptr.*;
            }
            current_index += 1;
        }
        
        return error.ObjectNotFound;
    }
};

// Tests for Phase 5: Memory Backend and Testing Infrastructure
test "memory backend provides fast in-memory storage" {
    const allocator = testing.allocator;
    
    var backend = try MemoryBackend.init(allocator, .{
        .max_size_bytes = 10 * 1024 * 1024, // 10MB limit
    });
    defer backend.deinit();
    
    const oid = "memory_test_oid_1234567890123456789012345678901234567890123456";
    const content = "memory test content";
    
    try backend.putObject(oid, content);
    
    const retrieved = try backend.getObject(oid);
    defer allocator.free(retrieved);
    
    try testing.expectEqualStrings(content, retrieved);
    
    // Test size tracking
    try testing.expectEqual(@as(u64, content.len), backend.getCurrentSize());
    try testing.expectEqual(@as(u32, 1), backend.getObjectCount());
}

test "memory backend enforces storage limits with eviction" {
    const allocator = testing.allocator;
    
    var backend = try MemoryBackend.init(allocator, .{
        .max_size_bytes = 100, // Very small limit for testing
        .eviction_policy = .lru,
    });
    defer backend.deinit();
    
    // Add objects that fit within limit
    try backend.putObject("oid1", "data1");
    try backend.putObject("oid2", "data2");
    try backend.putObject("oid3", "data3");
    
    try testing.expect(backend.objectExists("oid1"));
    try testing.expect(backend.objectExists("oid2"));
    try testing.expect(backend.objectExists("oid3"));
    
    // Add a large object that should trigger eviction
    const large_content = "x" ** 90; // 90 bytes
    try backend.putObject("large_oid", large_content);
    
    // Should have evicted some objects to make room
    try testing.expect(backend.objectExists("large_oid"));
    try testing.expect(backend.getCurrentSize() <= 100);
}

test "memory backend rejects objects that exceed total capacity" {
    const allocator = testing.allocator;
    
    var backend = try MemoryBackend.init(allocator, .{
        .max_size_bytes = 10, // Very small limit
    });
    defer backend.deinit();
    
    const large_content = "x" ** 20; // 20 bytes, larger than capacity
    
    try testing.expectError(error.StorageLimitExceeded, 
        backend.putObject("large_oid", large_content));
}

test "memory backend handles CRUD operations correctly" {
    const allocator = testing.allocator;
    
    var backend = try MemoryBackend.init(allocator, .{
        .max_size_bytes = 1024,
    });
    defer backend.deinit();
    
    const oid = "crud_test_oid";
    const content = "CRUD test content";
    
    // Create
    try backend.putObject(oid, content);
    try testing.expect(backend.objectExists(oid));
    
    // Read
    const retrieved = try backend.getObject(oid);
    defer allocator.free(retrieved);
    try testing.expectEqualStrings(content, retrieved);
    
    // Update
    const updated_content = "Updated content";
    try backend.putObject(oid, updated_content);
    
    const updated_retrieved = try backend.getObject(oid);
    defer allocator.free(updated_retrieved);
    try testing.expectEqualStrings(updated_content, updated_retrieved);
    
    // Delete
    try backend.deleteObject(oid);
    try testing.expect(!backend.objectExists(oid));
    try testing.expectError(error.ObjectNotFound, backend.getObject(oid));
}

test "memory backend handles non-existent objects gracefully" {
    const allocator = testing.allocator;
    
    var backend = try MemoryBackend.init(allocator, .{
        .max_size_bytes = 1024,
    });
    defer backend.deinit();
    
    const non_existent_oid = "non_existent";
    
    try testing.expect(!backend.objectExists(non_existent_oid));
    try testing.expectError(error.ObjectNotFound, backend.getObject(non_existent_oid));
    try testing.expectError(error.ObjectNotFound, backend.deleteObject(non_existent_oid));
    try testing.expectError(error.ObjectNotFound, backend.getObjectSize(non_existent_oid));
}

test "memory backend LRU eviction works correctly" {
    const allocator = testing.allocator;
    
    var backend = try MemoryBackend.init(allocator, .{
        .max_size_bytes = 20, // Room for about 4 objects of 5 chars each
        .eviction_policy = .lru,
    });
    defer backend.deinit();
    
    // Add objects
    try backend.putObject("oid1", "data1");
    try backend.putObject("oid2", "data2");
    try backend.putObject("oid3", "data3");
    try backend.putObject("oid4", "data4");
    
    // Access oid1 to make it recently used
    const accessed_data = try backend.getObject("oid1");
    defer allocator.free(accessed_data);
    
    // Add another object that should evict the least recently used (probably oid2)
    try backend.putObject("oid5", "data5");
    
    // oid1 should still exist (was recently accessed)
    try testing.expect(backend.objectExists("oid1"));
    
    // oid5 should exist (just added)
    try testing.expect(backend.objectExists("oid5"));
}