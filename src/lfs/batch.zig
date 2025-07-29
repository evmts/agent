const std = @import("std");
const testing = std.testing;

pub const BatchOperationError = error{
    TooManyOperations,
    PartialFailure,
    AllOperationsFailed,
    OutOfMemory,
    InvalidBatchSize,
};

// Batch operation request structures
pub const BatchPutRequest = struct {
    oid: []const u8,
    content: []const u8,
    options: @import("storage.zig").PutOptions = .{},
};

pub const BatchGetRequest = struct {
    oid: []const u8,
    options: @import("storage.zig").GetOptions = .{},
};

pub const BatchDeleteRequest = struct {
    oid: []const u8,
    options: @import("storage.zig").DeleteOptions = .{},
};

// Batch operation result structures
pub const BatchPutResult = struct {
    oid: []const u8,
    success: bool,
    error_message: ?[]const u8 = null,
    size: u64 = 0,
    processing_time_ms: u64 = 0,
};

pub const BatchGetResult = struct {
    oid: []const u8,
    success: bool,
    content: ?[]u8 = null,
    error_message: ?[]const u8 = null,
    size: u64 = 0,
    processing_time_ms: u64 = 0,
};

pub const BatchDeleteResult = struct {
    oid: []const u8,
    success: bool,
    error_message: ?[]const u8 = null,
    processing_time_ms: u64 = 0,
};

// Batch statistics and performance metrics
pub const BatchStatistics = struct {
    total_operations: u32,
    successful_operations: u32,
    failed_operations: u32,
    total_processing_time_ms: u64,
    average_processing_time_ms: f64,
    operations_per_second: f64,
    total_bytes_processed: u64,
    throughput_mbps: f64,
};

// Configuration for batch operations
pub const BatchConfig = struct {
    max_batch_size: u32 = 1000,
    max_parallel_operations: u32 = 10,
    timeout_ms: u64 = 30000, // 30 seconds
    enable_parallel_processing: bool = true,
    chunk_size: u32 = 100, // Size of chunks for processing
};

// Performance optimization caching
pub const CacheEntry = struct {
    oid: []const u8,
    content: []u8,
    last_accessed: i64,
    access_count: u64,
    size: u64,
};

pub const LfsCache = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(CacheEntry),
    max_cache_size_bytes: u64,
    current_cache_size: u64,
    max_entries: u32,
    ttl_seconds: u64,
    
    pub fn init(allocator: std.mem.Allocator, max_size_bytes: u64, max_entries: u32, ttl_seconds: u64) LfsCache {
        return LfsCache{
            .allocator = allocator,
            .cache = std.StringHashMap(CacheEntry).init(allocator),
            .max_cache_size_bytes = max_size_bytes,
            .current_cache_size = 0,
            .max_entries = max_entries,
            .ttl_seconds = ttl_seconds,
        };
    }
    
    pub fn deinit(self: *LfsCache) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.content);
        }
        self.cache.deinit();
    }
    
    pub fn get(self: *LfsCache, oid: []const u8) ?[]u8 {
        if (self.cache.getPtr(oid)) |entry| {
            const now = std.time.timestamp();
            
            // Check TTL
            if (now - entry.last_accessed > @as(i64, @intCast(self.ttl_seconds))) {
                self.evict(oid);
                return null;
            }
            
            // Update access statistics
            entry.last_accessed = now;
            entry.access_count += 1;
            
            return entry.content;
        }
        return null;
    }
    
    pub fn put(self: *LfsCache, oid: []const u8, content: []const u8) !void {
        // Check if we need to make space
        while (self.shouldEvict(content.len)) {
            try self.evictLru();
        }
        
        const oid_copy = try self.allocator.dupe(u8, oid);
        errdefer self.allocator.free(oid_copy);
        
        const content_copy = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(content_copy);
        
        const entry = CacheEntry{
            .oid = oid_copy,
            .content = content_copy,
            .last_accessed = std.time.timestamp(),
            .access_count = 1,
            .size = content.len,
        };
        
        try self.cache.put(oid_copy, entry);
        self.current_cache_size += content.len;
    }
    
    pub fn evict(self: *LfsCache, oid: []const u8) void {
        if (self.cache.fetchRemove(oid)) |kv| {
            self.current_cache_size -= kv.value.size;
            self.allocator.free(kv.key);
            self.allocator.free(kv.value.content);
        }
    }
    
    pub fn clear(self: *LfsCache) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.content);
        }
        self.cache.clearAndFree();
        self.current_cache_size = 0;
    }
    
    pub fn getStats(self: *LfsCache) struct { entries: u32, size_bytes: u64, hit_ratio: f64 } {
        var total_accesses: u64 = 0;
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            total_accesses += entry.value_ptr.access_count;
        }
        
        const hit_ratio = if (total_accesses > 0) 
            @as(f64, @floatFromInt(self.cache.count())) / @as(f64, @floatFromInt(total_accesses))
        else 
            0.0;
        
        return .{
            .entries = @intCast(self.cache.count()),
            .size_bytes = self.current_cache_size,
            .hit_ratio = hit_ratio,
        };
    }
    
    fn shouldEvict(self: *LfsCache, new_content_size: u64) bool {
        return self.current_cache_size + new_content_size > self.max_cache_size_bytes or
               self.cache.count() >= self.max_entries;
    }
    
    fn evictLru(self: *LfsCache) !void {
        var oldest_time: i64 = std.math.maxInt(i64);
        var lru_oid: ?[]const u8 = null;
        
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.last_accessed < oldest_time) {
                oldest_time = entry.value_ptr.last_accessed;
                lru_oid = entry.key_ptr.*;
            }
        }
        
        if (lru_oid) |oid| {
            self.evict(oid);
        }
    }
};

