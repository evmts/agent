# Implement Enterprise LFS Object Storage Backend (ENHANCED WITH GITEA PRODUCTION PATTERNS)

<task_definition>
Implement a comprehensive enterprise-grade LFS (Large File Storage) object storage backend with multi-backend support, content deduplication, encryption at rest, quota management, and enterprise monitoring. This backend handles efficient storage, retrieval, and management of large binary files with advanced features including content-addressed storage, automatic cleanup, multi-tier storage policies, and production-grade reliability following Gitea's battle-tested patterns.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: HTTP client for S3 API, Crypto for checksums/encryption, Database for metadata
- **Location**: `src/lfs/storage.zig`, `src/lfs/backends/`, `src/lfs/deduplication.zig`
- **🆕 Multi-Backend Support**: Filesystem, S3-compatible, multi-tier, hybrid configurations
- **🆕 Content Deduplication**: Content-addressed storage with automatic deduplication
- **🆕 Encryption at Rest**: AES-256 encryption with key rotation and secure key management
- **🆕 Quota Management**: Per-user, per-organization, and per-repository quota enforcement
- **🆕 Enterprise Monitoring**: Metrics collection, storage analytics, performance monitoring
- **Performance**: Streaming I/O, chunked uploads, parallel operations, caching layers
- **🆕 Advanced Security**: Content verification, access control, malware scanning integration
- **🆕 Production Reliability**: Atomic operations, checksums, data integrity, automated cleanup

</technical_requirements>

<business_context>

🆕 **Enterprise LFS Storage Backend Enables**:

- **🆕 Advanced Large File Management**: Efficient storage with deduplication, compression, and encryption
- **🆕 Multi-Tier Storage Policies**: Hot, warm, cold, and archival storage with automatic tiering
- **🆕 Enterprise Quota Management**: Granular quota enforcement at user, organization, and repository levels
- **🆕 Content Deduplication**: Automatic deduplication across repositories with content-addressed storage
- **🆕 Advanced Security**: Encryption at rest, malware scanning, access audit trails
- **Git LFS Protocol**: Complete Git LFS v1/v2 API implementation with batch extensions
- **🆕 Hybrid Cloud Storage**: Multi-backend configurations with failover and load balancing
- **🆕 Enterprise Monitoring**: Storage analytics, performance metrics, cost optimization insights
- **🆕 Automated Cleanup**: Intelligent cleanup policies with retention management
- **🆕 Production Reliability**: High availability, disaster recovery, data integrity verification

This provides enterprise-grade storage capabilities for organizations managing large binary assets across thousands of repositories and users, following Gitea's production-proven storage architecture.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

🆕 **Enterprise LFS Storage Requirements (Gitea Production Patterns)**:

1. **🆕 Multi-Tier Storage Backend Architecture**:
   ```zig
   const StorageBackend = union(enum) {
       filesystem: struct {
           base_path: []const u8,
           temp_path: []const u8,
           compression_enabled: bool,
           encryption_config: ?EncryptionConfig,
           deduplication_enabled: bool,
       },
       s3_compatible: struct {
           endpoint: []const u8,
           bucket: []const u8,
           region: []const u8,
           access_key: []const u8,
           secret_key: []const u8,
           encryption_key: ?[]const u8,
           cdn_domain: ?[]const u8,
           storage_class: S3StorageClass, // STANDARD, IA, GLACIER, etc.
       },
       multi_tier: struct {
           hot_storage: *StorageBackend,      // Frequently accessed objects
           warm_storage: *StorageBackend,     // Occasionally accessed objects  
           cold_storage: *StorageBackend,     // Rarely accessed objects
           archival_storage: *StorageBackend, // Long-term archival
           tier_policy: TieringPolicy,
       },
       hybrid: struct {
           primary_backend: *StorageBackend,
           secondary_backend: *StorageBackend,
           failover_enabled: bool,
           load_balancing: LoadBalancingPolicy,
       },
       memory: struct {
           max_size_bytes: u64,
           eviction_policy: EvictionPolicy,
       },
   };
   ```

