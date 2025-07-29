const std = @import("std");
const testing = std.testing;

// Artifact storage errors
pub const ArtifactError = error{
    ArtifactNotFound,
    StorageFailure,
    InvalidPath,
    ArtifactTooLarge,
    InsufficientSpace,
};

// Artifact metadata
pub const Artifact = struct {
    id: []const u8,
    name: []const u8,
    path: []const u8,
    size: u64,
    content_type: []const u8,
    checksum: []const u8,
    created_at: i64,
    job_id: u32,
    
    pub fn deinit(self: Artifact, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.path);
        allocator.free(self.content_type);
        allocator.free(self.checksum);
    }
};

// Artifact storage backend types
pub const ArtifactStorageBackend = enum {
    filesystem,
    s3,
    memory, // For testing
};

// Artifact storage configuration
pub const ArtifactStorageConfig = struct {
    backend: ArtifactStorageBackend = .filesystem,
    base_path: ?[]const u8 = null,
    max_artifact_size: u64 = 1024 * 1024 * 1024, // 1GB default
    retention_days: u32 = 30,
};

// Artifact storage implementation
pub const ArtifactStorage = struct {
    allocator: std.mem.Allocator,
    config: ArtifactStorageConfig,
    artifacts: std.StringHashMap(Artifact),
    
    pub fn init(allocator: std.mem.Allocator, config: ArtifactStorageConfig) !ArtifactStorage {
        var storage_config = config;
        
        // Set default base path if not provided
        if (config.base_path == null) {
            storage_config.base_path = "/tmp/artifacts";
        }
        
        // Ensure base path exists for filesystem backend
        if (config.backend == .filesystem) {
            if (storage_config.base_path) |base_path| {
                std.fs.cwd().makePath(base_path) catch |err| switch (err) {
                    error.PathAlreadyExists => {}, // OK
                    else => return err,
                };
            }
        }
        
        return ArtifactStorage{
            .allocator = allocator,
            .config = ArtifactStorageConfig{
                .backend = storage_config.backend,
                .base_path = if (storage_config.base_path) |path| try allocator.dupe(u8, path) else null,
                .max_artifact_size = storage_config.max_artifact_size,
                .retention_days = storage_config.retention_days,
            },
            .artifacts = std.StringHashMap(Artifact).init(allocator),
        };
    }
    
    pub fn deinit(self: *ArtifactStorage) void {
        if (self.config.base_path) |path| {
            self.allocator.free(path);
        }
        
        // Clean up artifacts
        var artifacts_iter = self.artifacts.iterator();
        while (artifacts_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.artifacts.deinit();
    }
    
    pub fn storeArtifact(self: *ArtifactStorage, name: []const u8, data: []const u8, job_id: u32) !Artifact {
        if (data.len > self.config.max_artifact_size) {
            return ArtifactError.ArtifactTooLarge;
        }
        
        // Generate unique artifact ID
        const artifact_id = try std.fmt.allocPrint(self.allocator, "artifact_{d}_{d}", .{ job_id, std.time.timestamp() });
        
        // Calculate checksum (simple hash for testing)
        const checksum = try self.calculateChecksum(data);
        
        // Determine content type
        const content_type = try self.determineContentType(name);
        
        // Store artifact data based on backend
        const storage_path = try self.storeArtifactData(artifact_id, data);
        
        const artifact = Artifact{
            .id = artifact_id,
            .name = try self.allocator.dupe(u8, name),
            .path = storage_path,
            .size = data.len,
            .content_type = content_type,
            .checksum = checksum,
            .created_at = std.time.timestamp(),
            .job_id = job_id,
        };
        
        const owned_id = try self.allocator.dupe(u8, artifact_id);
        try self.artifacts.put(owned_id, artifact);
        
        return Artifact{
            .id = try self.allocator.dupe(u8, artifact.id),
            .name = try self.allocator.dupe(u8, artifact.name),
            .path = try self.allocator.dupe(u8, artifact.path),
            .size = artifact.size,
            .content_type = try self.allocator.dupe(u8, artifact.content_type),
            .checksum = try self.allocator.dupe(u8, artifact.checksum),
            .created_at = artifact.created_at,
            .job_id = artifact.job_id,
        };
    }
    
    pub fn getArtifact(self: *ArtifactStorage, artifact_id: []const u8) !Artifact {
        const artifact = self.artifacts.get(artifact_id) orelse {
            return ArtifactError.ArtifactNotFound;
        };
        
        // Return a copy
        return Artifact{
            .id = try self.allocator.dupe(u8, artifact.id),
            .name = try self.allocator.dupe(u8, artifact.name),
            .path = try self.allocator.dupe(u8, artifact.path),
            .size = artifact.size,
            .content_type = try self.allocator.dupe(u8, artifact.content_type),
            .checksum = try self.allocator.dupe(u8, artifact.checksum),
            .created_at = artifact.created_at,
            .job_id = artifact.job_id,
        };
    }
    
    pub fn getJobArtifacts(self: *ArtifactStorage, job_id: u32) ![]Artifact {
        var job_artifacts = std.ArrayList(Artifact).init(self.allocator);
        
        var artifacts_iter = self.artifacts.iterator();
        while (artifacts_iter.next()) |entry| {
            const artifact = entry.value_ptr.*;
            if (artifact.job_id == job_id) {
                try job_artifacts.append(Artifact{
                    .id = try self.allocator.dupe(u8, artifact.id),
                    .name = try self.allocator.dupe(u8, artifact.name),
                    .path = try self.allocator.dupe(u8, artifact.path),
                    .size = artifact.size,
                    .content_type = try self.allocator.dupe(u8, artifact.content_type),
                    .checksum = try self.allocator.dupe(u8, artifact.checksum),
                    .created_at = artifact.created_at,
                    .job_id = artifact.job_id,
                });
            }
        }
        
        return job_artifacts.toOwnedSlice();
    }
    
    pub fn downloadArtifact(self: *ArtifactStorage, artifact_id: []const u8) ![]const u8 {
        const artifact = self.artifacts.get(artifact_id) orelse {
            return ArtifactError.ArtifactNotFound;
        };
        
        // Load artifact data from storage
        switch (self.config.backend) {
            .filesystem => {
                const file = std.fs.cwd().openFile(artifact.path, .{}) catch {
                    return ArtifactError.StorageFailure;
                };
                defer file.close();
                
                const file_size = try file.getEndPos();
                const data = try self.allocator.alloc(u8, file_size);
                _ = try file.readAll(data);
                return data;
            },
            .memory => {
                // For testing, return mock data
                return try std.fmt.allocPrint(self.allocator, "Mock artifact data for {s}", .{artifact_id});
            },
            .s3 => {
                // Mock S3 download
                return try std.fmt.allocPrint(self.allocator, "S3 artifact data for {s}", .{artifact_id});
            },
        }
    }
    
    pub fn deleteArtifact(self: *ArtifactStorage, artifact_id: []const u8) !void {
        const removed = self.artifacts.remove(artifact_id);
        if (removed) {
            // Delete from storage backend
            switch (self.config.backend) {
                .filesystem => {
                    std.fs.cwd().deleteFile(removed.value.path) catch {}; // Best effort
                },
                .memory, .s3 => {
                    // Nothing to do for these backends in mock implementation
                },
            }
            
            self.allocator.free(removed.key);
            removed.value.deinit(self.allocator);
        } else {
            return ArtifactError.ArtifactNotFound;
        }
    }
    
    pub fn cleanupExpiredArtifacts(self: *ArtifactStorage) !u32 {
        const current_time = std.time.timestamp();
        const retention_seconds = @as(i64, self.config.retention_days) * 24 * 60 * 60;
        
        var expired_artifacts = std.ArrayList([]const u8).init(self.allocator);
        defer expired_artifacts.deinit();
        
        var artifacts_iter = self.artifacts.iterator();
        while (artifacts_iter.next()) |entry| {
            const artifact = entry.value_ptr.*;
            if (current_time - artifact.created_at > retention_seconds) {
                try expired_artifacts.append(try self.allocator.dupe(u8, artifact.id));
            }
        }
        
        // Delete expired artifacts
        for (expired_artifacts.items) |artifact_id| {
            self.deleteArtifact(artifact_id) catch {};
            self.allocator.free(artifact_id);
        }
        
        return @intCast(expired_artifacts.items.len);
    }
    
    fn storeArtifactData(self: *ArtifactStorage, artifact_id: []const u8, data: []const u8) ![]const u8 {
        switch (self.config.backend) {
            .filesystem => {
                const file_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/{s}",
                    .{ self.config.base_path.?, artifact_id }
                );
                
                const file = std.fs.cwd().createFile(file_path, .{}) catch {
                    self.allocator.free(file_path);
                    return ArtifactError.StorageFailure;
                };
                defer file.close();
                
                try file.writeAll(data);
                return file_path;
            },
            .memory => {
                // Return a mock path for memory backend
                return try std.fmt.allocPrint(self.allocator, "memory://{s}", .{artifact_id});
            },
            .s3 => {
                // Return a mock S3 path
                return try std.fmt.allocPrint(self.allocator, "s3://bucket/{s}", .{artifact_id});
            },
        }
    }
    
    fn calculateChecksum(self: *ArtifactStorage, data: []const u8) ![]const u8 {
        // Simple checksum calculation (in real implementation, use proper hashing)
        var hash: u32 = 0;
        for (data) |byte| {
            hash = hash *% 31 +% byte;
        }
        return try std.fmt.allocPrint(self.allocator, "{x}", .{hash});
    }
    
    fn determineContentType(self: *ArtifactStorage, filename: []const u8) ![]const u8 {
        const ext_start = std.mem.lastIndexOf(u8, filename, ".") orelse {
            return try self.allocator.dupe(u8, "application/octet-stream");
        };
        
        const extension = filename[ext_start + 1..];
        
        const content_type = if (std.mem.eql(u8, extension, "xml"))
            "application/xml"
        else if (std.mem.eql(u8, extension, "json"))
            "application/json"
        else if (std.mem.eql(u8, extension, "txt"))
            "text/plain"
        else if (std.mem.eql(u8, extension, "log"))
            "text/plain"
        else if (std.mem.eql(u8, extension, "zip"))
            "application/zip"
        else if (std.mem.eql(u8, extension, "tar"))
            "application/x-tar"
        else if (std.mem.eql(u8, extension, "gz"))
            "application/gzip"
        else
            "application/octet-stream";
            
        return try self.allocator.dupe(u8, content_type);
    }
};