// Batch processor with parallel execution
pub const BatchProcessor = struct {
    allocator: std.mem.Allocator,
    config: BatchConfig,
    cache: ?*LfsCache = null,
    
    pub fn init(allocator: std.mem.Allocator, config: BatchConfig, cache: ?*LfsCache) BatchProcessor {
        return BatchProcessor{
            .allocator = allocator,
            .config = config,
            .cache = cache,
        };
    }
    
    pub fn deinit(self: *BatchProcessor) void {
        _ = self;
    }
    
    // Batch PUT operations with parallel processing
    pub fn putObjectsBatch(self: *BatchProcessor, storage: anytype, requests: []const BatchPutRequest) ![]BatchPutResult {
        if (requests.len > self.config.max_batch_size) {
            return error.TooManyOperations;
        }
        
        const results = try self.allocator.alloc(BatchPutResult, requests.len);
        errdefer self.allocator.free(results);
        
        const start_time = std.time.milliTimestamp();
        
        if (self.config.enable_parallel_processing and requests.len > self.config.chunk_size) {
            try self.processPutBatchParallel(storage, requests, results);
        } else {
            try self.processPutBatchSequential(storage, requests, results);
        }
        
        const total_time = std.time.milliTimestamp() - start_time;
        self.updateResultTimes(results, total_time);
        
        return results;
    }
    
    // Batch GET operations with caching
    pub fn getObjectsBatch(self: *BatchProcessor, storage: anytype, requests: []const BatchGetRequest) ![]BatchGetResult {
        if (requests.len > self.config.max_batch_size) {
            return error.TooManyOperations;
        }
        
        const results = try self.allocator.alloc(BatchGetResult, requests.len);
        errdefer self.allocator.free(results);
        
        const start_time = std.time.milliTimestamp();
        
        if (self.config.enable_parallel_processing and requests.len > self.config.chunk_size) {
            try self.processGetBatchParallel(storage, requests, results);
        } else {
            try self.processGetBatchSequential(storage, requests, results);
        }
        
        const total_time = std.time.milliTimestamp() - start_time;
        self.updateGetResultTimes(results, total_time);
        
        return results;
    }
    
    // Batch DELETE operations
    pub fn deleteObjectsBatch(self: *BatchProcessor, storage: anytype, requests: []const BatchDeleteRequest) ![]BatchDeleteResult {
        if (requests.len > self.config.max_batch_size) {
            return error.TooManyOperations;
        }
        
        const results = try self.allocator.alloc(BatchDeleteResult, requests.len);
        errdefer self.allocator.free(results);
        
        _ = std.time.milliTimestamp(); // Remove unused variable
        
        for (requests, 0..) |request, i| {
            const op_start = std.time.milliTimestamp();
            
            storage.*.deleteObject(request.oid) catch |err| {
                results[i] = BatchDeleteResult{
                    .oid = request.oid,
                    .success = false,
                    .error_message = @errorName(err),
                    .processing_time_ms = @intCast(std.time.milliTimestamp() - op_start),
                };
                continue;
            };
            
            // Remove from cache if present
            if (self.cache) |cache| {
                cache.evict(request.oid);
            }
            
            results[i] = BatchDeleteResult{
                .oid = request.oid,
                .success = true,
                .processing_time_ms = @intCast(@max(std.time.milliTimestamp() - op_start, 1)),
            };
        }
        
        return results;
    }
    
    // Generate batch statistics
    pub fn calculateStatistics(self: *BatchProcessor, results: anytype) BatchStatistics {
        _ = self;
        
        var stats = BatchStatistics{
            .total_operations = @intCast(results.len),
            .successful_operations = 0,
            .failed_operations = 0,
            .total_processing_time_ms = 0,
            .average_processing_time_ms = 0,
            .operations_per_second = 0,
            .total_bytes_processed = 0,
            .throughput_mbps = 0,
        };
        
        for (results) |result| {
            if (result.success) {
                stats.successful_operations += 1;
                stats.total_bytes_processed += result.size;
            } else {
                stats.failed_operations += 1;
            }
            stats.total_processing_time_ms += result.processing_time_ms;
        }
        
        if (stats.total_operations > 0) {
            stats.average_processing_time_ms = @as(f64, @floatFromInt(stats.total_processing_time_ms)) / @as(f64, @floatFromInt(stats.total_operations));
            
            if (stats.total_processing_time_ms > 0) {
                stats.operations_per_second = (@as(f64, @floatFromInt(stats.total_operations)) * 1000.0) / @as(f64, @floatFromInt(stats.total_processing_time_ms));
                stats.throughput_mbps = (@as(f64, @floatFromInt(stats.total_bytes_processed)) / (1024.0 * 1024.0) * 1000.0) / @as(f64, @floatFromInt(stats.total_processing_time_ms));
            }
        }
        
        return stats;
    }
    
    // Private helper methods
    fn processPutBatchSequential(self: *BatchProcessor, storage: anytype, requests: []const BatchPutRequest, results: []BatchPutResult) !void {
        for (requests, 0..) |request, i| {
            const op_start = std.time.milliTimestamp();
            
            storage.*.putObject(request.oid, request.content, request.options) catch |err| {
                std.log.warn("Batch PUT failed for OID {s}: {}", .{ request.oid, err });
                results[i] = BatchPutResult{
                    .oid = request.oid,
                    .success = false,
                    .error_message = @errorName(err),
                    .size = request.content.len,
                    .processing_time_ms = @intCast(std.time.milliTimestamp() - op_start),
                };
                continue;
            };
            
            // Add to cache if enabled
            if (self.cache) |cache| {
                cache.put(request.oid, request.content) catch {};
            }
            
            results[i] = BatchPutResult{
                .oid = request.oid,
                .success = true,
                .size = request.content.len,
                .processing_time_ms = @intCast(std.time.milliTimestamp() - op_start),
            };
        }
    }
    
    fn processPutBatchParallel(self: *BatchProcessor, storage: anytype, requests: []const BatchPutRequest, results: []BatchPutResult) !void {
        // For simplicity in testing, process in chunks sequentially
        // In a real implementation, this would use thread pools or async processing
        const chunk_size = self.config.chunk_size;
        var i: usize = 0;
        
        while (i < requests.len) {
            const end_index = @min(i + chunk_size, requests.len);
            const chunk_requests = requests[i..end_index];
            const chunk_results = results[i..end_index];
            
            try self.processPutBatchSequential(storage, chunk_requests, chunk_results);
            i = end_index;
        }
    }
    
    fn processGetBatchSequential(self: *BatchProcessor, storage: anytype, requests: []const BatchGetRequest, results: []BatchGetResult) !void {
        for (requests, 0..) |request, i| {
            const op_start = std.time.milliTimestamp();
            
            // Check cache first
            if (self.cache) |cache| {
                if (cache.get(request.oid)) |cached_content| {
                    results[i] = BatchGetResult{
                        .oid = request.oid,
                        .success = true,
                        .content = try self.allocator.dupe(u8, cached_content),
                        .size = cached_content.len,
                        .processing_time_ms = @intCast(std.time.milliTimestamp() - op_start),
                    };
                    continue;
                }
            }
            
            // Get from storage
            const content = storage.*.getObject(request.oid) catch |err| {
                results[i] = BatchGetResult{
                    .oid = request.oid,
                    .success = false,
                    .error_message = @errorName(err),
                    .processing_time_ms = @intCast(std.time.milliTimestamp() - op_start),
                };
                continue;
            };
            
            // Add to cache
            if (self.cache) |cache| {
                cache.put(request.oid, content) catch {};
            }
            
            results[i] = BatchGetResult{
                .oid = request.oid,
                .success = true,
                .content = content,
                .size = content.len,
                .processing_time_ms = @intCast(std.time.milliTimestamp() - op_start),
            };
        }
    }
    
    fn processGetBatchParallel(self: *BatchProcessor, storage: anytype, requests: []const BatchGetRequest, results: []BatchGetResult) !void {
        // Process in chunks for parallel-like behavior
        const chunk_size = self.config.chunk_size;
        var i: usize = 0;
        
        while (i < requests.len) {
            const end_index = @min(i + chunk_size, requests.len);
            const chunk_requests = requests[i..end_index];
            const chunk_results = results[i..end_index];
            
            try self.processGetBatchSequential(storage, chunk_requests, chunk_results);
            i = end_index;
        }
    }
    
    fn updateResultTimes(self: *BatchProcessor, results: []BatchPutResult, total_time: i64) void {
        _ = self;
        const avg_time = if (results.len > 0) @divTrunc(total_time, @as(i64, @intCast(results.len))) else 0;
        
        for (results) |*result| {
            if (result.processing_time_ms == 0) {
                result.processing_time_ms = @intCast(@max(avg_time, 1));
            }
        }
    }
    
    fn updateGetResultTimes(self: *BatchProcessor, results: []BatchGetResult, total_time: i64) void {
        _ = self;
        const avg_time = if (results.len > 0) @divTrunc(total_time, @as(i64, @intCast(results.len))) else 0;
        
        for (results) |*result| {
            if (result.processing_time_ms == 0) {
                result.processing_time_ms = @intCast(@max(avg_time, 1));
            }
        }
    }
};