2. **🆕 Enhanced LFS Object Operations with Enterprise Features**:
   ```zig
   // Store object with advanced options
   try storage.putObject(allocator, oid, content, .{
       .verify_checksum = true,
       .enable_encryption = true,
       .enable_compression = true,
       .enable_deduplication = true,
       .quota_context = quota_context,
       .malware_scan = true,
   });
   
   // Stream large object upload with quota enforcement
   var upload_stream = try storage.createUploadStream(allocator, oid, expected_size, .{
       .user_id = user_id,
       .organization_id = org_id,
       .repository_id = repo_id,
       .storage_tier = .hot,
   });
   defer upload_stream.deinit();
   try upload_stream.write(chunk_data);
   try upload_stream.finalize();
   
   // Get object with caching and access tracking
   var download_stream = try storage.getObjectStream(allocator, oid, .{
       .track_access = true,
       .update_tier_metadata = true,
       .cache_hint = .frequently_accessed,
   });
   defer download_stream.deinit();
   const data = try download_stream.readAll(allocator);
   ```

3. **🆕 Advanced Content Verification and Security**:
   ```zig
   const VerificationResult = struct {
       checksum_valid: bool,
       size_valid: bool,
       encryption_verified: bool,
       malware_scan_result: MalwareScanResult,
       content_type: ?[]const u8,
       duplicate_of: ?[]const u8, // OID of existing duplicate
   };
   
   const MalwareScanResult = enum {
       clean,
       infected,
       suspicious,
       scan_failed,
       scan_not_performed,
   };
   ```

4. **🆕 Enterprise Storage Operations**:
   ```zig
   // Quota management
   const QuotaInfo = struct {
       user_quota: QuotaLimits,
       organization_quota: QuotaLimits,
       repository_quota: QuotaLimits,
       current_usage: StorageUsage,
   };
   
   // Content deduplication
   const DeduplicationResult = struct {
       is_duplicate: bool,
       existing_oid: ?[]const u8,
       space_saved: u64,
       ref_count: u32,
   };
   
   // Storage tiering
   const TieringDecision = struct {
       current_tier: StorageTier,
       recommended_tier: StorageTier,
       tier_change_reason: TierChangeReason,
       estimated_cost_savings: f64,
   };
   ```

5. **🆕 Enterprise Monitoring and Analytics**:
   - Real-time storage metrics and usage analytics
   - Cost analysis and optimization recommendations
   - Performance monitoring with SLA tracking
   - Capacity planning with growth projections
   - Access pattern analysis for intelligent tiering

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

🆕 **Complete Enterprise LFS Storage System Providing**:

1. **🆕 Multi-Tier Storage Interface**: Unified API supporting complex storage hierarchies
2. **🆕 Enhanced Filesystem Backend**: High-performance local storage with encryption, compression, and deduplication
3. **🆕 Advanced S3 Backend**: Cloud storage with intelligent tiering, CDN integration, and cost optimization
4. **🆕 Hybrid Storage Configurations**: Multi-backend setups with failover and load balancing
5. **🆕 Content Deduplication Engine**: Automatic deduplication across repositories with reference counting
6. **🆕 Encryption at Rest**: AES-256 encryption with key rotation and secure key management
7. **🆕 Enterprise Quota Management**: Multi-level quota enforcement with usage analytics
8. **🆕 Malware Scanning Integration**: Automatic malware scanning with configurable policies
9. **🆕 Intelligent Storage Tiering**: Automatic object migration based on access patterns
10. **🆕 Enterprise Monitoring**: Comprehensive metrics, cost analysis, and performance tracking
11. **Content Verification**: Enhanced SHA-256 validation and integrity checking
12. **Streaming Support**: Efficient handling of large files with chunked transfers
13. **🆕 Advanced Metadata Management**: Rich metadata with access tracking and analytics
14. **🆕 Production-Grade Error Handling**: Comprehensive error recovery, retry logic, and circuit breakers
15. **🆕 Automated Cleanup**: Intelligent cleanup policies with retention management

