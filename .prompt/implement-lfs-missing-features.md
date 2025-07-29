# Implement LFS Missing Features

## Priority: Low

## Problem
The LFS (Large File Storage) system has several TODO comments indicating missing functionality, particularly in S3 backend operations and filesystem traversal (found in `src/lfs/storage.zig` and related files).

## Current Missing Features

### 1. S3 Backend LIST Operations
```zig
// TODO in src/lfs/storage.zig around line 180:
pub fn listObjects(self: *S3Backend, prefix: []const u8) ![][]const u8 {
    _ = self;
    _ = prefix;
    // TODO: Implement S3 LIST operation
    return &[_][]const u8{};
}
```

### 2. Filesystem Directory Traversal
```zig
// TODO in src/lfs/storage.zig around line 220:
pub fn listDirectory(self: *FilesystemBackend, path: []const u8) ![][]const u8 {
    _ = self;
    _ = path;
    // TODO: Implement safe directory traversal
    return &[_][]const u8{};
}
```

### 3. LFS Garbage Collection
```zig
// TODO: Implement garbage collection for orphaned LFS objects
pub fn garbageCollect(self: *LFSStorage) !GCResult {
    // Find LFS objects not referenced by any commits
    // Remove orphaned objects from storage backends
}
```

## Expected Implementation

### 1. S3 Backend LIST Operations
```zig
pub fn listObjects(self: *S3Backend, allocator: std.mem.Allocator, prefix: []const u8) ![][]const u8 {
    // Construct S3 LIST request
    const host = try std.fmt.allocPrint(allocator, "{s}.s3.{s}.amazonaws.com", .{ self.bucket, self.region });
    defer allocator.free(host);
    
    const path = try std.fmt.allocPrint(allocator, "/?list-type=2&prefix={s}", .{prefix});
    defer allocator.free(path);
    
    // Create HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    
    // Build request with AWS v4 signature
    const auth_header = try self.buildAuthHeader(allocator, "GET", path, "");
    defer allocator.free(auth_header);
    
    var headers = std.http.Headers{ .allocator = allocator };
    defer headers.deinit();
    
    try headers.append("Host", host);
    try headers.append("Authorization", auth_header);
    try headers.append("x-amz-date", try getISO8601DateTime(allocator));
    
    // Make request
    var req = try client.request(.GET, try std.Uri.parse(try std.fmt.allocPrint(allocator, "https://{s}{s}", .{ host, path })), headers, .{});
    defer req.deinit();
    
    try req.start();
    try req.wait();
    
    if (req.response.status != .ok) {
        return LFSError.S3RequestFailed;
    }
    
    // Read response body
    const body = try req.reader().readAllAlloc(allocator, 1024 * 1024); // 1MB limit
    defer allocator.free(body);
    
    // Parse XML response to extract object keys
    return try parseS3ListResponse(allocator, body);
}

fn parseS3ListResponse(allocator: std.mem.Allocator, xml_body: []const u8) ![][]const u8 {
    var objects = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (objects.items) |obj| allocator.free(obj);
        objects.deinit();
    }
    
    // Simple XML parsing for <Key> elements
    var start: usize = 0;
    while (std.mem.indexOf(u8, xml_body[start..], "<Key>")) |key_start| {
        const key_content_start = start + key_start + 5; // Skip "<Key>"
        if (std.mem.indexOf(u8, xml_body[key_content_start..], "</Key>")) |key_end| {
            const key = try allocator.dupe(u8, xml_body[key_content_start..key_content_start + key_end]);
            try objects.append(key);
            start = key_content_start + key_end + 6; // Skip "</Key>"
        } else {
            break;
        }
    }
    
    return objects.toOwnedSlice();
}

fn buildAuthHeader(self: *S3Backend, allocator: std.mem.Allocator, method: []const u8, path: []const u8, payload: []const u8) ![]const u8 {
    // AWS Signature Version 4 implementation
    const service = "s3";
    const datetime = try getISO8601DateTime(allocator);
    defer allocator.free(datetime);
    
    const date = datetime[0..8]; // YYYYMMDD
    
    // Create canonical request
    const canonical_headers = try std.fmt.allocPrint(allocator, 
        "host:{s}.s3.{s}.amazonaws.com\nx-amz-date:{s}\n", 
        .{ self.bucket, self.region, datetime }
    );
    defer allocator.free(canonical_headers);
    
    const signed_headers = "host;x-amz-date";
    const payload_hash = try sha256Hex(allocator, payload);
    defer allocator.free(payload_hash);
    
    const canonical_request = try std.fmt.allocPrint(allocator,
        "{s}\n{s}\n\n{s}\n{s}\n{s}",
        .{ method, path, canonical_headers, signed_headers, payload_hash }
    );
    defer allocator.free(canonical_request);
    
    // Create string to sign
    const scope = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}/aws4_request", .{ date, self.region, service });
    defer allocator.free(scope);
    
    const canonical_request_hash = try sha256Hex(allocator, canonical_request);
    defer allocator.free(canonical_request_hash);
    
    const string_to_sign = try std.fmt.allocPrint(allocator,
        "AWS4-HMAC-SHA256\n{s}\n{s}\n{s}",
        .{ datetime, scope, canonical_request_hash }
    );
    defer allocator.free(string_to_sign);
    
    // Calculate signature
    const signing_key = try getSigningKey(allocator, self.secret_key, date, self.region, service);
    defer allocator.free(signing_key);
    
    const signature = try hmacSha256Hex(allocator, signing_key, string_to_sign);
    defer allocator.free(signature);
    
    // Build authorization header
    return try std.fmt.allocPrint(allocator,
        "AWS4-HMAC-SHA256 Credential={s}/{s}, SignedHeaders={s}, Signature={s}",
        .{ self.access_key, scope, signed_headers, signature }
    );
}
```

