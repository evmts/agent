# Implement LFS Object Storage Backend

<task_definition>
Implement a high-performance LFS (Large File Storage) object storage backend that supports multiple storage providers including filesystem, S3-compatible cloud storage, and in-memory storage for testing. This backend will handle efficient storage, retrieval, and management of large binary files for Git LFS operations with enterprise-grade performance, security, and reliability.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: HTTP client for S3 API, Crypto for checksums, Database for metadata
- **Location**: `src/lfs/storage.zig`, `src/lfs/backends/`
- **Storage Backends**: Filesystem, S3-compatible, In-memory (testing)
- **Performance**: Streaming I/O, chunked uploads, parallel operations
- **Security**: Content verification, access control, encryption at rest
- **Reliability**: Atomic operations, checksums, data integrity validation

</technical_requirements>

<business_context>

LFS storage backend enables:

- **Large File Management**: Efficient storage of binary assets (images, videos, datasets)
- **Git LFS Protocol**: Complete Git LFS v1 API implementation
- **Cloud Storage**: Scalable storage with S3-compatible providers
- **Content Deduplication**: Automatic deduplication by content hash
- **Access Control**: Integration with repository permissions
- **Performance**: High-throughput uploads and downloads with streaming
- **Cost Optimization**: Efficient storage utilization and transfer optimization

This is critical for supporting modern development workflows with large binary assets.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

LFS storage requirements:

1. **Storage Backends**:
   ```zig
   const StorageBackend = union(enum) {
       filesystem: struct {
           base_path: []const u8,
           temp_path: []const u8,
       },
       s3: struct {
           endpoint: []const u8,
           bucket: []const u8,
           region: []const u8,
           access_key: []const u8,
           secret_key: []const u8,
       },
       memory: struct {
           max_size_bytes: u64,
       },
   };
   ```

2. **LFS Object Operations**:
   ```zig
   // Store object with content verification
   try storage.putObject(allocator, oid, content, .{ .verify_checksum = true });
   
   // Stream large object upload
   var upload_stream = try storage.createUploadStream(allocator, oid, expected_size);
   defer upload_stream.deinit();
   try upload_stream.write(chunk_data);
   try upload_stream.finalize();
   
   // Get object with streaming
   var download_stream = try storage.getObjectStream(allocator, oid);
   defer download_stream.deinit();
   const data = try download_stream.readAll(allocator);
   ```

3. **Content Verification**:
   - SHA-256 checksum validation
   - Size verification
   - Content-Type detection
   - Virus scanning integration points

4. **Storage Operations**:
   - Atomic put/get operations
   - Batch operations for multiple objects
   - Metadata management (size, timestamp, checksum)
   - Cleanup and garbage collection

Expected integration patterns:
```bash
# Git LFS workflow
git lfs track "*.jpg"
git add large-image.jpg    # Stores to LFS backend
git push origin main       # Uploads LFS objects
git clone repo.git         # Downloads LFS pointers
git lfs pull              # Downloads actual LFS objects
```

</input>

<expected_output>

Complete LFS storage system providing:

1. **Storage Backend Interface**: Unified API for multiple storage providers
2. **Filesystem Backend**: High-performance local file storage with atomic operations
3. **S3 Backend**: Cloud storage with streaming uploads and multipart support
4. **Memory Backend**: In-memory storage for testing and caching
5. **Content Verification**: SHA-256 validation and integrity checking
6. **Streaming Support**: Efficient handling of large files without memory bloat
7. **Metadata Management**: Object metadata storage and indexing
8. **Error Handling**: Comprehensive error recovery and retry logic
9. **Performance Optimization**: Parallel operations, connection pooling, caching

