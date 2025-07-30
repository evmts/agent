const std = @import("std");
const testing = std.testing;

pub const FilesystemBackendError = error{
    PathNotAbsolute,
    DirectoryCreateFailed,
    AtomicWriteFailed,
    ObjectNotFound,
    PermissionDenied,
    OutOfMemory,
};

pub const FilesystemConfig = struct {
    base_path: []const u8,
    temp_path: []const u8,
    compression_enabled: bool = false,
    encryption_enabled: bool = false,
    deduplication_enabled: bool = true,
};

pub const FilesystemBackend = struct {
    config: FilesystemConfig,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, config: FilesystemConfig) !FilesystemBackend {
        // Ensure paths are absolute
        if (!std.fs.path.isAbsolute(config.base_path)) {
            return error.PathNotAbsolute;
        }
        if (!std.fs.path.isAbsolute(config.temp_path)) {
            return error.PathNotAbsolute;
        }
        
        // Create base directories
        try std.fs.cwd().makePath(config.base_path);
        try std.fs.cwd().makePath(config.temp_path);
        
        return FilesystemBackend{
            .allocator = allocator,
            .config = config,
        };
    }
    
    pub fn deinit(self: *FilesystemBackend) void {
        _ = self;
    }
    
    pub fn putObject(self: *FilesystemBackend, oid: []const u8, content: []const u8) !void {
        const object_path = try self.buildObjectPath(oid);
        defer self.allocator.free(object_path);
        
        // Create directory structure
        const dir_path = std.fs.path.dirname(object_path).?;
        try std.fs.cwd().makePath(dir_path);
        
        // Write to temporary file first (atomic operation)
        const temp_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.tmp.{d}", 
            .{ self.config.temp_path, oid, std.time.timestamp() });
        defer self.allocator.free(temp_path);
        
        const temp_file = try std.fs.cwd().createFile(temp_path, .{});
        defer temp_file.close();
        
        try temp_file.writeAll(content);
        try temp_file.sync(); // Ensure data is written to disk
        
        // Atomic rename to final location
        try std.fs.cwd().rename(temp_path, object_path);
    }
    
    pub fn getObject(self: *FilesystemBackend, oid: []const u8) ![]u8 {
        const object_path = try self.buildObjectPath(oid);
        defer self.allocator.free(object_path);
        
        const file = std.fs.cwd().openFile(object_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.ObjectNotFound,
            error.AccessDenied => return error.PermissionDenied,
            else => return err,
        };
        defer file.close();
        
        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, file_size);
        errdefer self.allocator.free(content);
        
        _ = try file.read(content);
        return content;
    }
    
    pub fn deleteObject(self: *FilesystemBackend, oid: []const u8) !void {
        const object_path = try self.buildObjectPath(oid);
        defer self.allocator.free(object_path);
        
        std.fs.cwd().deleteFile(object_path) catch |err| switch (err) {
            error.FileNotFound => return error.ObjectNotFound,
            error.AccessDenied => return error.PermissionDenied,
            else => return err,
        };
    }
    
    pub fn objectExists(self: *FilesystemBackend, oid: []const u8) !bool {
        const object_path = try self.buildObjectPath(oid);
        defer self.allocator.free(object_path);
        
        const file = std.fs.cwd().openFile(object_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            error.AccessDenied => return error.PermissionDenied,
            else => return err,
        };
        file.close();
        return true;
    }
    
    pub fn listObjects(self: *FilesystemBackend, prefix: ?[]const u8) ![][]const u8 {
        var object_list = std.ArrayList([]const u8).init(self.allocator);
        defer object_list.deinit();
        
        // Walk through the directory structure
        try self.walkDirectory(self.config.base_path, prefix, &object_list);
        
        return try object_list.toOwnedSlice();
    }
    
    fn walkDirectory(self: *FilesystemBackend, dir_path: []const u8, prefix: ?[]const u8, object_list: *std.ArrayList([]const u8)) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return, // Directory doesn't exist, no objects
            else => return err,
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const entry_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
            defer self.allocator.free(entry_path);
            
            switch (entry.kind) {
                .directory => {
                    // Recursively walk subdirectories
                    try self.walkDirectory(entry_path, prefix, object_list);
                },
                .file => {
                    // Check if this is an object file (not a temp file)
                    if (std.mem.endsWith(u8, entry.name, ".tmp")) continue;
                    
                    // Extract OID from file path - objects are stored as base_path/ab/cd/abcdef...
                    // The OID is the filename itself
                    const oid = entry.name;
                    
                    // Filter by prefix if provided
                    if (prefix) |p| {
                        if (!std.mem.startsWith(u8, oid, p)) continue;
                    }
                    
                    // Validate OID format (should be hex and at least 4 chars)
                    if (oid.len < 4) continue;
                    if (!self.isValidOid(oid)) continue;
                    
                    // Add to list with owned memory
                    const owned_oid = try self.allocator.dupe(u8, oid);
                    try object_list.append(owned_oid);
                },
                else => continue,
            }
        }
    }
    
    fn isValidOid(self: *FilesystemBackend, oid: []const u8) bool {
        _ = self;
        
        // Check if all characters are valid hex
        for (oid) |c| {
            if (!std.ascii.isHex(c)) return false;
        }
        return true;
    }
    
    pub fn getObjectSize(self: *FilesystemBackend, oid: []const u8) !u64 {
        const object_path = try self.buildObjectPath(oid);
        defer self.allocator.free(object_path);
        
        const file = std.fs.cwd().openFile(object_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.ObjectNotFound,
            error.AccessDenied => return error.PermissionDenied,
            else => return err,
        };
        defer file.close();
        
        return try file.getEndPos();
    }
    
    fn buildObjectPath(self: *FilesystemBackend, oid: []const u8) ![]u8 {
        if (oid.len < 4) return error.ObjectNotFound;
        
        // Create directory structure: base_path/ab/cd/abcdef...
        const dir1 = oid[0..2];
        const dir2 = oid[2..4];
        
        return try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}/{s}", .{
            self.config.base_path, dir1, dir2, oid,
        });
    }
};

