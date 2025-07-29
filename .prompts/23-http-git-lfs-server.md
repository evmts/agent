# Implement Enterprise HTTP Git and LFS Server (ENHANCED WITH GITEA PRODUCTION PATTERNS)

<task_definition>
Implement a comprehensive enterprise-grade HTTP server that provides Git Smart HTTP protocol v2 support, advanced Git LFS capabilities, and multi-authentication systems. This server handles Git operations over HTTPS with security hardening, performance optimization, advanced LFS features, and production-grade reliability following Gitea's battle-tested patterns for high-traffic Git hosting environments.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig with Zap HTTP framework - https://ziglang.org/documentation/master/
- **Dependencies**: Zap HTTP server, Git command wrapper, Permission system, Database layer
- **🆕 Protocols**: Git Smart HTTP v1/v2, Git LFS API v1 with batch extensions
- **Location**: `src/http/git_server.zig`, `src/http/lfs_server.zig`, `src/http/auth_middleware.zig`
- **🆕 Multi-Authentication**: HTTP Basic, Bearer tokens, API keys, SSH key authentication over HTTP
- **🆕 Security Hardening**: Input validation, request sanitization, DoS protection, security headers
- **🆕 Performance Optimization**: HTTP/2 support, connection pooling, streaming pipelines, caching layers
- **🆕 Advanced LFS**: Batch API v2, resumable uploads, chunked transfers, deduplication
- **🆕 Storage Backends**: Multi-tier storage, CDN integration, object versioning, cleanup automation

</technical_requirements>

<business_context>

🆕 **Enterprise HTTP Git Server Enables**:

- **🆕 Multi-Protocol Git Operations**: Git Smart HTTP v1/v2 with performance optimizations
- **🆕 Advanced Authentication**: Multi-tier authentication with organization/team support
- **🆕 Enterprise LFS Management**: Advanced LFS with deduplication, resumable uploads, and CDN integration
- **🆕 High-Performance Operations**: HTTP/2, streaming pipelines, connection pooling for high-traffic environments
- **🆕 Security Hardening**: DoS protection, input validation, security headers, rate limiting per organization/user
- **Web-based Git Operations**: Clone, fetch, push over HTTP/HTTPS with firewall-friendly access
- **🆕 Advanced Web Integration**: Deep integration with web interfaces, APIs, and webhook systems
- **🆕 Production-Grade Features**: Monitoring, metrics, audit logging, graceful degradation
- **🆕 CDN and Storage Optimization**: Multi-tier storage, object versioning, automated cleanup

This provides enterprise-grade Git hosting capabilities that complement the SSH server and scale to thousands of users and repositories following Gitea's production architecture patterns.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

🆕 **Enterprise HTTP Git Server Requirements (Gitea Production Patterns)**:

1. **🆕 Enhanced Git Smart HTTP Protocol (v1/v2 Support)**:
   ```bash
   # Git Protocol v1 (standard)
   GET  /owner/repo.git/info/refs?service=git-upload-pack
   POST /owner/repo.git/git-upload-pack
   POST /owner/repo.git/git-receive-pack
   GET  /owner/repo.git/objects/[hash-path]
   GET  /owner/repo.git/HEAD
   
   # 🆕 Git Protocol v2 (enhanced performance)
   GET  /owner/repo.git/info/refs?service=git-upload-pack&version=2
   POST /owner/repo.git/git-upload-pack (with protocol v2 request format)
   
   # 🆕 Enhanced endpoints for metadata and caching
   GET  /owner/repo.git/info/refs?service=git-upload-pack&want-ref=refs/heads/main
   GET  /owner/repo.git/info/attributes
   GET  /owner/repo.git/info/sparse-checkout
   ```

