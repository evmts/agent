const std = @import("std");
const testing = std.testing;

pub const LfsMetadataError = error{
    ObjectNotFound,
    DuplicateObject,
    DatabaseError,
    InvalidMetadata,
    OutOfMemory,
};

// Enhanced LFS metadata structure for enterprise features
pub const EnhancedLfsMetadata = struct {
    oid: []const u8,
    size: u64,
    checksum: []const u8,
    created_at: i64,
    last_accessed: i64,
    access_count: u64 = 0,
    content_type: ?[]const u8 = null,
    storage_tier: StorageTier = .hot,
    compression_algorithm: CompressionAlgorithm = .none,
    encrypted: bool = false,
    encryption_key_id: ?[]const u8 = null,
    repository_id: ?u32 = null,
    user_id: ?u32 = null,
    organization_id: ?u32 = null,
    duplicate_references: u32 = 0,
    malware_scan_result: MalwareScanResult = .scan_not_performed,
    storage_backend: []const u8 = "filesystem",
};

pub const StorageTier = enum {
    hot,      // Frequently accessed
    warm,     // Occasionally accessed  
    cold,     // Rarely accessed
    archival, // Long-term storage
};

pub const CompressionAlgorithm = enum {
    none,
    gzip,
    lz4,
    zstd,
};

pub const MalwareScanResult = enum {
    clean,
    infected,
    suspicious,
    scan_failed,
    scan_not_performed,
};

// Search and query structures
pub const MetadataSearchQuery = struct {
    repository_id: ?u32 = null,
    user_id: ?u32 = null,
    organization_id: ?u32 = null,
    storage_tier: ?StorageTier = null,
    min_size: ?u64 = null,
    max_size: ?u64 = null,
    created_after: ?i64 = null,
    created_before: ?i64 = null,
    content_type: ?[]const u8 = null,
    encrypted: ?bool = null,
    limit: u32 = 100,
    offset: u32 = 0,
};

pub const MetadataSearchResult = struct {
    objects: []EnhancedLfsMetadata,
    total_count: u32,
    has_more: bool,
};