// Tests for Phase 2: Filesystem Backend Implementation
test "filesystem backend stores objects with correct directory structure" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    const temp_path = try std.fmt.allocPrint(allocator, "{s}/temp", .{base_path});
    defer allocator.free(temp_path);
    
    var backend = try FilesystemBackend.init(allocator, .{
        .base_path = base_path,
        .temp_path = temp_path,
    });
    defer backend.deinit();
    
    const oid = "abcdef1234567890123456789012345678901234567890123456789012345678";
    const content = "test file content";
    
    try backend.putObject(oid, content);
    
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
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    const temp_path = try std.fmt.allocPrint(allocator, "{s}/temp", .{base_path});
    defer allocator.free(temp_path);
    
    var backend = try FilesystemBackend.init(allocator, .{
        .base_path = base_path,
        .temp_path = temp_path,
    });
    defer backend.deinit();
    
    const oid = "atomic_test_oid_1234567890123456789012345678901234567890123456";
    const content = "atomic write test content";
    
    // Write object
    try backend.putObject(oid, content);
    
    // Verify object exists
    try testing.expect(try backend.objectExists(oid));
    
    // Verify content matches
    const retrieved_content = try backend.getObject(oid);
    defer allocator.free(retrieved_content);
    
    try testing.expectEqualStrings(content, retrieved_content);
    
    // Verify size
    const size = try backend.getObjectSize(oid);
    try testing.expectEqual(@as(u64, content.len), size);
}

test "filesystem backend validates absolute paths" {
    const allocator = testing.allocator;
    
    // Should fail with relative paths
    try testing.expectError(error.PathNotAbsolute, 
        FilesystemBackend.init(allocator, .{
            .base_path = "relative/path",
            .temp_path = "/tmp/temp",
        }));
    
    try testing.expectError(error.PathNotAbsolute, 
        FilesystemBackend.init(allocator, .{
            .base_path = "/tmp/base",
            .temp_path = "relative/temp",
        }));
}

test "filesystem backend handles non-existent objects gracefully" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    const temp_path = try std.fmt.allocPrint(allocator, "{s}/temp", .{base_path});
    defer allocator.free(temp_path);
    
    var backend = try FilesystemBackend.init(allocator, .{
        .base_path = base_path,
        .temp_path = temp_path,
    });
    defer backend.deinit();
    
    const non_existent_oid = "0000000000000000000000000000000000000000000000000000000000000000";
    
    // Should not exist
    try testing.expect(!try backend.objectExists(non_existent_oid));
    
    // Should fail to retrieve
    try testing.expectError(error.ObjectNotFound, backend.getObject(non_existent_oid));
    
    // Should fail to get size
    try testing.expectError(error.ObjectNotFound, backend.getObjectSize(non_existent_oid));
    
    // Should fail to delete
    try testing.expectError(error.ObjectNotFound, backend.deleteObject(non_existent_oid));
}

