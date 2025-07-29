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
        _ = self;
        _ = prefix;
        // TODO: Implement directory traversal for listing objects
        return &[_][]const u8{};
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