2. **🆕 Advanced Git LFS Protocol with Batch Extensions**:
   ```bash
   # Standard LFS API v1
   POST /owner/repo.git/info/lfs/objects/batch
   GET  /owner/repo.git/info/lfs/objects/{oid}
   PUT  /owner/repo.git/info/lfs/objects/{oid}
   
   # 🆕 LFS Batch API v2 with advanced features
   POST /owner/repo.git/info/lfs/objects/batch (with transfer adapters)
   GET  /owner/repo.git/info/lfs/objects/{oid}/verify
   PUT  /owner/repo.git/info/lfs/objects/{oid}/upload/{chunk}
   POST /owner/repo.git/info/lfs/objects/{oid}/complete
   
   # 🆕 LFS management and metadata
   GET  /owner/repo.git/info/lfs/locks
   POST /owner/repo.git/info/lfs/locks
   POST /owner/repo.git/info/lfs/locks/{id}/unlock
   GET  /owner/repo.git/info/lfs/size
   ```

3. **🆕 Multi-Tier Authentication System**:
   ```zig
   const AuthenticationMethod = enum {
       http_basic,           // Username:password or token
       bearer_token,         // OAuth/API tokens
       api_key_header,       // X-API-Key header
       ssh_key_over_http,    // SSH key authentication over HTTP
       session_cookie,       // Web session authentication
       organization_token,   // Organization-scoped tokens
       temporary_token,      // Time-limited access tokens
   };
   
   const AuthenticationResult = struct {
       authenticated: bool,
       user_id: u32,
       organization_id: ?u32,
       team_ids: []u32,
       token_scopes: []TokenScope,
       rate_limit_tier: RateLimitTier,
       expires_at: ?i64,
   };
   ```

4. **🆕 Enhanced Repository Operations with Team Context**:
   ```zig
   const GitOperation = enum {
       clone,              // Read access
       fetch,              // Read access  
       push,               // Write access
       force_push,         // Admin access
       delete_branch,      // Write access
       create_tag,         // Write access
       delete_tag,         // Admin access
       lfs_upload,         // LFS write access
       lfs_download,       // LFS read access
       lfs_lock,           // LFS lock management
   };
   
   const OperationContext = struct {
       operation: GitOperation,
       repository_path: []const u8,
       user_context: UserContext,
       team_context: ?TeamContext,
       branch_name: ?[]const u8,
       tag_name: ?[]const u8,
       lfs_oid: ?[]const u8,
   };
   ```

5. **🆕 Security Hardening Requirements**:
   - Input validation and sanitization for all Git operations
   - Rate limiting per IP, user, and organization
   - DoS protection with connection limits and timeouts
   - Security headers (HSTS, CSP, X-Frame-Options)
   - Request size limits and upload quotas
   - Malicious payload detection for Git objects

🆕 **Expected Enterprise Client Interactions**:
```bash
# 🆕 Multi-authentication Git operations over HTTPS
git clone https://api-key:token@plue.dev/owner/repo.git
git clone https://org-token:team-token@plue.dev/org/repo.git
git push https://username:password@plue.dev/owner/repo.git

# 🆕 Advanced Git operations with protocol v2
git -c protocol.version=2 clone https://plue.dev/owner/repo.git
git -c protocol.version=2 fetch origin

# 🆕 Enhanced LFS operations with resumable uploads
git lfs push origin main
git lfs pull
git lfs lock path/to/large-file.bin
git lfs unlock path/to/large-file.bin

# 🆕 Organization and team-aware operations
git clone https://team-token@plue.dev/org/private-repo.git
git push --force-with-lease origin feature-branch  # With enhanced security checks

# 🆕 API-driven operations with advanced authentication
curl -H "Authorization: Bearer org-token" \
     -H "X-Organization: myorg" \
     https://plue.dev/api/v1/repos/org/repo/git/refs
```

</input>

<expected_output>

🆕 **Complete Enterprise HTTP Git and LFS Server Providing**:

1. **🆕 Enhanced Git Smart HTTP Server**: Git protocol v1/v2 support with performance optimizations
2. **🆕 Advanced Git LFS Server**: LFS batch API v2 with resumable uploads, chunked transfers, and deduplication
3. **🆕 Multi-Tier Authentication System**: HTTP Basic, Bearer tokens, API keys, SSH-over-HTTP, organization tokens
4. **🆕 Team-Aware Authorization**: Organization/team-based permissions with fine-grained access control
5. **🆕 High-Performance Streaming**: HTTP/2 support, connection pooling, streaming pipelines, caching layers
6. **🆕 Advanced Security Hardening**: DoS protection, input validation, security headers, malicious payload detection
7. **🆕 Enterprise-Grade Rate Limiting**: Per-IP, per-user, per-organization rate limiting with burst protection
8. **🆕 Comprehensive Audit System**: Multi-tier audit logging with organization-level reporting
9. **🆕 Multi-Tier Storage Backends**: File system, cloud storage, CDN integration with object versioning
10. **🆕 Production Monitoring**: Health checks, metrics collection, performance monitoring, graceful degradation

🆕 **Enhanced Enterprise Server Architecture**:
```zig
const GitHttpServer = struct {
    http_server: *zap.Server,
    git_command: *GitCommandWrapper,
    permission_checker: *PermissionChecker,
    auth_manager: *MultiTierAuthManager,
    lfs_storage: *AdvancedLfsStorage,
    rate_limiter: *EnterpriseRateLimiter,
    security_validator: *SecurityValidator,
    performance_monitor: *PerformanceMonitor,
    audit_logger: *AuditLogger,

    pub fn init(allocator: std.mem.Allocator, config: GitHttpConfig) !GitHttpServer;
    pub fn start(self: *GitHttpServer, allocator: std.mem.Allocator) !void;
    
    // 🆕 Enhanced Git Smart HTTP endpoints with protocol v2 support
    pub fn handleInfoRefs(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleInfoRefsV2(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleGitUploadPack(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleGitUploadPackV2(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleGitReceivePack(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    
    // 🆕 Advanced Git LFS endpoints with batch v2 support
    pub fn handleLfsBatch(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleLfsBatchV2(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleLfsUpload(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleLfsChunkedUpload(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleLfsDownload(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleLfsVerify(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleLfsLocks(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    
    // 🆕 Security and monitoring endpoints
    pub fn handleHealthCheck(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleMetrics(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
};

// 🆕 Multi-tier authentication manager
const MultiTierAuthManager = struct {
    basic_auth: *BasicAuthHandler,
    token_auth: *TokenAuthHandler,
    ssh_key_auth: *SshKeyOverHttpHandler,
    organization_auth: *OrganizationAuthHandler,
    
    pub fn authenticate(self: *MultiTierAuthManager, allocator: std.mem.Allocator, req: *zap.Request) !AuthenticationResult;
    pub fn validateTokenScopes(self: *MultiTierAuthManager, allocator: std.mem.Allocator, token: []const u8, required_scopes: []TokenScope) !bool;
    pub fn getOrganizationContext(self: *MultiTierAuthManager, allocator: std.mem.Allocator, user_id: u32, org_name: []const u8) !?OrganizationContext;
};

// 🆕 Advanced LFS storage with deduplication and CDN support
const AdvancedLfsStorage = struct {
    primary_backend: StorageBackend,
    cdn_backend: ?StorageBackend,
    deduplication_enabled: bool,
    versioning_enabled: bool,
    cleanup_scheduler: *CleanupScheduler,
    
    pub fn storeObject(self: *AdvancedLfsStorage, allocator: std.mem.Allocator, oid: []const u8, data: []const u8) !void;
    pub fn storeObjectChunked(self: *AdvancedLfsStorage, allocator: std.mem.Allocator, oid: []const u8, chunk_stream: *ChunkStream) !void;
    pub fn retrieveObject(self: *AdvancedLfsStorage, allocator: std.mem.Allocator, oid: []const u8) ![]u8;
    pub fn getObjectUrl(self: *AdvancedLfsStorage, allocator: std.mem.Allocator, oid: []const u8, operation: LfsOperation) ![]const u8;
    pub fn deduplicateObject(self: *AdvancedLfsStorage, allocator: std.mem.Allocator, oid: []const u8) !DeduplicationResult;
    pub fn scheduleCleanup(self: *AdvancedLfsStorage, allocator: std.mem.Allocator, retention_policy: RetentionPolicy) !void;
};

// 🆕 Enhanced storage backends with CDN integration
const StorageBackend = union(enum) {
    filesystem: struct {
        base_path: []const u8,
        compression_enabled: bool,
        encryption_key: ?[]const u8,
    },
    s3_compatible: struct {
        endpoint: []const u8,
        bucket: []const u8,
        region: []const u8,
        access_key: []const u8,
        secret_key: []const u8,
        cdn_domain: ?[]const u8,
    },
    multi_tier: struct {
        hot_storage: *StorageBackend,
        cold_storage: *StorageBackend,
        archival_storage: *StorageBackend,
        tier_policy: TieringPolicy,
    },
};

// 🆕 Enterprise rate limiting with organization awareness
const EnterpriseRateLimiter = struct {
    ip_limiter: *IpRateLimiter,
    user_limiter: *UserRateLimiter,
    org_limiter: *OrganizationRateLimiter,
    
    pub fn checkRateLimit(self: *EnterpriseRateLimiter, allocator: std.mem.Allocator, context: RateLimitContext) !RateLimitResult;
    pub fn updateLimits(self: *EnterpriseRateLimiter, allocator: std.mem.Allocator, updates: []RateLimitUpdate) !void;
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Use real HTTP clients for testing. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: HTTP Server Foundation and Routing (TDD)</title>

1. **Create HTTP server module structure**
   ```bash
   mkdir -p src/http
   touch src/http/git_server.zig
   touch src/http/lfs_server.zig
   ```

2. **Write tests for basic HTTP routing**
   ```zig
   test "routes Git Smart HTTP requests correctly" {
       const allocator = testing.allocator;
       
       var server = try GitHttpServer.init(allocator, test_config);
       defer server.deinit(allocator);
       
       // Test info/refs routing
       const info_refs_request = try createTestRequest(allocator, .{
           .method = .GET,
           .path = "/owner/repo.git/info/refs",
           .query = "service=git-upload-pack",
       });
       defer info_refs_request.deinit(allocator);
       
       var response = TestResponse.init(allocator);
       defer response.deinit(allocator);
       
       try server.handleRequest(allocator, &info_refs_request, &response);
       
       try testing.expectEqual(@as(u16, 200), response.status_code);
       try testing.expect(std.mem.indexOf(u8, response.headers.get("Content-Type"), "application/x-git") != null);
   }
   
   test "returns 404 for non-existent repository" {
       const allocator = testing.allocator;
       
       var server = try GitHttpServer.init(allocator, test_config);
       defer server.deinit(allocator);
       
       const request = try createTestRequest(allocator, .{
           .method = .GET,
           .path = "/nonexistent/repo.git/info/refs",
           .query = "service=git-upload-pack",
       });
       defer request.deinit(allocator);
       
       var response = TestResponse.init(allocator);
       defer response.deinit(allocator);
       
       try server.handleRequest(allocator, &request, &response);
       try testing.expectEqual(@as(u16, 404), response.status_code);
   }
   ```

3. **Implement basic HTTP server with Zap**
4. **Add Git Smart HTTP route parsing**
5. **Test repository path extraction and validation**

</phase_1>

<phase_2>
<title>Phase 2: Authentication and Authorization (TDD)</title>

1. **Write tests for HTTP authentication**
   ```zig
   test "authenticates HTTP Basic Auth for Git operations" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Create test user with API token
       const user_id = try createTestUser(&db, allocator, .{});
       defer _ = db.deleteUser(allocator, user_id) catch {};
       
       const api_token = try db.createApiToken(allocator, user_id, .{ .scopes = &.{"repo:read"} });
       defer _ = db.revokeApiToken(allocator, api_token.id) catch {};
       
       var server = try GitHttpServer.init(allocator, test_config);
       defer server.deinit(allocator);
       
       const auth_header = try std.fmt.allocPrint(allocator, "Basic {s}", .{
           try base64Encode(allocator, "api-key:" ++ api_token.token)
       });
       defer allocator.free(auth_header);
       
       const request = try createTestRequest(allocator, .{
           .method = .GET,
           .path = "/owner/repo.git/info/refs",
           .headers = &.{.{ .name = "Authorization", .value = auth_header }},
       });
       defer request.deinit(allocator);
       
       const auth_context = try server.authenticateRequest(allocator, &request);
       try testing.expect(auth_context.authenticated);
       try testing.expectEqual(user_id, auth_context.user_id);
   }
   
   test "rejects invalid authentication credentials" {
       // Test invalid credentials rejection
   }
   ```

2. **Implement HTTP authentication manager**
3. **Add Bearer token and API key authentication**
4. **Test authorization integration with permission system**

</phase_2>

<phase_3>
<title>Phase 3: Git Smart HTTP Protocol Implementation (TDD)</title>

1. **Write tests for Git info/refs endpoint**
   ```zig
   test "serves git-upload-pack info/refs correctly" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Create test repository
       const repo_id = try createTestRepository(&db, allocator, .{ .visibility = .public });
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       var server = try GitHttpServer.init(allocator, test_config);
       defer server.deinit(allocator);
       
       const request = try createTestRequest(allocator, .{
           .method = .GET,
           .path = "/owner/repo.git/info/refs",
           .query = "service=git-upload-pack",
       });
       defer request.deinit(allocator);
       
       var response = TestResponse.init(allocator);
       defer response.deinit(allocator);
       
       try server.handleInfoRefs(allocator, &request, &response);
       
       try testing.expectEqual(@as(u16, 200), response.status_code);
       try testing.expectEqualStrings("application/x-git-upload-pack-advertisement", 
           response.headers.get("Content-Type"));
       
       // Verify Git protocol response format
       const body = response.getBody();
       try testing.expect(std.mem.startsWith(u8, body, "001e# service=git-upload-pack\n"));
   }
   
   test "handles git-receive-pack authorization" {
       // Test push authorization with write permissions
   }
   ```

2. **Implement Git Smart HTTP info/refs handler**
3. **Add git-upload-pack and git-receive-pack handlers**
4. **Test Git protocol streaming and chunked responses**

</phase_3>

<phase_4>
<title>Phase 4: Git LFS Batch API Implementation (TDD)</title>

1. **Write tests for LFS batch API**
   ```zig
   test "handles LFS batch request for download" {
       const allocator = testing.allocator;
       
       var server = try GitHttpServer.init(allocator, test_config);
       defer server.deinit(allocator);
       
       const batch_request = LfsBatchRequest{
           .operation = .download,
           .transfers = &.{"basic"},
           .objects = &.{
               .{
                   .oid = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                   .size = 0,
               },
           },
       };
       
       const request_body = try std.json.stringifyAlloc(allocator, batch_request, .{});
       defer allocator.free(request_body);
       
       const request = try createTestRequest(allocator, .{
           .method = .POST,
           .path = "/owner/repo.git/info/lfs/objects/batch",
           .headers = &.{
               .{ .name = "Content-Type", .value = "application/vnd.git-lfs+json" },
               .{ .name = "Accept", .value = "application/vnd.git-lfs+json" },
           },
           .body = request_body,
       });
       defer request.deinit(allocator);
       
       var response = TestResponse.init(allocator);
       defer response.deinit(allocator);
       
       try server.handleLfsBatch(allocator, &request, &response);
       
       try testing.expectEqual(@as(u16, 200), response.status_code);
       
       const batch_response = try std.json.parseFromSlice(LfsBatchResponse, allocator, response.getBody(), .{});
       defer batch_response.deinit();
       
       try testing.expectEqual(@as(usize, 1), batch_response.value.objects.len);
   }
   
   test "handles LFS batch request for upload" {
       // Test LFS upload batch request
   }
   ```

2. **Implement LFS batch API handler**
3. **Add LFS object metadata management**
4. **Test upload and download URL generation**

</phase_4>

<phase_5>
<title>Phase 5: LFS Storage Backend Implementation (TDD)</title>

1. **Write tests for LFS storage operations**
   ```zig
   test "stores and retrieves LFS objects from filesystem" {
       const allocator = testing.allocator;
       
       var tmp_dir = testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       const storage_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
       defer allocator.free(storage_path);
       
       var lfs_storage = try LfsStorage.init(allocator, .{
           .filesystem = .{ .base_path = storage_path },
       });
       defer lfs_storage.deinit(allocator);
       
       const test_data = "Hello, LFS!";
       const oid = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
       
       // Store object
       try lfs_storage.storeObject(allocator, oid, test_data);
       
       // Verify object exists
       try testing.expect(try lfs_storage.objectExists(allocator, oid));
       
       // Retrieve object
       const retrieved_data = try lfs_storage.retrieveObject(allocator, oid);
       defer allocator.free(retrieved_data);
       
       try testing.expectEqualStrings(test_data, retrieved_data);
   }
   
   test "handles LFS object upload and download streams" {
       // Test streaming upload/download for large files
   }
   ```

2. **Implement filesystem storage backend**
3. **Add S3-compatible cloud storage backend**
4. **Test storage backend switching and configuration**

</phase_5>

<phase_6>
<title>Phase 6: Streaming and Performance Optimization (TDD)</title>

1. **Write tests for streaming operations**
   ```zig
   test "streams large Git pack files efficiently" {
       const allocator = testing.allocator;
       
       var server = try GitHttpServer.init(allocator, test_config);
       defer server.deinit(allocator);
       
       // Create large test repository (or simulate large pack)
       const large_pack_size = 10 * 1024 * 1024; // 10MB
       
       const request = try createTestRequest(allocator, .{
           .method = .POST,
           .path = "/owner/repo.git/git-upload-pack",
           .headers = &.{
               .{ .name = "Content-Type", .value = "application/x-git-upload-pack-request" },
           },
       });
       defer request.deinit(allocator);
       
       var response = TestStreamResponse.init(allocator);
       defer response.deinit(allocator);
       
       const start_time = std.time.nanoTimestamp();
       try server.handleGitUploadPack(allocator, &request, &response);
       const duration = std.time.nanoTimestamp() - start_time;
       
       // Verify streaming performance
       const max_duration_ns = 5 * std.time.ns_per_s; // 5 seconds max
       try testing.expect(duration < max_duration_ns);
       
       // Verify response was streamed (not buffered entirely)
       try testing.expect(response.chunks_received > 1);
   }
   ```

2. **Implement streaming response handling**
3. **Add chunked transfer encoding support**
4. **Test memory usage with large files**

</phase_6>

<phase_7>
<title>Phase 7: Rate Limiting and Security (TDD)</title>

1. **Write tests for rate limiting**
   ```zig
   test "rate limits Git operations per IP" {
       const allocator = testing.allocator;
       
       var server = try GitHttpServer.init(allocator, .{
           .rate_limit = .{
               .requests_per_minute = 10,
               .burst_size = 5,
           },
       });
       defer server.deinit(allocator);
       
       const client_ip = "192.168.1.100";
       
       // Make requests up to the limit
       for (0..10) |_| {
           const request = try createTestRequest(allocator, .{
               .method = .GET,
               .path = "/owner/repo.git/info/refs",
               .client_ip = client_ip,
           });
           defer request.deinit(allocator);
           
           var response = TestResponse.init(allocator);
           defer response.deinit(allocator);
           
           try server.handleRequest(allocator, &request, &response);
           try testing.expect(response.status_code < 400);
       }
       
       // Next request should be rate limited
       const rate_limited_request = try createTestRequest(allocator, .{
           .method = .GET,
           .path = "/owner/repo.git/info/refs",
           .client_ip = client_ip,
       });
       defer rate_limited_request.deinit(allocator);
       
       var rate_limited_response = TestResponse.init(allocator);
       defer rate_limited_response.deinit(allocator);
       
       try server.handleRequest(allocator, &rate_limited_request, &rate_limited_response);
       try testing.expectEqual(@as(u16, 429), rate_limited_response.status_code);
   }
   ```

2. **Implement rate limiting system**
3. **Add request validation and sanitization**
4. **Test security headers and HTTPS enforcement**

</phase_7>

<phase_8>
<title>Phase 8: Integration and Production Features (TDD)</title>

1. **Write tests for server integration**
2. **Implement comprehensive audit logging**
3. **Add health check and metrics endpoints**
4. **Test graceful shutdown and connection draining**

</phase_8>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **HTTP Client Testing**: Use real HTTP clients (curl, Git client) for integration tests
- **Protocol Compliance**: Verify Git Smart HTTP and LFS protocol compliance
- **Performance Testing**: Large repository and file handling performance
- **Security Testing**: Authentication bypass attempts and injection attacks
- **Concurrency Testing**: Concurrent Git operations and LFS uploads/downloads
- **Storage Testing**: Multiple storage backend configurations

</testing_requirements>

<success_criteria>

1. **All tests pass**: Complete enterprise HTTP Git and LFS functionality
2. **🆕 Protocol compliance**: Full Git Smart HTTP v1/v2 and LFS API v1/v2 support
3. **🆕 Multi-tier authentication**: All authentication methods working with organization/team context
4. **🆕 Advanced LFS features**: Resumable uploads, chunked transfers, deduplication, and CDN integration
5. **🆕 Performance optimization**: HTTP/2 support, streaming pipelines, connection pooling
6. **🆕 Security hardening**: Input validation, DoS protection, security headers, malicious payload detection
7. **🆕 Enterprise rate limiting**: Per-IP, per-user, per-organization rate limiting with burst protection
8. **Integration**: Seamless integration with permission system, database, and team management
9. **Scalability**: Support thousands of concurrent operations and high throughput
10. **🆕 Storage flexibility**: Multi-tier storage backends with object versioning and automated cleanup
11. **🆕 Production monitoring**: Health checks, metrics collection, audit logging, graceful degradation
12. **🆕 Battle-tested patterns**: Implementation following Gitea's production-proven architecture

</success_criteria>

</quality_assurance>

<reference_implementations>

**🆕 Enhanced with Gitea Production Patterns:**
- [🆕 Gitea HTTP Git Server](https://github.com/go-gitea/gitea/tree/main/routers/web/repo)
- [🆕 Gitea LFS Implementation](https://github.com/go-gitea/gitea/tree/main/services/lfs)
- [🆕 Gitea Authentication Middleware](https://github.com/go-gitea/gitea/tree/main/services/auth)
- [🆕 Gitea Organization/Team Integration](https://github.com/go-gitea/gitea/tree/main/models/organization)
- [🆕 Gitea Rate Limiting](https://github.com/go-gitea/gitea/tree/main/modules/web/middleware)
- [🆕 Gitea Git Protocol v2](https://github.com/go-gitea/gitea/blob/main/services/repository/files/git.go)
- **Git Smart HTTP**: Official Git documentation and protocol specification
- **Git LFS API**: GitHub LFS API specification and reference implementation
- **GitLab Git HTTP**: Enterprise-grade HTTP Git server implementation

**🆕 Key Gitea Patterns Implemented:**
- Multi-tier authentication with organization/team context
- Git protocol v2 support with performance optimizations
- Advanced LFS batch API with resumable uploads and deduplication
- Enterprise-grade rate limiting with multi-level controls
- Security hardening with input validation and DoS protection
- Multi-tier storage backends with CDN integration and object versioning

</reference_implementations>