test "filesystem backend handles CRUD operations correctly" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    const temp_path = try std.fmt.allocPrint(allocator, "{s}/temp", .{base_path});
    defer allocator.free(temp_path);
    
    var backend = try FilesystemBackend.init(allocator, .{
        .base_path = base_path,
        .temp_path = temp_path,
    });
    defer backend.deinit();
    
    const oid = "crud_test_oid_1234567890123456789012345678901234567890123456789";
    const content = "CRUD test file content";
    
    // Create
    try backend.putObject(oid, content);
    try testing.expect(try backend.objectExists(oid));
    
    // Read
    const retrieved_content = try backend.getObject(oid);
    defer allocator.free(retrieved_content);
    try testing.expectEqualStrings(content, retrieved_content);
    
    // Update (overwrite)
    const updated_content = "Updated CRUD test content";
    try backend.putObject(oid, updated_content);
    
    const updated_retrieved = try backend.getObject(oid);
    defer allocator.free(updated_retrieved);
    try testing.expectEqualStrings(updated_content, updated_retrieved);
    
    // Delete
    try backend.deleteObject(oid);
    try testing.expect(!try backend.objectExists(oid));
}

test "filesystem backend lists objects correctly" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    const temp_path = try std.fmt.allocPrint(allocator, "{s}/temp", .{base_path});
    defer allocator.free(temp_path);
    
    var backend = try FilesystemBackend.init(allocator, .{
        .base_path = base_path,
        .temp_path = temp_path,
    });
    defer backend.deinit();
    
    // Store test objects
    const test_objects = [_][]const u8{
        "abcdef1234567890123456789012345678901234567890123456789012345678",
        "abcdef9876543210123456789012345678901234567890123456789012345678",
        "123456789012345678901234567890123456789012345678901234567890abcd",
        "fedcba1234567890123456789012345678901234567890123456789012345678",
    };
    
    for (test_objects) |oid| {
        try backend.putObject(oid, "test content");
    }
    
    // List all objects
    const all_objects = try backend.listObjects(null);
    defer {
        for (all_objects) |obj| {
            allocator.free(obj);
        }
        allocator.free(all_objects);
    }
    
    try testing.expectEqual(@as(usize, 4), all_objects.len);
    
    // List objects with prefix "abcdef"
    const prefixed_objects = try backend.listObjects("abcdef");
    defer {
        for (prefixed_objects) |obj| {
            allocator.free(obj);
        }
        allocator.free(prefixed_objects);
    }
    
    try testing.expectEqual(@as(usize, 2), prefixed_objects.len);
    
    // Verify prefixed results start with "abcdef"
    for (prefixed_objects) |obj| {
        try testing.expect(std.mem.startsWith(u8, obj, "abcdef"));
    }
}

test "filesystem backend handles empty directory in listObjects" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    const temp_path = try std.fmt.allocPrint(allocator, "{s}/temp", .{base_path});
    defer allocator.free(temp_path);
    
    var backend = try FilesystemBackend.init(allocator, .{
        .base_path = base_path,
        .temp_path = temp_path,
    });
    defer backend.deinit();
    
    // List objects from empty directory
    const objects = try backend.listObjects(null);
    defer {
        for (objects) |obj| {
            allocator.free(obj);
        }
        allocator.free(objects);
    }
    
    try testing.expectEqual(@as(usize, 0), objects.len);
}

test "filesystem backend filters invalid OIDs in listObjects" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const base_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    const temp_path = try std.fmt.allocPrint(allocator, "{s}/temp", .{base_path});
    defer allocator.free(temp_path);
    
    var backend = try FilesystemBackend.init(allocator, .{
        .base_path = base_path,
        .temp_path = temp_path,
    });
    defer backend.deinit();
    
    // Create a valid object
    const valid_oid = "abcdef1234567890123456789012345678901234567890123456789012345678";
    try backend.putObject(valid_oid, "valid content");
    
    // Manually create some invalid files that should be filtered out
    const valid_dir = try std.fmt.allocPrint(allocator, "{s}/ab/cd", .{base_path});
    defer allocator.free(valid_dir);
    
    try std.fs.cwd().makePath(valid_dir);
    
    // Create temp file (should be filtered)
    const temp_file_path = try std.fmt.allocPrint(allocator, "{s}/temp_file.tmp", .{valid_dir});
    defer allocator.free(temp_file_path);
    
    const temp_file = try std.fs.cwd().createFile(temp_file_path, .{});
    temp_file.close();
    
    // Create file with non-hex characters (should be filtered)
    const invalid_oid_path = try std.fmt.allocPrint(allocator, "{s}/xyz_invalid", .{valid_dir});
    defer allocator.free(invalid_oid_path);
    
    const invalid_file = try std.fs.cwd().createFile(invalid_oid_path, .{});
    invalid_file.close();
    
    // List objects - should only return the valid one
    const objects = try backend.listObjects(null);
    defer {
        for (objects) |obj| {
            allocator.free(obj);
        }
        allocator.free(objects);
    }
    
    try testing.expectEqual(@as(usize, 1), objects.len);
    try testing.expectEqualStrings(valid_oid, objects[0]);
}