// Usage analytics and statistics
pub const StorageUsageStats = struct {
    total_objects: u64,
    total_size_bytes: u64,
    objects_by_tier: std.EnumMap(StorageTier, u64),
    size_by_tier: std.EnumMap(StorageTier, u64),
    objects_by_repository: std.HashMap(u32, u64, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    size_by_repository: std.HashMap(u32, u64, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    duplicate_space_saved: u64,
    encrypted_objects: u64,
    compressed_objects: u64,
};

// Database connection interface for metadata operations
pub const LfsMetadataManager = struct {
    allocator: std.mem.Allocator,
    db_pool: ?*anyopaque = null, // Would be *pg.Pool in real implementation
    
    // For testing - in-memory storage when no database available
    memory_store: ?std.StringHashMap(EnhancedLfsMetadata) = null,
    
    pub fn init(allocator: std.mem.Allocator, db_pool: ?*anyopaque) !LfsMetadataManager {
        var memory_store: ?std.StringHashMap(EnhancedLfsMetadata) = null;
        
        // If no database pool provided, use in-memory storage for testing
        if (db_pool == null) {
            memory_store = std.StringHashMap(EnhancedLfsMetadata).init(allocator);
        }
        
        return LfsMetadataManager{
            .allocator = allocator,
            .db_pool = db_pool,
            .memory_store = memory_store,
        };
    }
    
    pub fn deinit(self: *LfsMetadataManager) void {
        if (self.memory_store) |*store| {
            var iterator = store.iterator();
            while (iterator.next()) |entry| {
                self.deallocateMetadata(entry.value_ptr);
                self.allocator.free(entry.key_ptr.*);
            }
            store.deinit();
        }
    }
    
    // Core metadata operations
    pub fn storeMetadata(self: *LfsMetadataManager, metadata: EnhancedLfsMetadata) !void {
        if (self.db_pool) |pool| {
            try self.storeMetadataDatabase(pool, metadata);
        } else if (self.memory_store) |*store| {
            try self.storeMetadataMemory(store, metadata);
        } else {
            return error.DatabaseError;
        }
    }
    
    pub fn getMetadata(self: *LfsMetadataManager, oid: []const u8) !?EnhancedLfsMetadata {
        if (self.db_pool) |pool| {
            return try self.getMetadataDatabase(pool, oid);
        } else if (self.memory_store) |*store| {
            return self.getMetadataMemory(store, oid);
        } else {
            return error.DatabaseError;
        }
    }
    
    pub fn updateMetadata(self: *LfsMetadataManager, oid: []const u8, metadata: EnhancedLfsMetadata) !void {
        if (self.db_pool) |pool| {
            try self.updateMetadataDatabase(pool, oid, metadata);
        } else if (self.memory_store) |*store| {
            try self.updateMetadataMemory(store, oid, metadata);
        } else {
            return error.DatabaseError;
        }
    }
    
    pub fn deleteMetadata(self: *LfsMetadataManager, oid: []const u8) !void {
        if (self.db_pool) |pool| {
            try self.deleteMetadataDatabase(pool, oid);
        } else if (self.memory_store) |*store| {
            try self.deleteMetadataMemory(store, oid);
        } else {
            return error.DatabaseError;
        }
    }
    
    // Enhanced search and indexing operations
    pub fn searchMetadata(self: *LfsMetadataManager, query: MetadataSearchQuery) !MetadataSearchResult {
        if (self.db_pool) |pool| {
            return try self.searchMetadataDatabase(pool, query);
        } else if (self.memory_store) |*store| {
            return try self.searchMetadataMemory(store, query);
        } else {
            return error.DatabaseError;
        }
    }
    
    pub fn getObjectsByRepository(self: *LfsMetadataManager, repository_id: u32, limit: u32, offset: u32) ![]EnhancedLfsMetadata {
        const query = MetadataSearchQuery{
            .repository_id = repository_id,
            .limit = limit,
            .offset = offset,
        };
        const result = try self.searchMetadata(query);
        return result.objects;
    }
    
    pub fn getObjectsByUser(self: *LfsMetadataManager, user_id: u32, limit: u32, offset: u32) ![]EnhancedLfsMetadata {
        const query = MetadataSearchQuery{
            .user_id = user_id,
            .limit = limit,
            .offset = offset,
        };
        const result = try self.searchMetadata(query);
        return result.objects;
    }
    
    pub fn getObjectsByStorageTier(self: *LfsMetadataManager, tier: StorageTier, limit: u32, offset: u32) ![]EnhancedLfsMetadata {
        const query = MetadataSearchQuery{
            .storage_tier = tier,
            .limit = limit,
            .offset = offset,
        };
        const result = try self.searchMetadata(query);
        return result.objects;
    }
    
    // Analytics and usage statistics
    pub fn getStorageUsageStats(self: *LfsMetadataManager) !StorageUsageStats {
        if (self.db_pool) |pool| {
            return try self.getStorageUsageStatsDatabase(pool);
        } else if (self.memory_store) |*store| {
            return try self.getStorageUsageStatsMemory(store);
        } else {
            return error.DatabaseError;
        }
    }
    
    pub fn getRepositoryUsage(self: *LfsMetadataManager, repository_id: u32) !struct { object_count: u64, total_size: u64 } {
        const query = MetadataSearchQuery{
            .repository_id = repository_id,
            .limit = std.math.maxInt(u32),
        };
        const result = try self.searchMetadata(query);
        
        var total_size: u64 = 0;
        for (result.objects) |metadata| {
            total_size += metadata.size;
        }
        
        return .{
            .object_count = result.objects.len,
            .total_size = total_size,
        };
    }
    
    // Maintenance operations
    pub fn cleanupOrphanedMetadata(self: *LfsMetadataManager) !u32 {
        // In a real implementation, this would:
        // 1. Find metadata records without corresponding storage objects
        // 2. Remove orphaned records
        // 3. Return count of cleaned up records
        _ = self;
        return 0; // Placeholder for testing
    }
    
    pub fn updateAccessStatistics(self: *LfsMetadataManager, oid: []const u8) !void {
        if (self.memory_store) |*store| {
            if (store.getPtr(oid)) |existing| {
                existing.last_accessed = std.time.timestamp();
                existing.access_count += 1;
            } else {
                return error.ObjectNotFound;
            }
        } else {
            // For database implementation, would update in-place
            var metadata = (try self.getMetadata(oid)) orelse return error.ObjectNotFound;
            metadata.last_accessed = std.time.timestamp();
            metadata.access_count += 1;
            try self.updateMetadata(oid, metadata);
        }
    }
    
    pub fn getDuplicateObjects(self: *LfsMetadataManager) ![][]const u8 {
        // In a real implementation, this would find objects with duplicate checksums
        _ = self;
        return &[_][]const u8{};
    }
    
    // Database implementation methods
    fn storeMetadataDatabase(self: *LfsMetadataManager, pool: *anyopaque, metadata: EnhancedLfsMetadata) !void {
        _ = self;
        _ = pool;
        _ = metadata;
        // TODO: Implement SQL INSERT for enhanced metadata
        // Would create SQL like:
        // INSERT INTO lfs_metadata (oid, size, checksum, created_at, ...) VALUES ($1, $2, $3, $4, ...)
    }
    
    fn getMetadataDatabase(self: *LfsMetadataManager, pool: *anyopaque, oid: []const u8) !?EnhancedLfsMetadata {
        _ = self;
        _ = pool;
        _ = oid;
        // TODO: Implement SQL SELECT for enhanced metadata
        return null;
    }
    
    fn updateMetadataDatabase(self: *LfsMetadataManager, pool: *anyopaque, oid: []const u8, metadata: EnhancedLfsMetadata) !void {
        _ = self;
        _ = pool;
        _ = oid;
        _ = metadata;
        // TODO: Implement SQL UPDATE for enhanced metadata
    }
    
    fn deleteMetadataDatabase(self: *LfsMetadataManager, pool: *anyopaque, oid: []const u8) !void {
        _ = self;
        _ = pool;
        _ = oid;
        // TODO: Implement SQL DELETE for enhanced metadata
    }
    
    fn searchMetadataDatabase(self: *LfsMetadataManager, pool: *anyopaque, query: MetadataSearchQuery) !MetadataSearchResult {
        _ = self;
        _ = pool;
        _ = query;
        // TODO: Implement SQL SELECT with WHERE clauses for complex queries
        return MetadataSearchResult{
            .objects = &[_]EnhancedLfsMetadata{},
            .total_count = 0,
            .has_more = false,
        };
    }
    
    fn getStorageUsageStatsDatabase(self: *LfsMetadataManager, pool: *anyopaque) !StorageUsageStats {
        _ = pool;
        // TODO: Implement SQL aggregation queries for usage statistics
        return StorageUsageStats{
            .total_objects = 0,
            .total_size_bytes = 0,
            .objects_by_tier = std.EnumMap(StorageTier, u64).init(.{}),
            .size_by_tier = std.EnumMap(StorageTier, u64).init(.{}),
            .objects_by_repository = std.HashMap(u32, u64, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(self.allocator),
            .size_by_repository = std.HashMap(u32, u64, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(self.allocator),
            .duplicate_space_saved = 0,
            .encrypted_objects = 0,
            .compressed_objects = 0,
        };
    }
    
    // Memory implementation methods (for testing)
    fn storeMetadataMemory(self: *LfsMetadataManager, store: *std.StringHashMap(EnhancedLfsMetadata), metadata: EnhancedLfsMetadata) !void {
        const oid_copy = try self.allocator.dupe(u8, metadata.oid);
        errdefer self.allocator.free(oid_copy);
        
        const metadata_copy = try self.allocateMetadata(metadata);
        errdefer self.deallocateMetadata(&metadata_copy);
        
        try store.put(oid_copy, metadata_copy);
    }
    
    fn getMetadataMemory(self: *LfsMetadataManager, store: *std.StringHashMap(EnhancedLfsMetadata), oid: []const u8) ?EnhancedLfsMetadata {
        _ = self;
        return store.get(oid);
    }
    
    fn updateMetadataMemory(self: *LfsMetadataManager, store: *std.StringHashMap(EnhancedLfsMetadata), oid: []const u8, metadata: EnhancedLfsMetadata) !void {
        if (store.getPtr(oid)) |existing| {
            // Free existing metadata
            self.deallocateMetadata(existing);
            // Allocate new metadata
            existing.* = try self.allocateMetadata(metadata);
        } else {
            return error.ObjectNotFound;
        }
    }
    
    fn deleteMetadataMemory(self: *LfsMetadataManager, store: *std.StringHashMap(EnhancedLfsMetadata), oid: []const u8) !void {
        const kv = store.fetchRemove(oid) orelse return error.ObjectNotFound;
        self.deallocateMetadata(&kv.value);
        self.allocator.free(kv.key);
    }
    
    fn searchMetadataMemory(self: *LfsMetadataManager, store: *std.StringHashMap(EnhancedLfsMetadata), query: MetadataSearchQuery) !MetadataSearchResult {
        var matching_objects = std.ArrayList(EnhancedLfsMetadata).init(self.allocator);
        defer matching_objects.deinit();
        
        var iterator = store.iterator();
        while (iterator.next()) |entry| {
            const metadata = entry.value_ptr.*;
            
            // Apply filters
            if (query.repository_id) |repo_id| {
                if (metadata.repository_id != repo_id) continue;
            }
            if (query.user_id) |user_id| {
                if (metadata.user_id != user_id) continue;
            }
            if (query.organization_id) |org_id| {
                if (metadata.organization_id != org_id) continue;
            }
            if (query.storage_tier) |tier| {
                if (metadata.storage_tier != tier) continue;
            }
            if (query.min_size) |min_size| {
                if (metadata.size < min_size) continue;
            }
            if (query.max_size) |max_size| {
                if (metadata.size > max_size) continue;
            }
            if (query.created_after) |after| {
                if (metadata.created_at <= after) continue;
            }
            if (query.created_before) |before| {
                if (metadata.created_at >= before) continue;
            }
            if (query.encrypted) |encrypted| {
                if (metadata.encrypted != encrypted) continue;
            }
            if (query.content_type) |content_type| {
                if (metadata.content_type == null or !std.mem.eql(u8, metadata.content_type.?, content_type)) continue;
            }
            
            try matching_objects.append(metadata);
        }
        
        // Apply pagination
        const total_count = @as(u32, @intCast(matching_objects.items.len));
        const start_index = @min(query.offset, total_count);
        const end_index = @min(start_index + query.limit, total_count);
        
        const result_slice = if (start_index < end_index) 
            matching_objects.items[start_index..end_index] 
        else 
            &[_]EnhancedLfsMetadata{};
        
        const result_objects = try self.allocator.dupe(EnhancedLfsMetadata, result_slice);
        
        return MetadataSearchResult{
            .objects = result_objects,
            .total_count = total_count,
            .has_more = end_index < total_count,
        };
    }
    
    fn getStorageUsageStatsMemory(self: *LfsMetadataManager, store: *std.StringHashMap(EnhancedLfsMetadata)) !StorageUsageStats {
        var stats = StorageUsageStats{
            .total_objects = 0,
            .total_size_bytes = 0,
            .objects_by_tier = std.EnumMap(StorageTier, u64).init(.{}),
            .size_by_tier = std.EnumMap(StorageTier, u64).init(.{}),
            .objects_by_repository = std.HashMap(u32, u64, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(self.allocator),
            .size_by_repository = std.HashMap(u32, u64, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(self.allocator),
            .duplicate_space_saved = 0,
            .encrypted_objects = 0,
            .compressed_objects = 0,
        };
        
        var iterator = store.iterator();
        while (iterator.next()) |entry| {
            const metadata = entry.value_ptr.*;
            
            stats.total_objects += 1;
            stats.total_size_bytes += metadata.size;
            
            // Track by tier
            const tier_objects = stats.objects_by_tier.get(metadata.storage_tier) orelse 0;
            const tier_size = stats.size_by_tier.get(metadata.storage_tier) orelse 0;
            stats.objects_by_tier.put(metadata.storage_tier, tier_objects + 1);
            stats.size_by_tier.put(metadata.storage_tier, tier_size + metadata.size);
            
            // Track by repository
            if (metadata.repository_id) |repo_id| {
                const repo_objects = stats.objects_by_repository.get(repo_id) orelse 0;
                const repo_size = stats.size_by_repository.get(repo_id) orelse 0;
                try stats.objects_by_repository.put(repo_id, repo_objects + 1);
                try stats.size_by_repository.put(repo_id, repo_size + metadata.size);
            }
            
            // Track encryption and compression
            if (metadata.encrypted) {
                stats.encrypted_objects += 1;
            }
            if (metadata.compression_algorithm != .none) {
                stats.compressed_objects += 1;
            }
            
            // Track deduplication savings
            if (metadata.duplicate_references > 0) {
                stats.duplicate_space_saved += metadata.size * metadata.duplicate_references;
            }
        }
        
        return stats;
    }
    
    // Memory management helpers
    fn allocateMetadata(self: *LfsMetadataManager, metadata: EnhancedLfsMetadata) !EnhancedLfsMetadata {
        var result = metadata;
        
        result.oid = try self.allocator.dupe(u8, metadata.oid);
        errdefer self.allocator.free(result.oid);
        
        result.checksum = try self.allocator.dupe(u8, metadata.checksum);
        errdefer self.allocator.free(result.checksum);
        
        if (metadata.content_type) |ct| {
            result.content_type = try self.allocator.dupe(u8, ct);
        }
        errdefer if (result.content_type) |ct| self.allocator.free(ct);
        
        if (metadata.encryption_key_id) |key_id| {
            result.encryption_key_id = try self.allocator.dupe(u8, key_id);
        }
        errdefer if (result.encryption_key_id) |key_id| self.allocator.free(key_id);
        
        result.storage_backend = try self.allocator.dupe(u8, metadata.storage_backend);
        errdefer self.allocator.free(result.storage_backend);
        
        return result;
    }
    
    fn deallocateMetadata(self: *LfsMetadataManager, metadata: *const EnhancedLfsMetadata) void {
        self.allocator.free(metadata.oid);
        self.allocator.free(metadata.checksum);
        if (metadata.content_type) |ct| {
            self.allocator.free(ct);
        }
        if (metadata.encryption_key_id) |key_id| {
            self.allocator.free(key_id);
        }
        self.allocator.free(metadata.storage_backend);
    }
};

// Tests for Phase 6: Metadata Management and Database Integration
test "stores and retrieves object metadata" {
    const allocator = testing.allocator;
    
    var metadata_manager = try LfsMetadataManager.init(allocator, null);
    defer metadata_manager.deinit();
    
    const test_metadata = EnhancedLfsMetadata{
        .oid = "abcdef1234567890123456789012345678901234567890123456789012345678",
        .size = 1024 * 1024, // 1MB
        .checksum = "sha256checksum1234567890123456789012345678901234567890123456789012345678",
        .created_at = std.time.timestamp(),
        .last_accessed = std.time.timestamp(),
        .access_count = 5,
        .content_type = "application/octet-stream",
        .storage_tier = .warm,
        .compression_algorithm = .gzip,
        .encrypted = true,
        .encryption_key_id = "key123",
        .repository_id = 456,
        .user_id = 789,
        .organization_id = 101112,
        .duplicate_references = 2,
        .malware_scan_result = .clean,
        .storage_backend = "s3",
    };
    
    // Store metadata
    try metadata_manager.storeMetadata(test_metadata);
    
    // Retrieve metadata
    const retrieved = (try metadata_manager.getMetadata(test_metadata.oid)) orelse return error.ObjectNotFound;
    
    try testing.expectEqualStrings(test_metadata.oid, retrieved.oid);
    try testing.expectEqual(test_metadata.size, retrieved.size);
    try testing.expectEqualStrings(test_metadata.checksum, retrieved.checksum);
    try testing.expectEqual(test_metadata.access_count, retrieved.access_count);
    try testing.expectEqualStrings(test_metadata.content_type.?, retrieved.content_type.?);
    try testing.expectEqual(test_metadata.storage_tier, retrieved.storage_tier);
    try testing.expectEqual(test_metadata.encrypted, retrieved.encrypted);
    try testing.expectEqual(test_metadata.repository_id, retrieved.repository_id);
    try testing.expectEqual(test_metadata.user_id, retrieved.user_id);
    try testing.expectEqual(test_metadata.organization_id, retrieved.organization_id);
}

test "metadata search and filtering works correctly" {
    const allocator = testing.allocator;
    
    var metadata_manager = try LfsMetadataManager.init(allocator, null);
    defer metadata_manager.deinit();
    
    // Store multiple test objects
    const test_objects = [_]EnhancedLfsMetadata{
        .{
            .oid = "oid1",
            .size = 1000,
            .checksum = "checksum1",
            .created_at = 1000,
            .last_accessed = 1000,
            .repository_id = 100,
            .user_id = 200,
            .storage_tier = .hot,
            .storage_backend = "filesystem",
        },
        .{
            .oid = "oid2", 
            .size = 2000,
            .checksum = "checksum2",
            .created_at = 2000,
            .last_accessed = 2000,
            .repository_id = 100,
            .user_id = 300,
            .storage_tier = .warm,
            .storage_backend = "s3",
        },
        .{
            .oid = "oid3",
            .size = 3000,
            .checksum = "checksum3", 
            .created_at = 3000,
            .last_accessed = 3000,
            .repository_id = 200,
            .user_id = 200,
            .storage_tier = .cold,
            .storage_backend = "filesystem",
        },
    };
    
    for (test_objects) |obj| {
        try metadata_manager.storeMetadata(obj);
    }
    
    // Test search by repository
    const repo_query = MetadataSearchQuery{ .repository_id = 100 };
    const repo_results = try metadata_manager.searchMetadata(repo_query);
    defer allocator.free(repo_results.objects);
    
    try testing.expectEqual(@as(u32, 2), repo_results.total_count);
    try testing.expect(!repo_results.has_more);
    
    // Test search by user
    const user_query = MetadataSearchQuery{ .user_id = 200 };
    const user_results = try metadata_manager.searchMetadata(user_query);
    defer allocator.free(user_results.objects);
    
    try testing.expectEqual(@as(u32, 2), user_results.total_count);
    
    // Test search by storage tier
    const tier_query = MetadataSearchQuery{ .storage_tier = .warm };
    const tier_results = try metadata_manager.searchMetadata(tier_query);
    defer allocator.free(tier_results.objects);
    
    try testing.expectEqual(@as(u32, 1), tier_results.total_count);
    try testing.expectEqualStrings("oid2", tier_results.objects[0].oid);
    
    // Test search with size range
    const size_query = MetadataSearchQuery{ .min_size = 1500, .max_size = 2500 };
    const size_results = try metadata_manager.searchMetadata(size_query);
    defer allocator.free(size_results.objects);
    
    try testing.expectEqual(@as(u32, 1), size_results.total_count);
    try testing.expectEqualStrings("oid2", size_results.objects[0].oid);
}

test "metadata updates and access tracking" {
    const allocator = testing.allocator;
    
    var metadata_manager = try LfsMetadataManager.init(allocator, null);
    defer metadata_manager.deinit();
    
    const original_metadata = EnhancedLfsMetadata{
        .oid = "update_test_oid",
        .size = 1024,
        .checksum = "original_checksum",
        .created_at = 1000,
        .last_accessed = 1000,
        .access_count = 1,
        .storage_tier = .hot,
        .storage_backend = "filesystem",
    };
    
    // Store original metadata
    try metadata_manager.storeMetadata(original_metadata);
    
    // Update access statistics
    try metadata_manager.updateAccessStatistics(original_metadata.oid);
    
    // Retrieve updated metadata
    const updated = (try metadata_manager.getMetadata(original_metadata.oid)) orelse return error.ObjectNotFound;
    
    try testing.expectEqual(@as(u64, 2), updated.access_count);
    try testing.expect(updated.last_accessed > original_metadata.last_accessed);
    
    // Test full metadata update
    var modified_metadata = original_metadata;
    modified_metadata.storage_tier = .cold;
    modified_metadata.access_count = 10;
    
    try metadata_manager.updateMetadata(original_metadata.oid, modified_metadata);
    
    const final_metadata = (try metadata_manager.getMetadata(original_metadata.oid)) orelse return error.ObjectNotFound;
    try testing.expectEqual(StorageTier.cold, final_metadata.storage_tier);
    try testing.expectEqual(@as(u64, 10), final_metadata.access_count);
}

test "storage usage statistics calculation" {
    const allocator = testing.allocator;
    
    var metadata_manager = try LfsMetadataManager.init(allocator, null);
    defer metadata_manager.deinit();
    
    // Store test objects with different characteristics
    const test_objects = [_]EnhancedLfsMetadata{
        .{
            .oid = "stats1",
            .size = 1000,
            .checksum = "checksum1",
            .created_at = 1000,
            .last_accessed = 1000,
            .repository_id = 100,
            .storage_tier = .hot,
            .encrypted = true,
            .compression_algorithm = .gzip,
            .duplicate_references = 1,
            .storage_backend = "filesystem",
        },
        .{
            .oid = "stats2",
            .size = 2000,
            .checksum = "checksum2",
            .created_at = 2000,
            .last_accessed = 2000,
            .repository_id = 100,
            .storage_tier = .warm,
            .encrypted = false,
            .compression_algorithm = .none,
            .storage_backend = "s3",
        },
        .{
            .oid = "stats3",
            .size = 3000,
            .checksum = "checksum3",
            .created_at = 3000,
            .last_accessed = 3000,
            .repository_id = 200,
            .storage_tier = .cold,
            .encrypted = true,
            .compression_algorithm = .lz4,
            .storage_backend = "filesystem",
        },
    };
    
    for (test_objects) |obj| {
        try metadata_manager.storeMetadata(obj);
    }
    
    // Get usage statistics
    var stats = try metadata_manager.getStorageUsageStats();
    defer stats.objects_by_repository.deinit();
    defer stats.size_by_repository.deinit();
    
    try testing.expectEqual(@as(u64, 3), stats.total_objects);
    try testing.expectEqual(@as(u64, 6000), stats.total_size_bytes);
    try testing.expectEqual(@as(u64, 2), stats.encrypted_objects);
    try testing.expectEqual(@as(u64, 2), stats.compressed_objects);
    try testing.expectEqual(@as(u64, 1000), stats.duplicate_space_saved); // 1000 * 1 duplicate reference
    
    // Check tier distribution
    try testing.expectEqual(@as(u64, 1), stats.objects_by_tier.get(.hot).?);
    try testing.expectEqual(@as(u64, 1), stats.objects_by_tier.get(.warm).?);
    try testing.expectEqual(@as(u64, 1), stats.objects_by_tier.get(.cold).?);
    
    try testing.expectEqual(@as(u64, 1000), stats.size_by_tier.get(.hot).?);
    try testing.expectEqual(@as(u64, 2000), stats.size_by_tier.get(.warm).?);
    try testing.expectEqual(@as(u64, 3000), stats.size_by_tier.get(.cold).?);
    
    // Check repository distribution
    try testing.expectEqual(@as(u64, 2), stats.objects_by_repository.get(100).?);
    try testing.expectEqual(@as(u64, 1), stats.objects_by_repository.get(200).?);
    try testing.expectEqual(@as(u64, 3000), stats.size_by_repository.get(100).?);
    try testing.expectEqual(@as(u64, 3000), stats.size_by_repository.get(200).?);
}

test "metadata deletion and cleanup" {
    const allocator = testing.allocator;
    
    var metadata_manager = try LfsMetadataManager.init(allocator, null);
    defer metadata_manager.deinit();
    
    const test_metadata = EnhancedLfsMetadata{
        .oid = "delete_test_oid",
        .size = 1024,
        .checksum = "delete_checksum",
        .created_at = std.time.timestamp(),
        .last_accessed = std.time.timestamp(),
        .storage_backend = "filesystem",
    };
    
    // Store metadata
    try metadata_manager.storeMetadata(test_metadata);
    
    // Verify it exists
    const retrieved = try metadata_manager.getMetadata(test_metadata.oid);
    try testing.expect(retrieved != null);
    
    // Delete metadata
    try metadata_manager.deleteMetadata(test_metadata.oid);
    
    // Verify it's gone
    const deleted = try metadata_manager.getMetadata(test_metadata.oid);
    try testing.expect(deleted == null);
    
    // Test cleanup operations
    const cleaned_count = try metadata_manager.cleanupOrphanedMetadata();
    try testing.expectEqual(@as(u32, 0), cleaned_count); // No orphaned records in test
}