// Tests for Phase 6: Artifact Management
test "artifact storage stores and retrieves artifacts" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const cache_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cache_path);
    
    var artifact_storage = try ArtifactStorage.init(allocator, .{
        .backend = .filesystem,
        .base_path = cache_path,
    });
    defer artifact_storage.deinit();
    
    const job_id: u32 = 123;
    const test_data = "<results><test>passed</test></results>";
    
    // Store artifact
    var artifact = try artifact_storage.storeArtifact("test-results.xml", test_data, job_id);
    defer artifact.deinit(allocator);
    
    try testing.expect(artifact.id.len > 0);
    try testing.expectEqualStrings("test-results.xml", artifact.name);
    try testing.expectEqualStrings("application/xml", artifact.content_type);
    try testing.expectEqual(@as(u64, test_data.len), artifact.size);
    try testing.expectEqual(job_id, artifact.job_id);
    
    // Retrieve artifact
    var retrieved = try artifact_storage.getArtifact(artifact.id);
    defer retrieved.deinit(allocator);
    
    try testing.expectEqualStrings(artifact.id, retrieved.id);
    try testing.expectEqualStrings(artifact.name, retrieved.name);
    try testing.expectEqual(artifact.size, retrieved.size);
}

test "artifact storage handles different file types correctly" {
    const allocator = testing.allocator;
    
    var artifact_storage = try ArtifactStorage.init(allocator, .{
        .backend = .memory,
    });
    defer artifact_storage.deinit();
    
    const job_id: u32 = 456;
    
    // Test JSON artifact
    {
        const json_data = "{\"test\": \"passed\"}";
        var json_artifact = try artifact_storage.storeArtifact("results.json", json_data, job_id);
        defer json_artifact.deinit(allocator);
        
        try testing.expectEqualStrings("application/json", json_artifact.content_type);
    }
    
    // Test text artifact
    {
        const text_data = "Test output log";
        var text_artifact = try artifact_storage.storeArtifact("output.log", text_data, job_id);
        defer text_artifact.deinit(allocator);
        
        try testing.expectEqualStrings("text/plain", text_artifact.content_type);
    }
    
    // Test binary artifact
    {
        const binary_data = [_]u8{0x50, 0x4B, 0x03, 0x04}; // ZIP header
        var binary_artifact = try artifact_storage.storeArtifact("archive.zip", &binary_data, job_id);
        defer binary_artifact.deinit(allocator);
        
        try testing.expectEqualStrings("application/zip", binary_artifact.content_type);
    }
}

