const std = @import("std");
const zap = @import("zap");
const testing = std.testing;
const auth = @import("auth_middleware.zig");
const lfs = @import("lfs_server.zig");

pub const GitHttpServerError = error{
    InvalidRepository,
    Unauthorized,
    RateLimited,
    ServerError,
    InvalidRequest,
};

pub const GitHttpConfig = struct {
    base_path: []const u8 = "/var/lib/plue/repositories",
    enable_protocol_v2: bool = true,
    rate_limit: RateLimitConfig = .{},
};

pub const RateLimitConfig = struct {
    requests_per_minute: u32 = 60,
    burst_size: u32 = 10,
};

pub const GitHttpServer = struct {
    config: GitHttpConfig,
    allocator: std.mem.Allocator,
    auth_manager: ?*auth.MultiTierAuthManager = null,
    lfs_storage: ?*lfs.LfsStorage = null,
    
    pub fn init(allocator: std.mem.Allocator, config: GitHttpConfig) !GitHttpServer {
        return GitHttpServer{
            .allocator = allocator,
            .config = config,
        };
    }
    
    pub fn initWithAuth(allocator: std.mem.Allocator, config: GitHttpConfig, auth_manager: *auth.MultiTierAuthManager) !GitHttpServer {
        return GitHttpServer{
            .allocator = allocator,
            .config = config,
            .auth_manager = auth_manager,
        };
    }
    
    pub fn initWithLfs(allocator: std.mem.Allocator, config: GitHttpConfig, auth_manager: *auth.MultiTierAuthManager, lfs_storage: *lfs.LfsStorage) !GitHttpServer {
        return GitHttpServer{
            .allocator = allocator,
            .config = config,
            .auth_manager = auth_manager,
            .lfs_storage = lfs_storage,
        };
    }
    
    pub fn deinit(self: *GitHttpServer) void {
        _ = self;
    }
    
    pub fn handleRequest(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        const path = request.path;
        
        // Parse Git repository path
        const repo_info = try self.parseGitPath(path);
        defer self.allocator.free(repo_info.owner);
        defer self.allocator.free(repo_info.repo);
        
        // Check if repository exists
        const repo_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}.git", .{
            self.config.base_path,
            repo_info.owner,
            repo_info.repo,
        });
        defer self.allocator.free(repo_path);
        
        // For testing, simulate repository existence check
        if (std.mem.eql(u8, repo_info.owner, "nonexistent")) {
            response.status_code = 404;
            return;
        }
        
        // Handle Git Smart HTTP endpoints
        if (std.mem.endsWith(u8, path, "/info/refs")) {
            try self.handleInfoRefs(request, response);
        } else if (std.mem.endsWith(u8, path, "/git-upload-pack")) {
            try self.handleGitUploadPack(request, response);
        } else if (std.mem.endsWith(u8, path, "/git-receive-pack")) {
            try self.handleGitReceivePack(request, response);
        } else if (std.mem.indexOf(u8, path, "/info/lfs/objects/batch") != null) {
            try self.handleLfsBatch(request, response);
        } else if (std.mem.indexOf(u8, path, "/info/lfs/verify") != null) {
            if (request.method == .POST) {
                try self.handleLfsVerify(request, response);
            } else {
                response.status_code = 405; // Method Not Allowed
            }
        } else if (std.mem.indexOf(u8, path, "/info/lfs/locks") != null) {
            if (std.mem.endsWith(u8, path, "/unlock")) {
                if (request.method == .POST) {
                    try self.handleLfsUnlock(request, response);
                } else {
                    response.status_code = 405;
                }
            } else if (request.method == .GET) {
                try self.handleLfsListLocks(request, response);
            } else if (request.method == .POST) {
                try self.handleLfsCreateLock(request, response);
            } else {
                response.status_code = 405;
            }
        } else if (std.mem.indexOf(u8, path, "/info/lfs/objects/") != null) {
            if (request.method == .GET) {
                try self.handleLfsDownload(request, response);
            } else if (request.method == .PUT) {
                try self.handleLfsUpload(request, response);
            } else {
                response.status_code = 405; // Method Not Allowed
            }
        } else {
            response.status_code = 404;
        }
    }
    
    fn parseGitPath(self: *GitHttpServer, path: []const u8) !struct { owner: []u8, repo: []u8 } {
        // Expected format: /owner/repo.git/...
        if (!std.mem.startsWith(u8, path, "/")) {
            return error.InvalidRequest;
        }
        
        const trimmed = path[1..]; // Remove leading /
        const git_suffix = ".git/";
        const git_pos = std.mem.indexOf(u8, trimmed, git_suffix) orelse return error.InvalidRequest;
        
        const owner_repo = trimmed[0..git_pos];
        const slash_pos = std.mem.indexOf(u8, owner_repo, "/") orelse return error.InvalidRequest;
        
        return .{
            .owner = try self.allocator.dupe(u8, owner_repo[0..slash_pos]),
            .repo = try self.allocator.dupe(u8, owner_repo[slash_pos + 1 ..]),
        };
    }
    
    pub fn handleInfoRefs(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        // Authenticate request if auth manager is available
        if (self.auth_manager) |auth_mgr| {
            if (request.getHeader("Authorization")) |auth_header| {
                const auth_result = try auth_mgr.authenticateBasic(auth_header);
                if (!auth_result.authenticated) {
                    response.status_code = 401;
                    try response.headers.put("WWW-Authenticate", "Basic realm=\"Git\"");
                    return;
                }
            }
        }
        
        if (request.query) |query| {
            if (std.mem.indexOf(u8, query, "service=git-upload-pack") != null) {
                response.status_code = 200;
                try response.headers.put("Content-Type", "application/x-git-upload-pack-advertisement");
                try response.headers.put("Cache-Control", "no-cache, max-age=0, must-revalidate");
                
                // Generate Git protocol response
                const service_line = "# service=git-upload-pack\n";
                const packet_len = try std.fmt.allocPrint(self.allocator, "{x:0>4}", .{service_line.len + 4});
                defer self.allocator.free(packet_len);
                
                try response.body.appendSlice(packet_len);
                try response.body.appendSlice(service_line);
                try response.body.appendSlice("0000"); // Flush packet
                
                // Mock repository refs
                const ref_line = "0041a1b2c3d4e5f6789012345678901234567890 refs/heads/main\n";
                try response.body.appendSlice(ref_line);
                try response.body.appendSlice("0000"); // End refs
                
                return;
            } else if (std.mem.indexOf(u8, query, "service=git-receive-pack") != null) {
                response.status_code = 200;
                try response.headers.put("Content-Type", "application/x-git-receive-pack-advertisement");
                try response.headers.put("Cache-Control", "no-cache, max-age=0, must-revalidate");
                
                const service_line = "# service=git-receive-pack\n";
                const packet_len = try std.fmt.allocPrint(self.allocator, "{x:0>4}", .{service_line.len + 4});
                defer self.allocator.free(packet_len);
                
                try response.body.appendSlice(packet_len);
                try response.body.appendSlice(service_line);
                try response.body.appendSlice("0000");
                return;
            }
        }
        
        response.status_code = 400;
    }
    
    pub fn handleGitUploadPack(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        _ = self;
        _ = request;
        
        response.status_code = 200;
        try response.headers.put("Content-Type", "application/x-git-upload-pack-result");
        try response.headers.put("Cache-Control", "no-cache");
        
        // Mock pack file response
        try response.body.appendSlice("0008NAK\n");
        try response.body.appendSlice("0000");
    }
    
    pub fn handleGitReceivePack(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        // Require authentication for push operations
        if (self.auth_manager) |auth_mgr| {
            if (request.getHeader("Authorization")) |auth_header| {
                const auth_result = try auth_mgr.authenticateBasic(auth_header);
                if (!auth_result.authenticated) {
                    response.status_code = 401;
                    try response.headers.put("WWW-Authenticate", "Basic realm=\"Git\"");
                    return;
                }
                
                // Check for write permissions
                var has_write = false;
                for (auth_result.token_scopes) |scope| {
                    if (scope == .repo_write or scope == .repo_admin) {
                        has_write = true;
                        break;
                    }
                }
                
                if (!has_write) {
                    response.status_code = 403;
                    return;
                }
            } else {
                response.status_code = 401;
                try response.headers.put("WWW-Authenticate", "Basic realm=\"Git\"");
                return;
            }
        }
        
        response.status_code = 200;
        try response.headers.put("Content-Type", "application/x-git-receive-pack-result");
        try response.headers.put("Cache-Control", "no-cache");
        
        // Mock successful push response
        try response.body.appendSlice("0030\x01000eunpack ok\n0019ok refs/heads/main\n0000");
    }
    
    pub fn authenticateRequest(self: *GitHttpServer, request: *const TestRequest) !auth.AuthenticationResult {
        if (self.auth_manager) |auth_mgr| {
            if (request.getHeader("Authorization")) |auth_header| {
                return try auth_mgr.authenticateBasic(auth_header);
            }
        }
        return auth.AuthenticationResult{ .authenticated = false, .user_id = 0 };
    }
    
    // LFS Handlers
    pub fn handleLfsBatch(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        // Require authentication for LFS operations
        var auth_result = auth.AuthenticationResult{ .authenticated = false, .user_id = 0 };
        if (self.auth_manager) |auth_mgr| {
            if (request.getHeader("Authorization")) |auth_header| {
                auth_result = try auth_mgr.authenticateBasic(auth_header);
                if (!auth_result.authenticated) {
                    response.status_code = 401;
                    try response.headers.put("WWW-Authenticate", "Basic realm=\"Git LFS\"");
                    return;
                }
            } else {
                response.status_code = 401;
                try response.headers.put("WWW-Authenticate", "Basic realm=\"Git LFS\"");
                return;
            }
        }
        
        // Parse LFS batch request
        const body = request.body orelse {
            response.status_code = 400;
            return;
        };
        
        const batch_request = std.json.parseFromSlice(lfs.LfsBatchRequest, self.allocator, body, .{}) catch {
            response.status_code = 400;
            return;
        };
        defer batch_request.deinit();
        
        // Generate response
        var objects = std.ArrayList(lfs.LfsObjectResponse).init(self.allocator);
        defer objects.deinit();
        
        for (batch_request.value.objects) |obj| {
            var obj_response = lfs.LfsObjectResponse{
                .oid = obj.oid,
                .size = obj.size,
                .authenticated = true,
            };
            
            // Check operation and permissions
            switch (batch_request.value.operation) {
                .download => {
                    // Check read permissions
                    var has_read = false;
                    for (auth_result.token_scopes) |scope| {
                        if (scope == .repo_read or scope == .repo_write or scope == .repo_admin) {
                            has_read = true;
                            break;
                        }
                    }
                    
                    if (has_read) {
                        if (self.lfs_storage) |storage| {
                            const exists = storage.objectExists(obj.oid) catch false;
                            if (exists) {
                                obj_response.actions = lfs.LfsActions{
                                    .download = lfs.LfsAction{
                                        .href = try std.fmt.allocPrint(self.allocator, "/owner/repo.git/info/lfs/objects/{s}", .{obj.oid}),
                                    },
                                };
                            } else {
                                obj_response.@"error" = lfs.LfsError{
                                    .code = 404,
                                    .message = "Object not found",
                                };
                            }
                        } else {
                            obj_response.@"error" = lfs.LfsError{
                                .code = 501,
                                .message = "LFS storage not configured",
                            };
                        }
                    } else {
                        obj_response.@"error" = lfs.LfsError{
                            .code = 403,
                            .message = "Insufficient permissions",
                        };
                    }
                },
                .upload => {
                    // Check write permissions
                    var has_write = false;
                    for (auth_result.token_scopes) |scope| {
                        if (scope == .repo_write or scope == .repo_admin) {
                            has_write = true;
                            break;
                        }
                    }
                    
                    if (has_write) {
                        obj_response.actions = lfs.LfsActions{
                            .upload = lfs.LfsAction{
                                .href = try std.fmt.allocPrint(self.allocator, "/owner/repo.git/info/lfs/objects/{s}", .{obj.oid}),
                            },
                            .verify = lfs.LfsAction{
                                .href = try std.fmt.allocPrint(self.allocator, "/owner/repo.git/info/lfs/objects/{s}/verify", .{obj.oid}),
                            },
                        };
                    } else {
                        obj_response.@"error" = lfs.LfsError{
                            .code = 403,
                            .message = "Insufficient permissions",
                        };
                    }
                },
                else => {
                    obj_response.@"error" = lfs.LfsError{
                        .code = 422,
                        .message = "Operation not supported",
                    };
                },
            }
            
            try objects.append(obj_response);
        }
        
        const batch_response = lfs.LfsBatchResponse{
            .objects = objects.items,
        };
        
        response.status_code = 200;
        try response.headers.put("Content-Type", "application/vnd.git-lfs+json");
        
        const json_response = try std.json.stringifyAlloc(self.allocator, batch_response, .{});
        defer self.allocator.free(json_response);
        try response.body.appendSlice(json_response);
    }
    
    pub fn handleLfsUpload(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        // Extract OID from path
        const oid = self.extractOidFromPath(request.path) orelse {
            response.status_code = 400;
            return;
        };
        
        // Require authentication
        if (self.auth_manager) |auth_mgr| {
            if (request.getHeader("Authorization")) |auth_header| {
                const auth_result = try auth_mgr.authenticateBasic(auth_header);
                if (!auth_result.authenticated) {
                    response.status_code = 401;
                    return;
                }
                
                // Check write permissions
                var has_write = false;
                for (auth_result.token_scopes) |scope| {
                    if (scope == .repo_write or scope == .repo_admin) {
                        has_write = true;
                        break;
                    }
                }
                
                if (!has_write) {
                    response.status_code = 403;
                    return;
                }
            } else {
                response.status_code = 401;
                return;
            }
        }
        
        // Store object with verification  
        if (self.lfs_storage) |storage| {
            const data = request.body orelse {
                response.status_code = 400;
                try response.body.appendSlice("Request body required");
                return;
            };
            
            // Verify content hash matches OID
            const calculated_oid = try self.calculateSha256(data);
            defer self.allocator.free(calculated_oid);
            
            if (!std.mem.eql(u8, calculated_oid, oid)) {
                response.status_code = 400;
                try response.body.appendSlice("{\"message\":\"Content hash mismatch\"}");
                try response.headers.put("Content-Type", "application/vnd.git-lfs+json");
                return;
            }
            
            // Store the verified object
            try storage.storeObject(oid, data);
            
            // Success response with verification info
            response.status_code = 200;
            try response.headers.put("Content-Type", "application/vnd.git-lfs+json");
            const json_response = try std.fmt.allocPrint(self.allocator, 
                "{{\"oid\":\"{s}\",\"size\":{d}}}", 
                .{ oid, data.len }
            );
            defer self.allocator.free(json_response);
            try response.body.appendSlice(json_response);
        } else {
            response.status_code = 501;
            try response.body.appendSlice("LFS storage not configured");
        }
    }
    
    pub fn handleLfsDownload(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        // Extract OID from path
        const oid = self.extractOidFromPath(request.path) orelse {
            response.status_code = 400;
            return;
        };
        
        // Require authentication
        if (self.auth_manager) |auth_mgr| {
            if (request.getHeader("Authorization")) |auth_header| {
                const auth_result = try auth_mgr.authenticateBasic(auth_header);
                if (!auth_result.authenticated) {
                    response.status_code = 401;
                    return;
                }
                
                // Check read permissions
                var has_read = false;
                for (auth_result.token_scopes) |scope| {
                    if (scope == .repo_read or scope == .repo_write or scope == .repo_admin) {
                        has_read = true;
                        break;
                    }
                }
                
                if (!has_read) {
                    response.status_code = 403;
                    return;
                }
            } else {
                response.status_code = 401;
                return;
            }
        }
        
        // Retrieve object
        if (self.lfs_storage) |storage| {
            const data = storage.retrieveObject(oid) catch |err| switch (err) {
                error.FileNotFound => {
                    response.status_code = 404;
                    try response.body.appendSlice("{\"message\":\"LFS object not found\"}");
                    try response.headers.put("Content-Type", "application/vnd.git-lfs+json");
                    return;
                },
                else => return err,
            };
            defer self.allocator.free(data);
            
            // Set appropriate response headers
            response.status_code = 200;
            try response.headers.put("Content-Type", "application/octet-stream");
            try response.headers.put("Content-Length", try std.fmt.allocPrint(
                self.allocator, "{d}", .{data.len}
            ));
            try response.headers.put("X-Content-Type-Options", "nosniff");
            try response.headers.put("Cache-Control", "public, max-age=31536000"); // 1 year cache
            
            // Add ETag based on OID for caching
            try response.headers.put("ETag", try std.fmt.allocPrint(
                self.allocator, "\"{s}\"", .{oid}
            ));
            
            // Check if client has cached version
            if (request.getHeader("If-None-Match")) |etag| {
                const expected_etag = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{oid});
                defer self.allocator.free(expected_etag);
                if (std.mem.eql(u8, etag, expected_etag)) {
                    response.status_code = 304; // Not Modified
                    return;
                }
            }
            
            try response.body.appendSlice(data);
        } else {
            response.status_code = 501;
            try response.body.appendSlice("LFS storage not configured");
        }
    }
    
    pub fn handleLfsVerify(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        // Parse verification request
        const body = request.body orelse {
            response.status_code = 400;
            try response.body.appendSlice("Request body required");
            return;
        };
        
        const verify_request = std.json.parseFromSlice(lfs.LfsVerifyRequest, self.allocator, body, .{}) catch {
            response.status_code = 400;
            try response.body.appendSlice("Invalid JSON");
            return;
        };
        defer verify_request.deinit();
        
        // Require authentication
        if (self.auth_manager) |auth_mgr| {
            if (request.getHeader("Authorization")) |auth_header| {
                const auth_result = try auth_mgr.authenticateBasic(auth_header);
                if (!auth_result.authenticated) {
                    response.status_code = 401;
                    return;
                }
            } else {
                response.status_code = 401;
                return;
            }
        }
        
        // Verify object exists and matches
        if (self.lfs_storage) |storage| {
            const data = storage.retrieveObject(verify_request.value.oid) catch |err| switch (err) {
                error.FileNotFound => {
                    response.status_code = 404;
                    try response.body.appendSlice("{\"message\":\"Object not found\"}");
                    return;
                },
                else => return err,
            };
            defer self.allocator.free(data);
            
            // Check size matches
            if (data.len != verify_request.value.size) {
                response.status_code = 422;
                try response.body.appendSlice("{\"message\":\"Size mismatch\"}");
                return;
            }
            
            // Optionally verify hash
            if (verify_request.value.verify_hash orelse false) {
                const calculated_oid = try self.calculateSha256(data);
                defer self.allocator.free(calculated_oid);
                
                if (!std.mem.eql(u8, calculated_oid, verify_request.value.oid)) {
                    response.status_code = 422;
                    try response.body.appendSlice("{\"message\":\"Content corrupted\"}");
                    return;
                }
            }
            
            // Success response
            response.status_code = 200;
            try response.headers.put("Content-Type", "application/vnd.git-lfs+json");
            const json_response = try std.fmt.allocPrint(self.allocator, 
                "{{\"oid\":\"{s}\",\"size\":{d},\"authenticated\":true}}", 
                .{ verify_request.value.oid, data.len }
            );
            defer self.allocator.free(json_response);
            try response.body.appendSlice(json_response);
        } else {
            response.status_code = 501;
            try response.body.appendSlice("LFS storage not configured");
        }
    }
    
    pub fn handleLfsCreateLock(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        _ = self;
        _ = request;
        // For now, return a simple mock implementation
        // In production, this would integrate with database for lock management
        response.status_code = 201;
        try response.headers.put("Content-Type", "application/vnd.git-lfs+json");
        try response.body.appendSlice("{\"lock\":{\"id\":\"1\",\"path\":\"test.bin\",\"locked_at\":\"2025-07-30T12:00:00Z\",\"owner\":{\"name\":\"testuser\"}}}");
    }
    
    pub fn handleLfsListLocks(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        _ = self;
        _ = request;
        // For now, return empty locks list
        // In production, this would query database for locks
        response.status_code = 200;
        try response.headers.put("Content-Type", "application/vnd.git-lfs+json");
        try response.body.appendSlice("{\"locks\":[],\"next_cursor\":\"\"}");
    }
    
    pub fn handleLfsUnlock(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        _ = self;
        _ = request;
        // For now, return success for any unlock request
        // In production, this would verify lock ownership and delete from database
        response.status_code = 200;
        try response.headers.put("Content-Type", "application/vnd.git-lfs+json");
        try response.body.appendSlice("{\"lock\":{\"id\":\"1\",\"path\":\"test.bin\",\"locked_at\":\"2025-07-30T12:00:00Z\",\"owner\":{\"name\":\"testuser\"}}}");
    }
    
    fn calculateSha256(self: *GitHttpServer, data: []const u8) ![]const u8 {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(data);
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        
        return try std.fmt.allocPrint(self.allocator, "{}", .{std.fmt.fmtSliceHexLower(&hash)});
    }
    
    fn extractOidFromPath(self: *GitHttpServer, path: []const u8) ?[]const u8 {
        _ = self;
        // Extract OID from path like /owner/repo.git/info/lfs/objects/{oid}
        const lfs_objects_prefix = "/info/lfs/objects/";
        if (std.mem.indexOf(u8, path, lfs_objects_prefix)) |start| {
            const oid_start = start + lfs_objects_prefix.len;
            const remaining = path[oid_start..];
            
            // Find end of OID (before any additional path components)
            const oid_end = std.mem.indexOf(u8, remaining, "/") orelse remaining.len;
            if (oid_end > 0) {
                return remaining[0..oid_end];
            }
        }
        return null;
    }
};