### 2. Filesystem Directory Traversal
```zig
pub fn listDirectory(self: *FilesystemBackend, allocator: std.mem.Allocator, path: []const u8) ![][]const u8 {
    // Validate path to prevent directory traversal
    if (std.mem.indexOf(u8, path, "..") != null) {
        return LFSError.InvalidPath;
    }
    
    // Ensure path is within LFS root
    const canonical_path = try std.fs.path.resolve(allocator, &.{ self.root_path, path });
    defer allocator.free(canonical_path);
    
    if (!std.mem.startsWith(u8, canonical_path, self.root_path)) {
        return LFSError.PathTraversalAttempt;
    }
    
    // Open directory
    var dir = std.fs.openDirAbsolute(canonical_path, .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound => return &[_][]const u8{},
            error.NotDir => return LFSError.NotADirectory,
            error.AccessDenied => return LFSError.PermissionDenied,
            else => return err,
        }
    };
    defer dir.close();
    
    var files = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (files.items) |file| allocator.free(file);
        files.deinit();
    }
    
    // Iterate directory entries
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        // Skip hidden files and directories
        if (entry.name[0] == '.') continue;
        
        // Only include regular files (not subdirectories)
        if (entry.kind == .file) {
            const filename = try allocator.dupe(u8, entry.name);
            try files.append(filename);
        }
    }
    
    // Sort files for consistent ordering
    std.sort.insertion([]const u8, files.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);
    
    return files.toOwnedSlice();
}

pub fn getDirectorySize(self: *FilesystemBackend, allocator: std.mem.Allocator, path: []const u8) !u64 {
    const canonical_path = try std.fs.path.resolve(allocator, &.{ self.root_path, path });
    defer allocator.free(canonical_path);
    
    if (!std.mem.startsWith(u8, canonical_path, self.root_path)) {
        return LFSError.PathTraversalAttempt;
    }
    
    var total_size: u64 = 0;
    
    var dir = std.fs.openDirAbsolute(canonical_path, .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound => return 0,
            else => return err,
        }
    };
    defer dir.close();
    
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file) {
            const file_path = try std.fs.path.join(allocator, &.{ canonical_path, entry.name });
            defer allocator.free(file_path);
            
            const stat = std.fs.cwd().statFile(file_path) catch continue;
            total_size += @intCast(stat.size);
        }
    }
    
    return total_size;
}
```