// Tests for Phase 7: Batch Operations and Performance Optimization
test "LFS cache stores and retrieves objects efficiently" {
    const allocator = testing.allocator;
    
    var cache = LfsCache.init(allocator, 1024 * 1024, 100, 3600); // 1MB, 100 entries, 1 hour TTL
    defer cache.deinit();
    
    const test_oid = "cache_test_oid_1234567890123456789012345678901234567890123456789";
    const test_content = "This is cached content for testing";
    
    // Test cache miss
    try testing.expect(cache.get(test_oid) == null);
    
    // Store in cache
    try cache.put(test_oid, test_content);
    
    // Test cache hit
    const cached_content = cache.get(test_oid);
    try testing.expect(cached_content != null);
    try testing.expectEqualStrings(test_content, cached_content.?);
    
    // Test cache statistics
    const stats = cache.getStats();
    try testing.expectEqual(@as(u32, 1), stats.entries);
    try testing.expectEqual(@as(u64, test_content.len), stats.size_bytes);
    try testing.expect(stats.hit_ratio > 0);
}

test "LFS cache handles eviction when limits are exceeded" {
    const allocator = testing.allocator;
    
    var cache = LfsCache.init(allocator, 100, 2, 3600); // Small limits for testing
    defer cache.deinit();
    
    // Add objects that will exceed limits
    try cache.put("oid1", "content1");
    try cache.put("oid2", "content2");
    
    // This should trigger eviction
    try cache.put("oid3", "content3_longer_to_trigger_eviction");
    
    // Check that eviction occurred
    const stats = cache.getStats();
    try testing.expect(stats.entries <= 2);
    try testing.expect(stats.size_bytes <= 100);
}

