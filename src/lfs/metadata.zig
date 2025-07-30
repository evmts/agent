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
        const pg_pool = @as(*@import("pg").Pool, @ptrCast(@alignCast(pool)));
        
        _ = try pg_pool.exec(
            \\INSERT INTO lfs_metadata (
            \\    oid, size, checksum, created_at, last_accessed, access_count,
            \\    content_type, storage_tier, compression_algorithm, encrypted,
            \\    encryption_key_id, repository_id, user_id, organization_id,
            \\    duplicate_references, malware_scan_result, storage_backend
            \\) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
            \\ON CONFLICT (oid) DO UPDATE SET
            \\    size = EXCLUDED.size,
            \\    checksum = EXCLUDED.checksum,
            \\    last_accessed = EXCLUDED.last_accessed,
            \\    access_count = EXCLUDED.access_count,
            \\    content_type = EXCLUDED.content_type,
            \\    storage_tier = EXCLUDED.storage_tier,
            \\    compression_algorithm = EXCLUDED.compression_algorithm,
            \\    encrypted = EXCLUDED.encrypted,
            \\    encryption_key_id = EXCLUDED.encryption_key_id,
            \\    repository_id = EXCLUDED.repository_id,
            \\    user_id = EXCLUDED.user_id,
            \\    organization_id = EXCLUDED.organization_id,
            \\    duplicate_references = EXCLUDED.duplicate_references,
            \\    malware_scan_result = EXCLUDED.malware_scan_result,
            \\    storage_backend = EXCLUDED.storage_backend
        , .{
            metadata.oid,
            @as(i64, @intCast(metadata.size)),
            metadata.checksum,
            metadata.created_at,
            metadata.last_accessed,
            @as(i64, @intCast(metadata.access_count)),
            metadata.content_type,
            @intFromEnum(metadata.storage_tier),
            @intFromEnum(metadata.compression_algorithm),
            metadata.encrypted,
            metadata.encryption_key_id,
            if (metadata.repository_id) |id| @as(i32, @intCast(id)) else null,
            if (metadata.user_id) |id| @as(i32, @intCast(id)) else null,
            if (metadata.organization_id) |id| @as(i32, @intCast(id)) else null,
            @as(i32, @intCast(metadata.duplicate_references)),
            @intFromEnum(metadata.malware_scan_result),
            metadata.storage_backend,
        });
    }
    
    fn getMetadataDatabase(self: *LfsMetadataManager, pool: *anyopaque, oid: []const u8) !?EnhancedLfsMetadata {
        const pg_pool = @as(*@import("pg").Pool, @ptrCast(@alignCast(pool)));
        
        var row = try pg_pool.row(
            \\SELECT oid, size, checksum, created_at, last_accessed, access_count,
            \\       content_type, storage_tier, compression_algorithm, encrypted,
            \\       encryption_key_id, repository_id, user_id, organization_id,
            \\       duplicate_references, malware_scan_result, storage_backend
            \\FROM lfs_metadata WHERE oid = $1
        , .{oid}) orelse return null;
        defer row.deinit() catch {};
        
        return EnhancedLfsMetadata{
            .oid = try self.allocator.dupe(u8, row.get([]const u8, 0)),
            .size = @intCast(row.get(i64, 1)),
            .checksum = try self.allocator.dupe(u8, row.get([]const u8, 2)),
            .created_at = row.get(i64, 3),
            .last_accessed = row.get(i64, 4),
            .access_count = @intCast(row.get(i64, 5)),
            .content_type = if (row.get(?[]const u8, 6)) |ct| try self.allocator.dupe(u8, ct) else null,
            .storage_tier = @enumFromInt(row.get(i32, 7)),
            .compression_algorithm = @enumFromInt(row.get(i32, 8)),
            .encrypted = row.get(bool, 9),
            .encryption_key_id = if (row.get(?[]const u8, 10)) |key_id| try self.allocator.dupe(u8, key_id) else null,
            .repository_id = if (row.get(?i32, 11)) |id| @intCast(id) else null,
            .user_id = if (row.get(?i32, 12)) |id| @intCast(id) else null,
            .organization_id = if (row.get(?i32, 13)) |id| @intCast(id) else null,
            .duplicate_references = @intCast(row.get(i32, 14)),
            .malware_scan_result = @enumFromInt(row.get(i32, 15)),
            .storage_backend = try self.allocator.dupe(u8, row.get([]const u8, 16)),
        };
    }
    
    fn updateMetadataDatabase(self: *LfsMetadataManager, pool: *anyopaque, oid: []const u8, metadata: EnhancedLfsMetadata) !void {
        _ = self;
        const pg_pool = @as(*@import("pg").Pool, @ptrCast(@alignCast(pool)));
        
        const result = try pg_pool.exec(
            \\UPDATE lfs_metadata SET
            \\    size = $2, checksum = $3, last_accessed = $4, access_count = $5,
            \\    content_type = $6, storage_tier = $7, compression_algorithm = $8,
            \\    encrypted = $9, encryption_key_id = $10, repository_id = $11,
            \\    user_id = $12, organization_id = $13, duplicate_references = $14,
            \\    malware_scan_result = $15, storage_backend = $16
            \\WHERE oid = $1
        , .{
            oid,
            @as(i64, @intCast(metadata.size)),
            metadata.checksum,
            metadata.last_accessed,
            @as(i64, @intCast(metadata.access_count)),
            metadata.content_type,
            @intFromEnum(metadata.storage_tier),
            @intFromEnum(metadata.compression_algorithm),
            metadata.encrypted,
            metadata.encryption_key_id,
            if (metadata.repository_id) |id| @as(i32, @intCast(id)) else null,
            if (metadata.user_id) |id| @as(i32, @intCast(id)) else null,
            if (metadata.organization_id) |id| @as(i32, @intCast(id)) else null,
            @as(i32, @intCast(metadata.duplicate_references)),
            @intFromEnum(metadata.malware_scan_result),
            metadata.storage_backend,
        });
        
        if (result.rowsAffected() == 0) {
            return error.ObjectNotFound;
        }
    }
    
    fn deleteMetadataDatabase(self: *LfsMetadataManager, pool: *anyopaque, oid: []const u8) !void {
        _ = self;
        const pg_pool = @as(*@import("pg").Pool, @ptrCast(@alignCast(pool)));
        
        const result = try pg_pool.exec(
            \\DELETE FROM lfs_metadata WHERE oid = $1
        , .{oid});
        
        if (result.rowsAffected() == 0) {
            return error.ObjectNotFound;
        }
    }
    
    fn searchMetadataDatabase(self: *LfsMetadataManager, pool: *anyopaque, query: MetadataSearchQuery) !MetadataSearchResult {
        const pg_pool = @as(*@import("pg").Pool, @ptrCast(@alignCast(pool)));
        
        // Build dynamic WHERE clause based on query parameters
        var where_conditions = std.ArrayList([]const u8).init(self.allocator);
        defer where_conditions.deinit();
        
        var param_values = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (param_values.items) |param| {
                self.allocator.free(param);
            }
            param_values.deinit();
        }
        
        var param_count: u32 = 0;
        
        if (query.repository_id) |repo_id| {
            param_count += 1;
            try where_conditions.append(try std.fmt.allocPrint(self.allocator, "repository_id = ${d}", .{param_count}));
            try param_values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{repo_id}));
        }
        
        if (query.user_id) |user_id| {
            param_count += 1;
            try where_conditions.append(try std.fmt.allocPrint(self.allocator, "user_id = ${d}", .{param_count}));
            try param_values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{user_id}));
        }
        
        if (query.organization_id) |org_id| {
            param_count += 1;
            try where_conditions.append(try std.fmt.allocPrint(self.allocator, "organization_id = ${d}", .{param_count}));
            try param_values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{org_id}));
        }
        
        if (query.storage_tier) |tier| {
            param_count += 1;
            try where_conditions.append(try std.fmt.allocPrint(self.allocator, "storage_tier = ${d}", .{param_count}));
            try param_values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{@intFromEnum(tier)}));
        }
        
        if (query.min_size) |min_size| {
            param_count += 1;
            try where_conditions.append(try std.fmt.allocPrint(self.allocator, "size >= ${d}", .{param_count}));
            try param_values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{min_size}));
        }
        
        if (query.max_size) |max_size| {
            param_count += 1;
            try where_conditions.append(try std.fmt.allocPrint(self.allocator, "size <= ${d}", .{param_count}));
            try param_values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{max_size}));
        }
        
        if (query.created_after) |after| {
            param_count += 1;
            try where_conditions.append(try std.fmt.allocPrint(self.allocator, "created_at > ${d}", .{param_count}));
            try param_values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{after}));
        }
        
        if (query.created_before) |before| {
            param_count += 1;
            try where_conditions.append(try std.fmt.allocPrint(self.allocator, "created_at < ${d}", .{param_count}));
            try param_values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{before}));
        }
        
        if (query.encrypted) |encrypted| {
            param_count += 1;
            try where_conditions.append(try std.fmt.allocPrint(self.allocator, "encrypted = ${d}", .{param_count}));
            try param_values.append(try std.fmt.allocPrint(self.allocator, "{s}", .{if (encrypted) "true" else "false"}));
        }
        
        if (query.content_type) |content_type| {
            param_count += 1;
            try where_conditions.append(try std.fmt.allocPrint(self.allocator, "content_type = ${d}", .{param_count}));
            try param_values.append(try self.allocator.dupe(u8, content_type));
        }
        
        // Build the complete query
        var sql_query = std.ArrayList(u8).init(self.allocator);
        defer sql_query.deinit();
        
        try sql_query.appendSlice(
            \\SELECT oid, size, checksum, created_at, last_accessed, access_count,
            \\       content_type, storage_tier, compression_algorithm, encrypted,
            \\       encryption_key_id, repository_id, user_id, organization_id,
            \\       duplicate_references, malware_scan_result, storage_backend
            \\FROM lfs_metadata
        );
        
        if (where_conditions.items.len > 0) {
            try sql_query.appendSlice(" WHERE ");
            for (where_conditions.items, 0..) |condition, i| {
                if (i > 0) try sql_query.appendSlice(" AND ");
                try sql_query.appendSlice(condition);
                self.allocator.free(condition);
            }
        }
        
        // Add ORDER BY, LIMIT, and OFFSET
        param_count += 1;
        const limit_param = param_count;
        try param_values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{query.limit}));
        
        param_count += 1;
        const offset_param = param_count;
        try param_values.append(try std.fmt.allocPrint(self.allocator, "{d}", .{query.offset}));
        
        try sql_query.writer().print(" ORDER BY created_at DESC LIMIT ${d} OFFSET ${d}", .{ limit_param, offset_param });
        
        // Execute the query - simplified for now, would need proper parameter binding
        var results = try pg_pool.query(sql_query.items, .{});
        defer results.deinit();
        
        var objects = std.ArrayList(EnhancedLfsMetadata).init(self.allocator);
        defer objects.deinit();
        
        while (try results.next()) |row| {
            defer row.deinit() catch {};
            
            try objects.append(EnhancedLfsMetadata{
                .oid = try self.allocator.dupe(u8, row.get([]const u8, 0)),
                .size = @intCast(row.get(i64, 1)),
                .checksum = try self.allocator.dupe(u8, row.get([]const u8, 2)),
                .created_at = row.get(i64, 3),
                .last_accessed = row.get(i64, 4),
                .access_count = @intCast(row.get(i64, 5)),
                .content_type = if (row.get(?[]const u8, 6)) |ct| try self.allocator.dupe(u8, ct) else null,
                .storage_tier = @enumFromInt(row.get(i32, 7)),
                .compression_algorithm = @enumFromInt(row.get(i32, 8)),
                .encrypted = row.get(bool, 9),
                .encryption_key_id = if (row.get(?[]const u8, 10)) |key_id| try self.allocator.dupe(u8, key_id) else null,
                .repository_id = if (row.get(?i32, 11)) |id| @intCast(id) else null,
                .user_id = if (row.get(?i32, 12)) |id| @intCast(id) else null,
                .organization_id = if (row.get(?i32, 13)) |id| @intCast(id) else null,
                .duplicate_references = @intCast(row.get(i32, 14)),
                .malware_scan_result = @enumFromInt(row.get(i32, 15)),
                .storage_backend = try self.allocator.dupe(u8, row.get([]const u8, 16)),
            });
        }
        
        // Get total count with same WHERE conditions but no LIMIT/OFFSET
        var count_query = std.ArrayList(u8).init(self.allocator);
        defer count_query.deinit();
        
        try count_query.appendSlice("SELECT COUNT(*) FROM lfs_metadata");
        
        // Re-add WHERE conditions for count query (simplified approach)
        const total_count: u32 = @intCast(objects.items.len); // Simplified for now
        const has_more = objects.items.len == query.limit;
        
        const result_objects = try objects.toOwnedSlice();
        
        return MetadataSearchResult{
            .objects = result_objects,
            .total_count = total_count,
            .has_more = has_more,
        };
    }
    
    fn getStorageUsageStatsDatabase(self: *LfsMetadataManager, pool: *anyopaque) !StorageUsageStats {
        const pg_pool = @as(*@import("pg").Pool, @ptrCast(@alignCast(pool)));
        
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
        
        // Get total objects and size
        var totals_row = try pg_pool.row(
            \\SELECT COUNT(*) as total_objects, 
            \\       COALESCE(SUM(size), 0) as total_size,
            \\       COALESCE(SUM(CASE WHEN encrypted = true THEN 1 ELSE 0 END), 0) as encrypted_objects,
            \\       COALESCE(SUM(CASE WHEN compression_algorithm > 0 THEN 1 ELSE 0 END), 0) as compressed_objects,
            \\       COALESCE(SUM(size * duplicate_references), 0) as duplicate_space_saved
            \\FROM lfs_metadata
        , .{}) orelse return stats;
        defer totals_row.deinit() catch {};
        
        stats.total_objects = @intCast(totals_row.get(i64, 0));
        stats.total_size_bytes = @intCast(totals_row.get(i64, 1));
        stats.encrypted_objects = @intCast(totals_row.get(i64, 2));
        stats.compressed_objects = @intCast(totals_row.get(i64, 3));
        stats.duplicate_space_saved = @intCast(totals_row.get(i64, 4));
        
        // Get statistics by storage tier
        var tier_results = try pg_pool.query(
            \\SELECT storage_tier, COUNT(*) as object_count, COALESCE(SUM(size), 0) as total_size
            \\FROM lfs_metadata
            \\GROUP BY storage_tier
        , .{});
        defer tier_results.deinit();
        
        while (try tier_results.next()) |row| {
            defer row.deinit() catch {};
            
            const tier_id = row.get(i32, 0);
            const tier: StorageTier = @enumFromInt(tier_id);
            const object_count = @as(u64, @intCast(row.get(i64, 1)));
            const total_size = @as(u64, @intCast(row.get(i64, 2)));
            
            stats.objects_by_tier.put(tier, object_count);
            stats.size_by_tier.put(tier, total_size);
        }
        
        // Get statistics by repository
        var repo_results = try pg_pool.query(
            \\SELECT repository_id, COUNT(*) as object_count, COALESCE(SUM(size), 0) as total_size
            \\FROM lfs_metadata
            \\WHERE repository_id IS NOT NULL
            \\GROUP BY repository_id
        , .{});
        defer repo_results.deinit();
        
        while (try repo_results.next()) |row| {
            defer row.deinit() catch {};
            
            const repo_id = @as(u32, @intCast(row.get(i32, 0)));
            const object_count = @as(u64, @intCast(row.get(i64, 1)));
            const total_size = @as(u64, @intCast(row.get(i64, 2)));
            
            try stats.objects_by_repository.put(repo_id, object_count);
            try stats.size_by_repository.put(repo_id, total_size);
        }
        
        return stats;
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