### 3. LFS Garbage Collection
```zig
pub const GCResult = struct {
    objects_scanned: u32,
    objects_deleted: u32,
    bytes_freed: u64,
    errors: [][]const u8,
};

pub fn garbageCollect(self: *LFSStorage, allocator: std.mem.Allocator) !GCResult {
    var result = GCResult{
        .objects_scanned = 0,
        .objects_deleted = 0,
        .bytes_freed = 0,
        .errors = &[_][]const u8{},
    };
    
    var errors = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (errors.items) |err_msg| allocator.free(err_msg);
        errors.deinit();
    }
    
    // Get all LFS objects from storage
    const all_objects = try self.listAllObjects(allocator);
    defer {
        for (all_objects) |obj| allocator.free(obj);
        allocator.free(all_objects);
    }
    
    // Get all LFS object references from Git repositories
    const referenced_objects = try self.getAllReferencedObjects(allocator);
    defer {
        for (referenced_objects) |obj| allocator.free(obj);
        allocator.free(referenced_objects);
    }
    
    // Convert to hash sets for efficient lookup
    var referenced_set = std.StringHashMap(void).init(allocator);
    defer referenced_set.deinit();
    
    for (referenced_objects) |obj_id| {
        try referenced_set.put(obj_id, {});
    }
    
    // Find orphaned objects
    for (all_objects) |obj_id| {
        result.objects_scanned += 1;
        
        if (!referenced_set.contains(obj_id)) {
            // Object is orphaned, delete it
            const size = self.getObjectSize(allocator, obj_id) catch |err| {
                const err_msg = try std.fmt.allocPrint(allocator, "Failed to get size for {s}: {}", .{ obj_id, err });
                try errors.append(err_msg);
                continue;
            };
            
            self.deleteObject(allocator, obj_id) catch |err| {
                const err_msg = try std.fmt.allocPrint(allocator, "Failed to delete {s}: {}", .{ obj_id, err });
                try errors.append(err_msg);
                continue;
            };
            
            result.objects_deleted += 1;
            result.bytes_freed += size;
        }
    }
    
    result.errors = try errors.toOwnedSlice();
    return result;
}

fn getAllReferencedObjects(self: *LFSStorage, allocator: std.mem.Allocator) ![][]const u8 {
    var referenced = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (referenced.items) |obj| allocator.free(obj);
        referenced.deinit();
    }
    
    // Query database for all repositories
    const repos = try self.dao.listAllRepositories(allocator, .{});
    defer {
        for (repos) |repo| {
            allocator.free(repo.name);
            if (repo.description) |d| allocator.free(d);
            allocator.free(repo.default_branch);
        }
        allocator.free(repos);
    }
    
    // For each repository, find LFS object references
    for (repos) |repo| {
        const repo_objects = try self.getRepositoryLFSObjects(allocator, repo.id);
        defer {
            for (repo_objects) |obj| allocator.free(obj);
            allocator.free(repo_objects);
        }
        
        for (repo_objects) |obj_id| {
            try referenced.append(try allocator.dupe(u8, obj_id));
        }
    }
    
    return referenced.toOwnedSlice();
}

fn getRepositoryLFSObjects(self: *LFSStorage, allocator: std.mem.Allocator, repo_id: i64) ![][]const u8 {
    // This would scan Git repository for .gitattributes files with LFS patterns
    // and then find all LFS pointer files in the repository
    var objects = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (objects.items) |obj| allocator.free(obj);
        objects.deinit();
    }
    
    // Get repository path
    const repo = try self.dao.getRepository(allocator, repo_id);
    defer if (repo) |r| {
        allocator.free(r.name);
        if (r.description) |d| allocator.free(d);
        allocator.free(r.default_branch);
    };
    
    if (repo == null) return &[_][]const u8{};
    
    const repo_path = try std.fmt.allocPrint(allocator, "{s}/{s}.git", .{ self.git_root_path, repo.?.name });
    defer allocator.free(repo_path);
    
    // Use git command to find LFS objects
    const result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "-C", repo_path, "lfs", "ls-files", "--all" },
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    
    if (result.term.Exited != 0) {
        // No LFS files or git lfs not available
        return &[_][]const u8{};
    }
    
    // Parse git lfs ls-files output
    var lines = std.mem.split(u8, result.stdout, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        
        // Extract OID from git lfs ls-files output format
        if (std.mem.indexOf(u8, line, " - ")) |separator| {
            const oid = line[0..separator];
            if (oid.len == 64) { // SHA-256 hash length
                try objects.append(try allocator.dupe(u8, oid));
            }
        }
    }
    
    return objects.toOwnedSlice();
}
```