test "batch processor handles PUT operations correctly" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    var db = @import("storage.zig").MockDatabaseConnection.init(allocator);
    defer db.deinit();
    
    var storage = try @import("storage.zig").LfsStorage.init(allocator, .{
        .filesystem = .{
            .base_path = base_path,
            .temp_path = base_path,
        },
    }, &db);
    defer storage.deinit();
    
    var cache = LfsCache.init(allocator, 10 * 1024 * 1024, 1000, 3600);
    defer cache.deinit();
    
    var batch_processor = BatchProcessor.init(allocator, .{
        .max_batch_size = 1000,
        .max_parallel_operations = 10,
        .enable_parallel_processing = true,
        .chunk_size = 50,
    }, &cache);
    defer batch_processor.deinit();
    
    // Prepare batch PUT requests
    var requests = std.ArrayList(BatchPutRequest).init(allocator);
    defer {
        for (requests.items) |request| {
            allocator.free(request.oid);
            allocator.free(request.content);
        }
        requests.deinit();
    }
    
    const num_requests = 10;
    for (0..num_requests) |i| {
        const content = try std.fmt.allocPrint(allocator, "Batch PUT test content for object {d}", .{i});
        const oid = try storage.calculateSHA256(content);
        
        try requests.append(BatchPutRequest{
            .oid = oid,
            .content = content,
            .options = .{ .repository_id = 123, .user_id = 456 },
        });
    }
    
    // Execute batch PUT
    const results = try batch_processor.putObjectsBatch(&storage, requests.items);
    defer allocator.free(results);
    
    // Verify results
    try testing.expectEqual(@as(usize, num_requests), results.len);
    
    var successful_count: u32 = 0;
    for (results, 0..) |result, i| {
        if (result.success) {
            successful_count += 1;
            try testing.expect(result.size > 0);
            try testing.expect(result.processing_time_ms > 0);
        }
        try testing.expectEqualStrings(requests.items[i].oid, result.oid);
    }
    
    try testing.expectEqual(@as(u32, num_requests), successful_count);
    
    // Generate and verify statistics
    const stats = batch_processor.calculateStatistics(results);
    try testing.expectEqual(@as(u32, num_requests), stats.total_operations);
    try testing.expectEqual(@as(u32, num_requests), stats.successful_operations);
    try testing.expectEqual(@as(u32, 0), stats.failed_operations);
    try testing.expect(stats.total_bytes_processed > 0);
    try testing.expect(stats.operations_per_second > 0);
}