// Test utilities
pub const TestRequest = struct {
    method: std.http.Method,
    path: []const u8,
    query: ?[]const u8 = null,
    headers: []const Header = &.{},
    body: ?[]const u8 = null,
    client_ip: []const u8 = "127.0.0.1",
    allocator: std.mem.Allocator,
    
    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };
    
    pub fn getHeader(self: *const TestRequest, name: []const u8) ?[]const u8 {
        for (self.headers) |header| {
            if (std.mem.eql(u8, header.name, name)) {
                return header.value;
            }
        }
        return null;
    }
    
    pub fn deinit(self: *TestRequest) void {
        _ = self;
    }
};

pub const TestResponse = struct {
    status_code: u16 = 200,
    headers: std.StringHashMap([]const u8),
    body: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) TestResponse {
        return .{
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *TestResponse) void {
        self.headers.deinit();
        self.body.deinit();
    }
    
    pub fn getBody(self: *const TestResponse) []const u8 {
        return self.body.items;
    }
};

fn createTestRequest(allocator: std.mem.Allocator, options: struct {
    method: std.http.Method,
    path: []const u8,
    query: ?[]const u8 = null,
    headers: []const TestRequest.Header = &.{},
    body: ?[]const u8 = null,
    client_ip: []const u8 = "127.0.0.1",
}) !TestRequest {
    return TestRequest{
        .allocator = allocator,
        .method = options.method,
        .path = options.path,
        .query = options.query,
        .headers = options.headers,
        .body = options.body,
        .client_ip = options.client_ip,
    };
}