### 4. LFS Bandwidth Tracking
```zig
pub const BandwidthStats = struct {
    uploads_bytes: u64,
    downloads_bytes: u64,
    uploads_count: u32,
    downloads_count: u32,
    period_start: i64,
    period_end: i64,
};

pub fn trackBandwidth(self: *LFSStorage, allocator: std.mem.Allocator, operation: enum { upload, download }, bytes: u64) !void {
    const timestamp = std.time.timestamp();
    
    // Insert bandwidth record
    try self.dao.insertBandwidthRecord(allocator, .{
        .operation = switch (operation) {
            .upload => "upload",
            .download => "download",
        },
        .bytes = bytes,
        .timestamp = timestamp,
    });
}

pub fn getBandwidthStats(self: *LFSStorage, allocator: std.mem.Allocator, start_time: i64, end_time: i64) !BandwidthStats {
    return try self.dao.getBandwidthStats(allocator, start_time, end_time);
}
```

## Helper Functions Needed
```zig
fn getISO8601DateTime(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    const epoch_seconds = @as(u64, @intCast(timestamp));
    const datetime = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const day_seconds = datetime.getDaySeconds();
    const year_day = datetime.getYearDay();
    
    return try std.fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
        year_day.year, year_day.month, year_day.day_index + 1,
        day_seconds.getHoursIntoDay(), day_seconds.getMinutesIntoHour(), day_seconds.getSecondsIntoMinute()
    });
}

fn sha256Hex(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(data);
    const hash = hasher.finalResult();
    
    return try std.fmt.allocPrint(allocator, "{x}", .{std.fmt.fmtSliceHexLower(&hash)});
}

fn hmacSha256Hex(allocator: std.mem.Allocator, key: []const u8, data: []const u8) ![]const u8 {
    var mac: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&mac, data, key);
    
    return try std.fmt.allocPrint(allocator, "{x}", .{std.fmt.fmtSliceHexLower(&mac)});
}

fn getSigningKey(allocator: std.mem.Allocator, secret_key: []const u8, date: []const u8, region: []const u8, service: []const u8) ![]const u8 {
    // AWS Signature Version 4 signing key derivation
    const k_secret = try std.fmt.allocPrint(allocator, "AWS4{s}", .{secret_key});
    defer allocator.free(k_secret);
    
    var k_date: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&k_date, date, k_secret);
    
    var k_region: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&k_region, region, &k_date);
    
    var k_service: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&k_service, service, &k_region);
    
    var k_signing: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&k_signing, "aws4_request", &k_service);
    
    return try allocator.dupe(u8, &k_signing);
}
```

## Files to Modify
- `src/lfs/storage.zig` (implement missing methods)
- `src/lfs/s3.zig` (AWS S3 operations)
- `src/lfs/filesystem.zig` (filesystem operations)
- `src/database/dao.zig` (bandwidth tracking queries)
- Add garbage collection scheduling system

## Testing Requirements
- Test S3 LIST operations with various prefixes
- Test filesystem directory traversal safety
- Test garbage collection with orphaned objects
- Test bandwidth tracking accuracy
- Test AWS signature generation
- Integration tests with actual S3 buckets
- Performance tests for large object collections

## Dependencies
- AWS S3 API knowledge
- HTTP client for S3 requests
- XML parsing for S3 responses
- Filesystem operations
- Git LFS protocol understanding
- Database for bandwidth tracking

## Benefits
- Completes LFS functionality
- Enables proper storage management
- Provides bandwidth monitoring
- Supports multiple storage backends
- Essential for production LFS deployment