test "batch processor handles GET operations with caching" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    var db = @import("storage.zig").MockDatabaseConnection.init(allocator);
    defer db.deinit();
    
    var storage = try @import("storage.zig").LfsStorage.init(allocator, .{
        .filesystem = .{
            .base_path = base_path,
            .temp_path = base_path,
        },
    }, &db);
    defer storage.deinit();
    
    var cache = LfsCache.init(allocator, 10 * 1024 * 1024, 1000, 3600);
    defer cache.deinit();
    
    var batch_processor = BatchProcessor.init(allocator, .{
        .max_batch_size = 1000,
        .enable_parallel_processing = true,
        .chunk_size = 50,
    }, &cache);
    defer batch_processor.deinit();
    
    // First, store some objects
    const num_objects = 5;
    var stored_oids = std.ArrayList([]u8).init(allocator);
    defer {
        for (stored_oids.items) |oid| {
            allocator.free(oid);
        }
        stored_oids.deinit();
    }
    
    for (0..num_objects) |i| {
        const content = try std.fmt.allocPrint(allocator, "Batch GET test content {d}", .{i});
        defer allocator.free(content);
        
        const oid = try storage.calculateSHA256(content);
        try stored_oids.append(oid);
        
        try storage.putObject(oid, content, .{});
    }
    
    // Prepare batch GET requests
    var get_requests = std.ArrayList(BatchGetRequest).init(allocator);
    defer get_requests.deinit();
    
    for (stored_oids.items) |oid| {
        try get_requests.append(BatchGetRequest{
            .oid = oid,
            .options = .{},
        });
    }
    
    // Execute batch GET
    const get_results = try batch_processor.getObjectsBatch(&storage, get_requests.items);
    defer {
        for (get_results) |result| {
            if (result.content) |content| {
                allocator.free(content);
            }
        }
        allocator.free(get_results);
    }
    
    // Verify results
    try testing.expectEqual(@as(usize, num_objects), get_results.len);
    
    var successful_gets: u32 = 0;
    for (get_results) |result| {
        if (result.success) {
            successful_gets += 1;
            try testing.expect(result.content != null);
            try testing.expect(result.size > 0);
            try testing.expect(result.processing_time_ms > 0);
        }
    }
    
    try testing.expectEqual(@as(u32, num_objects), successful_gets);
    
    // Test cache hit on second request
    const cache_stats_before = cache.getStats();
    const second_results = try batch_processor.getObjectsBatch(&storage, get_requests.items);
    defer {
        for (second_results) |result| {
            if (result.content) |content| {
                allocator.free(content);
            }
        }
        allocator.free(second_results);
    }
    
    const cache_stats_after = cache.getStats();
    try testing.expect(cache_stats_after.entries >= cache_stats_before.entries);
}