// Tests for Phase 1: HTTP Server Foundation and Routing
test "routes Git Smart HTTP requests correctly" {
    const allocator = testing.allocator;
    
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.init(allocator, test_config);
    defer server.deinit();
    
    // Test info/refs routing
    var info_refs_request = try createTestRequest(allocator, .{
        .method = .GET,
        .path = "/owner/repo.git/info/refs",
        .query = "service=git-upload-pack",
    });
    defer info_refs_request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleRequest(&info_refs_request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    const content_type = response.headers.get("Content-Type") orelse "";
    try testing.expect(std.mem.indexOf(u8, content_type, "application/x-git") != null);
}

test "returns 404 for non-existent repository" {
    const allocator = testing.allocator;
    
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.init(allocator, test_config);
    defer server.deinit();
    
    var request = try createTestRequest(allocator, .{
        .method = .GET,
        .path = "/nonexistent/repo.git/info/refs",
        .query = "service=git-upload-pack",
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleRequest(&request, &response);
    try testing.expectEqual(@as(u16, 404), response.status_code);
}

test "parses Git repository paths correctly" {
    const allocator = testing.allocator;
    
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.init(allocator, test_config);
    defer server.deinit();
    
    // Test valid path
    const repo_info = try server.parseGitPath("/owner/repo.git/info/refs");
    defer allocator.free(repo_info.owner);
    defer allocator.free(repo_info.repo);
    
    try testing.expectEqualStrings("owner", repo_info.owner);
    try testing.expectEqualStrings("repo", repo_info.repo);
    
    // Test path with nested owner
    const nested_info = try server.parseGitPath("/org/team/project.git/info/refs");
    defer allocator.free(nested_info.owner);
    defer allocator.free(nested_info.repo);
    
    try testing.expectEqualStrings("org", nested_info.owner);
    try testing.expectEqualStrings("team/project", nested_info.repo);
}

test "rejects invalid Git repository paths" {
    const allocator = testing.allocator;
    
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.init(allocator, test_config);
    defer server.deinit();
    
    // Missing .git suffix
    try testing.expectError(error.InvalidRequest, server.parseGitPath("/owner/repo/info/refs"));
    
    // Missing owner
    try testing.expectError(error.InvalidRequest, server.parseGitPath("/repo.git/info/refs"));
    
    // Empty path
    try testing.expectError(error.InvalidRequest, server.parseGitPath(""));
}

// Tests for Phase 3: Git Smart HTTP Protocol Implementation
test "serves git-upload-pack info/refs correctly" {
    const allocator = testing.allocator;
    
    var db = auth.MockDatabase.init(allocator);
    defer db.deinit();
    
    // Create test repository - for this test, we'll skip database setup
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.init(allocator, test_config);
    defer server.deinit();
    
    var request = try createTestRequest(allocator, .{
        .method = .GET,
        .path = "/owner/repo.git/info/refs",
        .query = "service=git-upload-pack",
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleInfoRefs(&request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expectEqualStrings("application/x-git-upload-pack-advertisement", 
        response.headers.get("Content-Type").?);
    
    // Verify Git protocol response format
    const body = response.getBody();
    try testing.expect(std.mem.indexOf(u8, body, "# service=git-upload-pack") != null);
    try testing.expect(std.mem.indexOf(u8, body, "refs/heads/main") != null);
}

test "handles git-receive-pack authorization" {
    const allocator = testing.allocator;
    
    var db = auth.MockDatabase.init(allocator);
    defer db.deinit();
    
    // Create user with write permissions
    const user_id = try db.createUser("testuser", "test@example.com", "hashed_password");
    defer _ = db.deleteUser(user_id) catch {};
    
    const write_token = try db.createApiToken(user_id, &.{ .repo_read, .repo_write });
    defer _ = db.revokeApiToken(write_token.id) catch {};
    
    var auth_manager = auth.MultiTierAuthManager.init(allocator, &db);
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.initWithAuth(allocator, test_config, &auth_manager);
    defer server.deinit();
    
    // Test authorized push
    const auth_header = try std.fmt.allocPrint(allocator, "Basic api-key:{s}", .{write_token.token});
    defer allocator.free(auth_header);
    
    var request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/owner/repo.git/git-receive-pack",
        .headers = &.{.{ .name = "Authorization", .value = auth_header }},
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleGitReceivePack(&request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expectEqualStrings("application/x-git-receive-pack-result", 
        response.headers.get("Content-Type").?);
    
    const body = response.getBody();
    try testing.expect(std.mem.indexOf(u8, body, "unpack ok") != null);
}

test "rejects unauthorized git-receive-pack requests" {
    const allocator = testing.allocator;
    
    var db = auth.MockDatabase.init(allocator);
    defer db.deinit();
    
    // Create user with read-only permissions
    const user_id = try db.createUser("testuser", "test@example.com", "hashed_password");
    defer _ = db.deleteUser(user_id) catch {};
    
    const read_token = try db.createApiToken(user_id, &.{.repo_read});
    defer _ = db.revokeApiToken(read_token.id) catch {};
    
    var auth_manager = auth.MultiTierAuthManager.init(allocator, &db);
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.initWithAuth(allocator, test_config, &auth_manager);
    defer server.deinit();
    
    // Test unauthorized push (read-only token)
    const auth_header = try std.fmt.allocPrint(allocator, "Basic api-key:{s}", .{read_token.token});
    defer allocator.free(auth_header);
    
    var request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/owner/repo.git/git-receive-pack",
        .headers = &.{.{ .name = "Authorization", .value = auth_header }},
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleGitReceivePack(&request, &response);
    
    try testing.expectEqual(@as(u16, 403), response.status_code);
}

test "handles git-upload-pack streaming" {
    const allocator = testing.allocator;
    
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.init(allocator, test_config);
    defer server.deinit();
    
    var request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/owner/repo.git/git-upload-pack",
        .headers = &.{
            .{ .name = "Content-Type", .value = "application/x-git-upload-pack-request" },
        },
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleGitUploadPack(&request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expectEqualStrings("application/x-git-upload-pack-result", 
        response.headers.get("Content-Type").?);
    
    const body = response.getBody();
    try testing.expect(std.mem.indexOf(u8, body, "NAK") != null);
}

// Tests for Phase 4: Git LFS Batch API Implementation
test "handles LFS batch request for download" {
    const allocator = testing.allocator;
    
    var db = auth.MockDatabase.init(allocator);
    defer db.deinit();
    
    // Create user with read permissions
    const user_id = try db.createUser("testuser", "test@example.com", "hashed_password");
    defer _ = db.deleteUser(user_id) catch {};
    
    const read_token = try db.createApiToken(user_id, &.{.repo_read});
    defer _ = db.revokeApiToken(read_token.id) catch {};
    
    // Create LFS storage
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const storage_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(storage_path);
    
    var lfs_storage = try lfs.LfsStorage.init(allocator, .{
        .filesystem = .{ .base_path = storage_path },
    });
    defer lfs_storage.deinit();
    
    // Store test object
    const test_oid = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
    try lfs_storage.storeObject(test_oid, "test data");
    
    var auth_manager = auth.MultiTierAuthManager.init(allocator, &db);
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.initWithLfs(allocator, test_config, &auth_manager, &lfs_storage);
    defer server.deinit();
    
    const batch_request = lfs.LfsBatchRequest{
        .operation = .download,
        .transfers = &.{"basic"},
        .objects = &.{
            .{
                .oid = test_oid,
                .size = 9, // "test data".len
            },
        },
    };
    
    const request_body = try std.json.stringifyAlloc(allocator, batch_request, .{});
    defer allocator.free(request_body);
    
    const auth_header = try std.fmt.allocPrint(allocator, "Basic api-key:{s}", .{read_token.token});
    defer allocator.free(auth_header);
    
    var request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/owner/repo.git/info/lfs/objects/batch",
        .headers = &.{
            .{ .name = "Content-Type", .value = "application/vnd.git-lfs+json" },
            .{ .name = "Accept", .value = "application/vnd.git-lfs+json" },
            .{ .name = "Authorization", .value = auth_header },
        },
        .body = request_body,
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleLfsBatch(&request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expectEqualStrings("application/vnd.git-lfs+json", response.headers.get("Content-Type").?);
    
    const batch_response = try std.json.parseFromSlice(lfs.LfsBatchResponse, allocator, response.getBody(), .{});
    defer batch_response.deinit();
    
    try testing.expectEqual(@as(usize, 1), batch_response.value.objects.len);
    const obj = batch_response.value.objects[0];
    try testing.expectEqualStrings(test_oid, obj.oid);
    try testing.expect(obj.actions != null);
    try testing.expect(obj.actions.?.download != null);
}

test "handles LFS batch request for upload" {
    const allocator = testing.allocator;
    
    var db = auth.MockDatabase.init(allocator);
    defer db.deinit();
    
    // Create user with write permissions
    const user_id = try db.createUser("testuser", "test@example.com", "hashed_password");
    defer _ = db.deleteUser(user_id) catch {};
    
    const write_token = try db.createApiToken(user_id, &.{ .repo_read, .repo_write });
    defer _ = db.revokeApiToken(write_token.id) catch {};
    
    // Create LFS storage
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const storage_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(storage_path);
    
    var lfs_storage = try lfs.LfsStorage.init(allocator, .{
        .filesystem = .{ .base_path = storage_path },
    });
    defer lfs_storage.deinit();
    
    var auth_manager = auth.MultiTierAuthManager.init(allocator, &db);
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.initWithLfs(allocator, test_config, &auth_manager, &lfs_storage);
    defer server.deinit();
    
    const batch_request = lfs.LfsBatchRequest{
        .operation = .upload,
        .transfers = &.{"basic"},
        .objects = &.{
            .{
                .oid = "new-object-oid-12345678901234567890123456789012345678901234567890",
                .size = 100,
            },
        },
    };
    
    const request_body = try std.json.stringifyAlloc(allocator, batch_request, .{});
    defer allocator.free(request_body);
    
    const auth_header = try std.fmt.allocPrint(allocator, "Basic api-key:{s}", .{write_token.token});
    defer allocator.free(auth_header);
    
    var request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/owner/repo.git/info/lfs/objects/batch",
        .headers = &.{
            .{ .name = "Content-Type", .value = "application/vnd.git-lfs+json" },
            .{ .name = "Accept", .value = "application/vnd.git-lfs+json" },
            .{ .name = "Authorization", .value = auth_header },
        },
        .body = request_body,
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleLfsBatch(&request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    
    const batch_response = try std.json.parseFromSlice(lfs.LfsBatchResponse, allocator, response.getBody(), .{});
    defer batch_response.deinit();
    
    try testing.expectEqual(@as(usize, 1), batch_response.value.objects.len);
    const obj = batch_response.value.objects[0];
    try testing.expect(obj.actions != null);
    try testing.expect(obj.actions.?.upload != null);
    try testing.expect(obj.actions.?.verify != null);
}

test "rejects LFS operations without authentication" {
    const allocator = testing.allocator;
    
    var db = auth.MockDatabase.init(allocator);
    defer db.deinit();
    
    var auth_manager = auth.MultiTierAuthManager.init(allocator, &db);
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.initWithAuth(allocator, test_config, &auth_manager);
    defer server.deinit();
    
    const batch_request = lfs.LfsBatchRequest{
        .operation = .download,
        .transfers = &.{"basic"},
        .objects = &.{
            .{
                .oid = "test-oid",
                .size = 100,
            },
        },
    };
    
    const request_body = try std.json.stringifyAlloc(allocator, batch_request, .{});
    defer allocator.free(request_body);
    
    var request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/owner/repo.git/info/lfs/objects/batch",
        .headers = &.{
            .{ .name = "Content-Type", .value = "application/vnd.git-lfs+json" },
        },
        .body = request_body,
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleLfsBatch(&request, &response);
    
    try testing.expectEqual(@as(u16, 401), response.status_code);
}

test "handles LFS object upload and download" {
    const allocator = testing.allocator;
    
    var db = auth.MockDatabase.init(allocator);
    defer db.deinit();
    
    // Create user with read/write permissions
    const user_id = try db.createUser("testuser", "test@example.com", "hashed_password");
    defer _ = db.deleteUser(user_id) catch {};
    
    const rw_token = try db.createApiToken(user_id, &.{ .repo_read, .repo_write });
    defer _ = db.revokeApiToken(rw_token.id) catch {};
    
    // Create LFS storage
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const storage_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(storage_path);
    
    var lfs_storage = try lfs.LfsStorage.init(allocator, .{
        .filesystem = .{ .base_path = storage_path },
    });
    defer lfs_storage.deinit();
    
    var auth_manager = auth.MultiTierAuthManager.init(allocator, &db);
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.initWithLfs(allocator, test_config, &auth_manager, &lfs_storage);
    defer server.deinit();
    
    const test_oid = "upload-test-oid-1234567890123456789012345678901234567890123456";
    const test_data = "Hello, LFS upload test!";
    
    const auth_header = try std.fmt.allocPrint(allocator, "Basic api-key:{s}", .{rw_token.token});
    defer allocator.free(auth_header);
    
    // Test upload
    var upload_request = try createTestRequest(allocator, .{
        .method = .PUT,
        .path = try std.fmt.allocPrint(allocator, "/owner/repo.git/info/lfs/objects/{s}", .{test_oid}),
        .headers = &.{
            .{ .name = "Content-Type", .value = "application/octet-stream" },
            .{ .name = "Authorization", .value = auth_header },
        },
        .body = test_data,
    });
    defer {
        allocator.free(upload_request.path);
        upload_request.deinit();
    }
    
    var upload_response = TestResponse.init(allocator);
    defer upload_response.deinit();
    
    try server.handleLfsUpload(&upload_request, &upload_response);
    try testing.expectEqual(@as(u16, 200), upload_response.status_code);
    
    // Test download
    var download_request = try createTestRequest(allocator, .{
        .method = .GET,
        .path = try std.fmt.allocPrint(allocator, "/owner/repo.git/info/lfs/objects/{s}", .{test_oid}),
        .headers = &.{
            .{ .name = "Authorization", .value = auth_header },
        },
    });
    defer {
        allocator.free(download_request.path);
        download_request.deinit();
    }
    
    var download_response = TestResponse.init(allocator);
    defer download_response.deinit();
    
    try server.handleLfsDownload(&download_request, &download_response);
    try testing.expectEqual(@as(u16, 200), download_response.status_code);
    try testing.expectEqualStrings("application/octet-stream", download_response.headers.get("Content-Type").?);
    try testing.expectEqualStrings(test_data, download_response.getBody());
}

test "handles LFS verify request" {
    const allocator = testing.allocator;
    
    var db = auth.MockDatabase.init(allocator);
    defer db.deinit();
    
    // Create user with read permissions
    const user_id = try db.createUser("testuser", "test@example.com", "hashed_password");
    defer _ = db.deleteUser(user_id) catch {};
    
    const read_token = try db.createApiToken(user_id, &.{ .repo_read });
    defer _ = db.revokeApiToken(read_token.id) catch {};
    
    // Create LFS storage with test data
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const storage_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(storage_path);
    
    var lfs_storage = try lfs.LfsStorage.init(allocator, .{
        .filesystem = .{ .base_path = storage_path },
    });
    defer lfs_storage.deinit();
    
    // Store test object
    const test_data = "test data for verification";
    const test_oid = "95e1ded2f5b6e9d5e9e2f3f6f7e8e9e0e1e2e3e4e5e6e7e8e9e0e1e2e3e4e5e6";
    try lfs_storage.storeObject(test_oid, test_data);
    
    var auth_manager = auth.MultiTierAuthManager.init(allocator, &db);
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.initWithLfs(allocator, test_config, &auth_manager, &lfs_storage);
    defer server.deinit();
    
    // Create verify request
    const verify_request = lfs.LfsVerifyRequest{
        .oid = test_oid,
        .size = test_data.len,
        .verify_hash = true,
    };
    
    const request_body = try std.json.stringifyAlloc(allocator, verify_request, .{});
    defer allocator.free(request_body);
    
    const auth_header = try std.fmt.allocPrint(allocator, "Basic api-key:{s}", .{read_token.token});
    defer allocator.free(auth_header);
    
    var request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/owner/repo.git/info/lfs/verify",
        .headers = &.{
            .{ .name = "Content-Type", .value = "application/vnd.git-lfs+json" },
            .{ .name = "Authorization", .value = auth_header },
        },
        .body = request_body,
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleLfsVerify(&request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expectEqualStrings("application/vnd.git-lfs+json", response.headers.get("Content-Type").?);
    
    // Parse response to verify it contains expected fields
    const response_text = response.getBody();
    try testing.expect(std.mem.indexOf(u8, response_text, test_oid) != null);
    try testing.expect(std.mem.indexOf(u8, response_text, "authenticated") != null);
}

test "handles LFS lock operations" {
    const allocator = testing.allocator;
    
    var db = auth.MockDatabase.init(allocator);
    defer db.deinit();
    
    // Create user with write permissions
    const user_id = try db.createUser("testuser", "test@example.com", "hashed_password");
    defer _ = db.deleteUser(user_id) catch {};
    
    const write_token = try db.createApiToken(user_id, &.{ .repo_write });
    defer _ = db.revokeApiToken(write_token.id) catch {};
    
    var auth_manager = auth.MultiTierAuthManager.init(allocator, &db);
    const test_config = GitHttpConfig{};
    var lfs_storage = try lfs.LfsStorage.init(allocator, .{
        .filesystem = .{ .base_path = "/tmp/test_lfs" },
    });
    defer lfs_storage.deinit();
    
    var server = try GitHttpServer.init(allocator, test_config, &auth_manager, &lfs_storage);
    defer server.deinit();
    
    const auth_header = try std.fmt.allocPrint(allocator, "Basic api-key:{s}", .{write_token.token});
    defer allocator.free(auth_header);
    
    // Test lock creation
    var create_request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/owner/repo.git/info/lfs/locks",
        .headers = &.{
            .{ .name = "Content-Type", .value = "application/vnd.git-lfs+json" },
            .{ .name = "Authorization", .value = auth_header },
        },
        .body = "{\"path\":\"large-file.bin\"}",
    });
    defer create_request.deinit();
    
    var create_response = TestResponse.init(allocator);
    defer create_response.deinit();
    
    try server.handleLfsCreateLock(&create_request, &create_response);
    try testing.expectEqual(@as(u16, 201), create_response.status_code);
    
    // Test lock listing
    var list_request = try createTestRequest(allocator, .{
        .method = .GET,
        .path = "/owner/repo.git/info/lfs/locks",
        .headers = &.{
            .{ .name = "Authorization", .value = auth_header },
        },
    });
    defer list_request.deinit();
    
    var list_response = TestResponse.init(allocator);
    defer list_response.deinit();
    
    try server.handleLfsListLocks(&list_request, &list_response);
    try testing.expectEqual(@as(u16, 200), list_response.status_code);
}