🆕 **Enhanced Enterprise Storage Architecture**:
```zig
const EnterpriseStorage = struct {
    backend: StorageBackend,
    db: *DatabaseConnection,
    config: LfsConfig,
    deduplication_engine: *DeduplicationEngine,
    encryption_manager: *EncryptionManager,
    quota_manager: *QuotaManager,
    monitoring_service: *StorageMonitoring,
    malware_scanner: ?*MalwareScanner,
    
    pub fn init(allocator: std.mem.Allocator, backend: StorageBackend, db: *DatabaseConnection) !EnterpriseStorage;
    pub fn deinit(self: *EnterpriseStorage, allocator: std.mem.Allocator) void;
    
    // 🆕 Enhanced core object operations
    pub fn putObject(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8, content: []const u8, options: EnhancedPutOptions) !PutResult;
    pub fn getObject(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8, options: GetOptions) ![]u8;
    pub fn deleteObject(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8, options: DeleteOptions) !void;
    pub fn objectExists(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8) !bool;
    
    // 🆕 Advanced streaming with quota enforcement
    pub fn createUploadStream(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8, size: u64, context: UploadContext) !*EnhancedUploadStream;
    pub fn getObjectStream(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8, options: StreamOptions) !*EnhancedDownloadStream;
    
    // 🆕 Deduplication operations
    pub fn checkDuplication(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8) !DeduplicationResult;
    pub fn getDuplicateReferences(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8) ![]ObjectReference;
    
    // 🆕 Quota management
    pub fn checkQuota(self: *EnterpriseStorage, allocator: std.mem.Allocator, context: QuotaContext, size: u64) !QuotaCheckResult;
    pub fn getQuotaUsage(self: *EnterpriseStorage, allocator: std.mem.Allocator, scope: QuotaScope) !QuotaUsage;
    pub fn updateQuotaLimits(self: *EnterpriseStorage, allocator: std.mem.Allocator, updates: []QuotaUpdate) !void;
    
    // 🆕 Storage tiering operations
    pub fn evaluateTiering(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8) !TieringDecision;
    pub fn migrateToTier(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8, target_tier: StorageTier) !void;
    pub fn getBulkTieringRecommendations(self: *EnterpriseStorage, allocator: std.mem.Allocator, criteria: TieringCriteria) ![]TieringRecommendation;
    
    // 🆕 Enterprise monitoring and analytics
    pub fn getStorageMetrics(self: *EnterpriseStorage, allocator: std.mem.Allocator, scope: MetricsScope) !StorageMetrics;
    pub fn generateUsageReport(self: *EnterpriseStorage, allocator: std.mem.Allocator, params: ReportParameters) !UsageReport;
    pub fn getCostAnalysis(self: *EnterpriseStorage, allocator: std.mem.Allocator, period: TimePeriod) !CostAnalysis;
    
    // Enhanced batch operations
    pub fn putObjectsBatch(self: *EnterpriseStorage, allocator: std.mem.Allocator, objects: []const BatchPutRequest) ![]BatchPutResult;
    pub fn getObjectsBatch(self: *EnterpriseStorage, allocator: std.mem.Allocator, oids: []const []const u8) ![]BatchGetResult;
    
    // 🆕 Advanced metadata operations
    pub fn getObjectMetadata(self: *EnterpriseStorage, allocator: std.mem.Allocator, oid: []const u8) !EnhancedObjectMetadata;
    pub fn listObjects(self: *EnterpriseStorage, allocator: std.mem.Allocator, options: EnhancedListOptions) !ObjectList;
    pub fn searchObjects(self: *EnterpriseStorage, allocator: std.mem.Allocator, query: SearchQuery) !SearchResults;
    
    // 🆕 Production maintenance operations
    pub fn vacuum(self: *EnterpriseStorage, allocator: std.mem.Allocator, options: VacuumOptions) !VacuumResult;
    pub fn verifyIntegrity(self: *EnterpriseStorage, allocator: std.mem.Allocator, options: IntegrityCheckOptions) !IntegrityReport;
    pub fn performCleanup(self: *EnterpriseStorage, allocator: std.mem.Allocator, policy: CleanupPolicy) !CleanupResult;
};

// 🆕 Enhanced metadata structure
const EnhancedObjectMetadata = struct {
    oid: []const u8,
    size: u64,
    checksum: []const u8,
    created_at: i64,
    last_accessed: i64,
    access_count: u64,
    content_type: ?[]const u8,
    encryption_key_id: ?[]const u8,
    compression_algorithm: ?CompressionAlgorithm,
    storage_tier: StorageTier,
    duplicate_references: u32,
    malware_scan_result: MalwareScanResult,
    repository_id: ?u32,
    user_id: ?u32,
    organization_id: ?u32,
};

// 🆕 Enterprise-specific managers
const DeduplicationEngine = struct {
    pub fn checkDuplicate(self: *DeduplicationEngine, allocator: std.mem.Allocator, oid: []const u8) !?[]const u8;
    pub fn addReference(self: *DeduplicationEngine, allocator: std.mem.Allocator, oid: []const u8, ref: ObjectReference) !void;
    pub fn removeReference(self: *DeduplicationEngine, allocator: std.mem.Allocator, oid: []const u8, ref: ObjectReference) !bool;
    pub fn getStats(self: *DeduplicationEngine, allocator: std.mem.Allocator) !DeduplicationStats;
};

const QuotaManager = struct {
    pub fn enforceQuota(self: *QuotaManager, allocator: std.mem.Allocator, context: QuotaContext, size: u64) !void;
    pub fn updateUsage(self: *QuotaManager, allocator: std.mem.Allocator, context: QuotaContext, delta: i64) !void;
    pub fn getUsageReport(self: *QuotaManager, allocator: std.mem.Allocator, scope: QuotaScope) !QuotaUsageReport;
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
2. **🆕 Enterprise features**: Multi-backend support, deduplication, encryption, quota management
3. **🆕 Advanced performance**: Handle large files (>1GB) efficiently with streaming, compression, and tiering
4. **🆕 Content deduplication**: Automatic deduplication across repositories with significant space savings
5. **🆕 Encryption at rest**: Full AES-256 encryption with secure key management and rotation
6. **🆕 Quota enforcement**: Granular quota management at user, organization, and repository levels
7. **🆕 Storage tiering**: Intelligent automatic tiering based on access patterns with cost optimization
8. **🆕 Enterprise monitoring**: Comprehensive metrics, usage analytics, and cost analysis
9. **Reliability**: Atomic operations, data integrity, error recovery, and circuit breakers
10. **Scalability**: Support millions of objects with fast metadata operations and search
11. **🆕 Advanced security**: Content verification, malware scanning, access audit trails
12. **Integration**: Seamless integration with LFS HTTP server and permission systems
13. **🆕 Production ready**: Monitoring, alerting, automated cleanup, disaster recovery
14. **🆕 Battle-tested patterns**: Implementation following Gitea's production-proven storage architecture

</success_criteria>

</quality_assurance>

<reference_implementations>

**🆕 Enhanced with Gitea Production Patterns:**
- [🆕 Gitea LFS Storage Backend](https://github.com/go-gitea/gitea/tree/main/services/lfs)
- [🆕 Gitea Storage Configuration](https://github.com/go-gitea/gitea/blob/main/modules/storage/storage.go)
- [🆕 Gitea Content Deduplication](https://github.com/go-gitea/gitea/blob/main/services/lfs/content_store.go)
- [🆕 Gitea Quota Management](https://github.com/go-gitea/gitea/tree/main/modules/quota)
- [🆕 Gitea Storage Cleanup](https://github.com/go-gitea/gitea/blob/main/services/repository/cleanup.go)
- **Git LFS**: Official Git LFS storage backend implementations
- **S3 API**: AWS S3 API specification and best practices
- **Content-addressable storage**: IPFS and similar distributed storage systems
- **Object storage patterns**: Enterprise cloud storage service implementation patterns

**🆕 Key Gitea Patterns Implemented:**
- Multi-backend storage configurations with failover and load balancing
- Content deduplication with reference counting and space optimization
- Encryption at rest with secure key management and rotation policies
- Quota management with multi-level enforcement (user/org/repo)
- Intelligent storage tiering with cost optimization and access pattern analysis
- Enterprise monitoring with metrics collection and usage analytics

</reference_implementations>