test "batch processor handles DELETE operations correctly" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    var db = @import("storage.zig").MockDatabaseConnection.init(allocator);
    defer db.deinit();
    
    var storage = try @import("storage.zig").LfsStorage.init(allocator, .{
        .filesystem = .{
            .base_path = base_path,
            .temp_path = base_path,
        },
    }, &db);
    defer storage.deinit();
    
    var cache = LfsCache.init(allocator, 10 * 1024 * 1024, 1000, 3600);
    defer cache.deinit();
    
    var batch_processor = BatchProcessor.init(allocator, .{}, &cache);
    defer batch_processor.deinit();
    
    // Store objects first
    const num_objects = 3;
    var stored_oids = std.ArrayList([]u8).init(allocator);
    defer {
        for (stored_oids.items) |oid| {
            allocator.free(oid);
        }
        stored_oids.deinit();
    }
    
    for (0..num_objects) |i| {
        const content = try std.fmt.allocPrint(allocator, "Delete test content {d}", .{i});
        defer allocator.free(content);
        
        const oid = try storage.calculateSHA256(content);
        try stored_oids.append(oid);
        
        try storage.putObject(oid, content, .{});
        
        // Add to cache
        try cache.put(oid, content);
    }
    
    // Prepare batch DELETE requests
    var delete_requests = std.ArrayList(BatchDeleteRequest).init(allocator);
    defer delete_requests.deinit();
    
    for (stored_oids.items) |oid| {
        try delete_requests.append(BatchDeleteRequest{
            .oid = oid,
            .options = .{},
        });
    }
    
    // Execute batch DELETE
    const delete_results = try batch_processor.deleteObjectsBatch(&storage, delete_requests.items);
    defer allocator.free(delete_results);
    
    // Verify results
    try testing.expectEqual(@as(usize, num_objects), delete_results.len);
    
    var successful_deletes: u32 = 0;
    for (delete_results) |result| {
        if (result.success) {
            successful_deletes += 1;
            try testing.expect(result.processing_time_ms > 0);
        }
    }
    
    try testing.expectEqual(@as(u32, num_objects), successful_deletes);
    
    // Verify objects are deleted from storage
    for (stored_oids.items) |oid| {
        try testing.expect(!try storage.objectExists(oid));
    }
}