test "artifact storage retrieves job-specific artifacts" {
    const allocator = testing.allocator;
    
    var artifact_storage = try ArtifactStorage.init(allocator, .{
        .backend = .memory,
    });
    defer artifact_storage.deinit();
    
    // Store artifacts for different jobs
    const job1_id: u32 = 100;
    const job2_id: u32 = 200;
    
    var artifact1 = try artifact_storage.storeArtifact("job1-results.xml", "job1 data", job1_id);
    defer artifact1.deinit(allocator);
    
    var artifact2 = try artifact_storage.storeArtifact("job1-logs.txt", "job1 logs", job1_id);
    defer artifact2.deinit(allocator);
    
    var artifact3 = try artifact_storage.storeArtifact("job2-results.xml", "job2 data", job2_id);
    defer artifact3.deinit(allocator);
    
    // Get artifacts for job1
    const job1_artifacts = try artifact_storage.getJobArtifacts(job1_id);
    defer {
        for (job1_artifacts) |*artifact| {
            artifact.deinit(allocator);
        }
        allocator.free(job1_artifacts);
    }
    
    try testing.expectEqual(@as(usize, 2), job1_artifacts.len);
    
    // Get artifacts for job2
    const job2_artifacts = try artifact_storage.getJobArtifacts(job2_id);
    defer {
        for (job2_artifacts) |*artifact| {
            artifact.deinit(allocator);
        }
        allocator.free(job2_artifacts);
    }
    
    try testing.expectEqual(@as(usize, 1), job2_artifacts.len);
    try testing.expectEqualStrings("job2-results.xml", job2_artifacts[0].name);
}