Core storage architecture:
```zig
const LfsStorage = struct {
    backend: StorageBackend,
    db: *DatabaseConnection,
    config: LfsConfig,
    
    pub fn init(allocator: std.mem.Allocator, backend: StorageBackend, db: *DatabaseConnection) !LfsStorage;
    pub fn deinit(self: *LfsStorage, allocator: std.mem.Allocator) void;
    
    // Core object operations
    pub fn putObject(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8, content: []const u8, options: PutOptions) !void;
    pub fn getObject(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8) ![]u8;
    pub fn deleteObject(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8) !void;
    pub fn objectExists(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8) !bool;
    
    // Streaming operations
    pub fn createUploadStream(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8, size: u64) !*UploadStream;
    pub fn getObjectStream(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8) !*DownloadStream;
    
    // Batch operations
    pub fn putObjectsBatch(self: *LfsStorage, allocator: std.mem.Allocator, objects: []const BatchPutRequest) ![]BatchPutResult;
    pub fn getObjectsBatch(self: *LfsStorage, allocator: std.mem.Allocator, oids: []const []const u8) ![]BatchGetResult;
    
    // Metadata operations
    pub fn getObjectMetadata(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8) !ObjectMetadata;
    pub fn listObjects(self: *LfsStorage, allocator: std.mem.Allocator, options: ListOptions) !ObjectList;
    
    // Maintenance operations
    pub fn vacuum(self: *LfsStorage, allocator: std.mem.Allocator) !VacuumResult;
    pub fn verifyIntegrity(self: *LfsStorage, allocator: std.mem.Allocator) !IntegrityReport;
};

const ObjectMetadata = struct {
    oid: []const u8,
    size: u64,
    checksum: []const u8,
    created_at: i64,
    last_accessed: i64,
    content_type: ?[]const u8,
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Use real storage for all tests. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: Storage Backend Interface and Types (TDD)</title>

1. **Create LFS storage module structure**
   ```bash
   mkdir -p src/lfs/backends
   touch src/lfs/storage.zig
   touch src/lfs/backends/filesystem.zig
   touch src/lfs/backends/memory.zig
   ```

2. **Write tests for storage interface**
   ```zig
   test "LFS storage interface basic operations" {
       const allocator = testing.allocator;
       
       var storage = try LfsStorage.init(allocator, .{
           .filesystem = .{
               .base_path = "/tmp/lfs-test",
               .temp_path = "/tmp/lfs-temp",
           },
       }, &test_db);
       defer storage.deinit(allocator);
       
       const test_oid = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
       const test_content = "Hello, LFS!";
       
       // Test put operation
       try storage.putObject(allocator, test_oid, test_content, .{});
       
       // Test exists check
       try testing.expect(try storage.objectExists(allocator, test_oid));
       
       // Test get operation
       const retrieved_content = try storage.getObject(allocator, test_oid);
       defer allocator.free(retrieved_content);
       
       try testing.expectEqualStrings(test_content, retrieved_content);
       
       // Test delete operation
       try storage.deleteObject(allocator, test_oid);
       try testing.expect(!try storage.objectExists(allocator, test_oid));
   }
   
   test "LFS storage validates SHA-256 checksums" {
       const allocator = testing.allocator;
       
       var storage = try LfsStorage.init(allocator, test_backend, &test_db);
       defer storage.deinit(allocator);
       
       const invalid_oid = "invalid_sha256_hash";
       const content = "test content";
       
       // Should fail with checksum validation error
       try testing.expectError(error.InvalidChecksum, 
           storage.putObject(allocator, invalid_oid, content, .{ .verify_checksum = true }));
   }
   ```

3. **Implement core storage types and interfaces**
4. **Add checksum validation and content verification**

</phase_1>

<phase_2>
<title>Phase 2: Filesystem Backend Implementation (TDD)</title>

1. **Write tests for filesystem backend**
   ```zig
   test "filesystem backend stores objects with correct directory structure" {
       const allocator = testing.allocator;
       
       var tmp_dir = testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
       defer allocator.free(base_path);
       
       var backend = try FilesystemBackend.init(.{
           .base_path = base_path,
           .temp_path = base_path,
       });
       defer backend.deinit();
       
       const oid = "abcdef123456789012345678901234567890123456789012345678901234567890";
       const content = "test file content";
       
       try backend.putObject(allocator, oid, content);
       
       // Verify file exists in correct location: ab/cd/ef12...
       const expected_path = try std.fmt.allocPrint(allocator, "{s}/ab/cd/{s}", .{ base_path, oid });
       defer allocator.free(expected_path);
       
       const file = try std.fs.openFileAbsolute(expected_path, .{});
       defer file.close();
       
       const read_content = try file.readToEndAlloc(allocator, 1024);
       defer allocator.free(read_content);
       
       try testing.expectEqualStrings(content, read_content);
   }
   
   test "filesystem backend handles atomic writes with temp files" {
       // Test atomic write operations to prevent corruption
   }
   ```

2. **Implement filesystem backend with directory sharding**
3. **Add atomic write operations with temp files**
4. **Test concurrent access and file locking**

</phase_2>

<phase_3>
<title>Phase 3: Streaming Support and Large File Handling (TDD)</title>

1. **Write tests for streaming operations**
   ```zig
   test "upload stream handles large files efficiently" {
       const allocator = testing.allocator;
       
       var storage = try LfsStorage.init(allocator, test_backend, &test_db);
       defer storage.deinit(allocator);
       
       const oid = "large_file_oid_here";
       const total_size = 10 * 1024 * 1024; // 10MB
       const chunk_size = 64 * 1024; // 64KB chunks
       
       var upload_stream = try storage.createUploadStream(allocator, oid, total_size);
       defer upload_stream.deinit();
       
       // Write data in chunks
       var bytes_written: u64 = 0;
       while (bytes_written < total_size) {
           const remaining = total_size - bytes_written;
           const this_chunk_size = @min(chunk_size, remaining);
           
           const chunk_data = try allocator.alloc(u8, this_chunk_size);
           defer allocator.free(chunk_data);
           
           // Fill with test pattern
           for (chunk_data, 0..) |*byte, i| {
               byte.* = @truncate(u8, (bytes_written + i) & 0xFF);
           }
           
           try upload_stream.write(chunk_data);
           bytes_written += this_chunk_size;
       }
       
       try upload_stream.finalize();
       
       // Verify object was stored correctly
       try testing.expect(try storage.objectExists(allocator, oid));
       
       const metadata = try storage.getObjectMetadata(allocator, oid);
       try testing.expectEqual(total_size, metadata.size);
   }
   
   test "download stream provides efficient reading" {
       // Test streaming downloads for large files
   }
   ```

2. **Implement upload and download streaming**
3. **Add progress tracking and cancellation support**
4. **Test memory usage with large files**

</phase_3>

<phase_4>
<title>Phase 4: S3-Compatible Cloud Storage Backend (TDD)</title>

1. **Write tests for S3 backend**
   ```zig
   test "S3 backend performs basic operations" {
       const allocator = testing.allocator;
       
       // Skip test if S3 credentials not available
       const access_key = std.process.getEnvVarOwned(allocator, "TEST_S3_ACCESS_KEY") catch return;
       defer allocator.free(access_key);
       
       const secret_key = std.process.getEnvVarOwned(allocator, "TEST_S3_SECRET_KEY") catch return;
       defer allocator.free(secret_key);
       
       var backend = try S3Backend.init(.{
           .endpoint = "https://s3.amazonaws.com",
           .bucket = "test-lfs-bucket",
           .region = "us-east-1",
           .access_key = access_key,
           .secret_key = secret_key,
       });
       defer backend.deinit();
       
       const oid = "test_s3_object_oid";
       const content = "S3 test content";
       
       try backend.putObject(allocator, oid, content);
       
       const retrieved = try backend.getObject(allocator, oid);
       defer allocator.free(retrieved);
       
       try testing.expectEqualStrings(content, retrieved);
       
       try backend.deleteObject(allocator, oid);
   }
   
   test "S3 backend handles multipart uploads" {
       // Test multipart upload for large files
   }
   ```

2. **Implement S3 API client with authentication**
3. **Add multipart upload support for large files**
4. **Test error handling and retry logic**

</phase_4>

<phase_5>
<title>Phase 5: Memory Backend and Testing Infrastructure (TDD)</title>

1. **Write tests for memory backend**
   ```zig
   test "memory backend provides fast in-memory storage" {
       const allocator = testing.allocator;
       
       var backend = try MemoryBackend.init(.{
           .max_size_bytes = 10 * 1024 * 1024, // 10MB limit
       });
       defer backend.deinit(allocator);
       
       const oid = "memory_test_oid";
       const content = "memory test content";
       
       try backend.putObject(allocator, oid, content);
       
       const retrieved = try backend.getObject(allocator, oid);
       defer allocator.free(retrieved);
       
       try testing.expectEqualStrings(content, retrieved);
       
       // Test memory limits
       const large_content = try allocator.alloc(u8, 20 * 1024 * 1024); // 20MB
       defer allocator.free(large_content);
       
       try testing.expectError(error.StorageLimitExceeded, 
           backend.putObject(allocator, "large_oid", large_content));
   }
   ```

2. **Implement memory backend for testing**
3. **Add storage limits and eviction policies**
4. **Test concurrent access and thread safety**

</phase_5>

<phase_6>
<title>Phase 6: Metadata Management and Database Integration (TDD)</title>

1. **Write tests for metadata operations**
   ```zig
   test "stores and retrieves object metadata" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       var storage = try LfsStorage.init(allocator, test_backend, &db);
       defer storage.deinit(allocator);
       
       const oid = "metadata_test_oid";
       const content = "test content for metadata";
       
       try storage.putObject(allocator, oid, content, .{});
       
       const metadata = try storage.getObjectMetadata(allocator, oid);
       
       try testing.expectEqualStrings(oid, metadata.oid);
       try testing.expectEqual(@as(u64, content.len), metadata.size);
       try testing.expect(metadata.created_at > 0);
       try testing.expect(metadata.checksum.len == 64); // SHA-256 hex length
   }
   ```

2. **Implement metadata database schema**
3. **Add object indexing and search capabilities**
4. **Test metadata consistency and cleanup**

</phase_6>

<phase_7>
<title>Phase 7: Batch Operations and Performance Optimization (TDD)</title>

1. **Write tests for batch operations**
2. **Implement parallel batch processing**
3. **Add connection pooling and caching**
4. **Test performance with large object counts**

</phase_7>

<phase_8>
<title>Phase 8: Maintenance and Administrative Operations (TDD)</title>

1. **Write tests for vacuum and cleanup operations**
2. **Implement integrity verification**
3. **Add storage analytics and reporting**
4. **Test garbage collection and space reclamation**

</phase_8>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **Real Storage Testing**: Use actual filesystem and cloud storage for integration tests
- **Performance Testing**: Large file handling, concurrent operations, memory usage
- **Error Recovery**: Network failures, disk full, permission errors
- **Security Testing**: Access control, data integrity, checksum validation
- **Concurrency Testing**: Concurrent uploads/downloads, thread safety
- **Integration Testing**: End-to-end LFS workflows with Git clients

</testing_requirements>

<success_criteria>

1. **All tests pass**: Complete test coverage with zero failures
2. **Performance**: Handle large files (>1GB) efficiently with streaming
3. **Reliability**: Atomic operations, data integrity, error recovery
4. **Scalability**: Support thousands of objects with fast metadata operations
5. **Security**: Content verification, access control integration
6. **Integration**: Seamless integration with LFS HTTP server
7. **Production ready**: Monitoring, logging, maintenance operations

</success_criteria>

</quality_assurance>

<reference_implementations>

- **Git LFS**: Official Git LFS storage backend implementations
- **S3 API**: AWS S3 API specification and best practices
- **Content-addressable storage**: IPFS and similar distributed storage systems
- **Object storage patterns**: Cloud storage service implementation patterns

</reference_implementations>