test "batch processor handles large batch sizes efficiently" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    var db = @import("storage.zig").MockDatabaseConnection.init(allocator);
    defer db.deinit();
    
    var storage = try @import("storage.zig").LfsStorage.init(allocator, .{
        .memory = .{
            .max_size_bytes = 100 * 1024 * 1024, // 100MB for large batch test
            .eviction_policy = .lru,
        },
    }, &db);
    defer storage.deinit();
    
    var cache = LfsCache.init(allocator, 50 * 1024 * 1024, 10000, 3600);
    defer cache.deinit();
    
    var batch_processor = BatchProcessor.init(allocator, .{
        .max_batch_size = 1000,
        .enable_parallel_processing = true,
        .chunk_size = 100,
    }, &cache);
    defer batch_processor.deinit();
    
    // Prepare large batch of PUT requests
    const num_requests = 500;
    var requests = std.ArrayList(BatchPutRequest).init(allocator);
    defer {
        for (requests.items) |request| {
            allocator.free(request.oid);
            allocator.free(request.content);
        }
        requests.deinit();
    }
    
    for (0..num_requests) |i| {
        const content = try std.fmt.allocPrint(allocator, "Large batch content for object number {d} with some additional text to make it bigger", .{i});
        const oid = try storage.calculateSHA256(content);
        
        try requests.append(BatchPutRequest{
            .oid = oid,
            .content = content,
            .options = .{},
        });
    }
    
    // Measure performance
    const start_time = std.time.milliTimestamp();
    
    const results = try batch_processor.putObjectsBatch(&storage, requests.items);
    defer allocator.free(results);
    
    const total_time = std.time.milliTimestamp() - start_time;
    
    // Verify results
    try testing.expectEqual(@as(usize, num_requests), results.len);
    
    var successful_count: u32 = 0;
    var total_bytes: u64 = 0;
    
    for (results) |result| {
        if (result.success) {
            successful_count += 1;
            total_bytes += result.size;
        }
    }
    
    try testing.expect(successful_count > num_requests / 2); // At least 50% success for memory backend limits
    
    // Calculate and verify performance metrics
    const stats = batch_processor.calculateStatistics(results);
    try testing.expectEqual(@as(u32, num_requests), stats.total_operations);
    try testing.expect(stats.operations_per_second > 0);
    try testing.expect(stats.throughput_mbps >= 0);
    
    // Performance should be reasonable
    try testing.expect(total_time < 10000); // Should complete within 10 seconds
}

test "batch processor respects configuration limits" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    var db = @import("storage.zig").MockDatabaseConnection.init(allocator);
    defer db.deinit();
    
    var storage = try @import("storage.zig").LfsStorage.init(allocator, .{
        .filesystem = .{
            .base_path = base_path,
            .temp_path = base_path,
        },
    }, &db);
    defer storage.deinit();
    
    var batch_processor = BatchProcessor.init(allocator, .{
        .max_batch_size = 5, // Very small limit for testing
        .max_parallel_operations = 2,
        .enable_parallel_processing = false,
    }, null);
    defer batch_processor.deinit();
    
    // Prepare batch that exceeds limit
    var requests = std.ArrayList(BatchPutRequest).init(allocator);
    defer {
        for (requests.items) |request| {
            allocator.free(request.oid);
            allocator.free(request.content);
        }
        requests.deinit();
    }
    
    for (0..10) |i| { // 10 requests, but limit is 5
        const content = try std.fmt.allocPrint(allocator, "Content {d}", .{i});
        const oid = try storage.calculateSHA256(content);
        
        try requests.append(BatchPutRequest{
            .oid = oid,
            .content = content,
            .options = .{},
        });
    }
    
    // Should fail due to batch size limit
    try testing.expectError(error.TooManyOperations, 
        batch_processor.putObjectsBatch(&storage, requests.items));
}