# Implement HTTP Git and LFS Server

<task_definition>
Implement a comprehensive HTTP server that provides Git Smart HTTP protocol support and Git LFS (Large File Storage) capabilities. This server will handle Git operations over HTTPS, serve Git repositories via HTTP/HTTPS, and provide complete LFS functionality for large file management with enterprise-grade performance and security.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig with Zap HTTP framework - https://ziglang.org/documentation/master/
- **Dependencies**: Zap HTTP server, Git command wrapper, Permission system, Database layer
- **Protocols**: Git Smart HTTP, Git LFS API v1
- **Location**: `src/http/git_server.zig`, `src/http/lfs_server.zig`
- **Security**: Authentication, authorization, request validation, rate limiting
- **Performance**: Streaming support, connection pooling, efficient file handling
- **Storage**: File system and cloud storage backends for LFS objects

</technical_requirements>

<business_context>

HTTP Git server enables:

- **Web-based Git Operations**: Clone, fetch, push over HTTP/HTTPS
- **Firewall-friendly Access**: Git operations through standard HTTP ports
- **Large File Support**: Git LFS for managing large binary files
- **Web Integration**: Direct integration with web interfaces and APIs
- **Enterprise Features**: Authentication, authorization, audit logging
- **CDN Integration**: Efficient content delivery for repositories and LFS objects

This complements the SSH server and provides broader accessibility for Git operations.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

HTTP Git server requirements:

1. **Git Smart HTTP Protocol**:
   ```
   GET  /owner/repo.git/info/refs?service=git-upload-pack
   POST /owner/repo.git/git-upload-pack
   POST /owner/repo.git/git-receive-pack
   GET  /owner/repo.git/objects/[hash-path]
   GET  /owner/repo.git/HEAD
   ```

2. **Git LFS Protocol**:
   ```
   POST /owner/repo.git/info/lfs/objects/batch
   GET  /owner/repo.git/info/lfs/objects/{oid}
   PUT  /owner/repo.git/info/lfs/objects/{oid}
   ```

3. **Authentication Methods**:
   - HTTP Basic Authentication
   - Bearer token authentication
   - API key authentication
   - Session-based authentication for web interface

4. **Repository Operations**:
   - Clone (read access)
   - Fetch/Pull (read access)
   - Push (write access)
   - LFS object upload/download

Expected client interactions:
```bash
# Git operations over HTTPS
git clone https://api-key:token@plue.dev/owner/repo.git
git push https://username:password@plue.dev/owner/repo.git

# LFS operations (transparent to user)
git lfs push origin main
git lfs pull
```

</input>

<expected_output>

Complete HTTP Git and LFS server providing:

1. **Git Smart HTTP Server**: Full Git protocol support over HTTP/HTTPS
2. **Git LFS Server**: Large file storage with batch API support
3. **Authentication System**: Multiple authentication methods with session management
4. **Authorization Integration**: Permission-based access control for all operations
5. **Streaming Support**: Efficient handling of large repositories and files
6. **Rate Limiting**: DoS protection and abuse prevention
7. **Audit Logging**: Comprehensive logging for all Git and LFS operations
8. **Storage Backends**: File system and cloud storage for LFS objects

Core server architecture:
```zig
const GitHttpServer = struct {
    http_server: *zap.Server,
    git_command: *GitCommandWrapper,
    permission_checker: *PermissionChecker,
    auth_manager: *AuthManager,
    lfs_storage: *LfsStorage,
    rate_limiter: *RateLimiter,

    pub fn init(allocator: std.mem.Allocator, config: GitHttpConfig) !GitHttpServer;
    pub fn start(self: *GitHttpServer, allocator: std.mem.Allocator) !void;
    
    // Git Smart HTTP endpoints
    pub fn handleInfoRefs(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleGitUploadPack(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleGitReceivePack(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    
    // Git LFS endpoints
    pub fn handleLfsBatch(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleLfsUpload(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleLfsDownload(self: *GitHttpServer, req: *zap.Request, res: *zap.Response) !void;
};

const LfsStorage = struct {
    storage_backend: StorageBackend,
    
    pub fn storeObject(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8, data: []const u8) !void;
    pub fn retrieveObject(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8) ![]u8;
    pub fn objectExists(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8) !bool;
    pub fn deleteObject(self: *LfsStorage, allocator: std.mem.Allocator, oid: []const u8) !void;
};

const StorageBackend = union(enum) {
    filesystem: struct {
        base_path: []const u8,
    },
    s3: struct {
        bucket: []const u8,
        region: []const u8,
        access_key: []const u8,
        secret_key: []const u8,
    },
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

1. **All tests pass**: Complete HTTP Git and LFS functionality
2. **Protocol compliance**: Full Git Smart HTTP and LFS API v1 support
3. **Performance**: Handle large repositories and files efficiently
4. **Security**: Robust authentication and authorization
5. **Integration**: Seamless integration with permission system and database
6. **Scalability**: Support concurrent operations and high throughput
7. **Production ready**: Rate limiting, logging, monitoring, graceful shutdown

</success_criteria>

</quality_assurance>

<reference_implementations>

- **Git Smart HTTP**: Official Git documentation and protocol specification
- **Git LFS API**: GitHub LFS API specification and reference implementation
- **Gitea HTTP Git**: Reference implementation for HTTP Git server
- **GitLab Git HTTP**: Enterprise-grade HTTP Git server implementation

</reference_implementations>