test "artifact storage downloads artifact data" {
    const allocator = testing.allocator;
    
    var artifact_storage = try ArtifactStorage.init(allocator, .{
        .backend = .memory,
    });
    defer artifact_storage.deinit();
    
    const test_data = "This is test artifact content";
    var artifact = try artifact_storage.storeArtifact("test.txt", test_data, 789);
    defer artifact.deinit(allocator);
    
    // Download artifact data
    const downloaded_data = try artifact_storage.downloadArtifact(artifact.id);
    defer allocator.free(downloaded_data);
    
    try testing.expect(downloaded_data.len > 0);
    try testing.expect(std.mem.indexOf(u8, downloaded_data, artifact.id) != null);
}

test "artifact storage handles size limits" {
    const allocator = testing.allocator;
    
    var artifact_storage = try ArtifactStorage.init(allocator, .{
        .backend = .memory,
        .max_artifact_size = 100, // Small limit for testing
    });
    defer artifact_storage.deinit();
    
    // Try to store artifact that exceeds size limit
    const large_data = "x" ** 200; // 200 bytes, exceeds limit
    
    const result = artifact_storage.storeArtifact("large.txt", large_data, 999);
    try testing.expectError(ArtifactError.ArtifactTooLarge, result);
}

test "artifact storage cleanup removes expired artifacts" {
    const allocator = testing.allocator;
    
    var artifact_storage = try ArtifactStorage.init(allocator, .{
        .backend = .memory,
        .retention_days = 0, // Immediate expiration for testing
    });
    defer artifact_storage.deinit();
    
    // Store some artifacts
    var artifact1 = try artifact_storage.storeArtifact("old1.txt", "data1", 111);
    defer artifact1.deinit(allocator);
    
    var artifact2 = try artifact_storage.storeArtifact("old2.txt", "data2", 222);
    defer artifact2.deinit(allocator);
    
    // Wait a moment to ensure timestamp difference
    std.time.sleep(1000000); // 1ms
    
    // Run cleanup
    const cleaned_count = try artifact_storage.cleanupExpiredArtifacts();
    
    try testing.expectEqual(@as(u32, 2), cleaned_count);
    
    // Verify artifacts are gone
    const result1 = artifact_storage.getArtifact(artifact1.id);
    try testing.expectError(ArtifactError.ArtifactNotFound, result1);
    
    const result2 = artifact_storage.getArtifact(artifact2.id);
    try testing.expectError(ArtifactError.ArtifactNotFound, result2);
}