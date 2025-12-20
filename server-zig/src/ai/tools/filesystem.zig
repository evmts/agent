const std = @import("std");

/// Path validation and security utilities

/// Resolve and validate a path, ensuring it doesn't escape the working directory
pub fn resolveAndValidatePathSecure(
    allocator: std.mem.Allocator,
    path: []const u8,
    working_dir: ?[]const u8,
) !?[]const u8 {
    const cwd = working_dir orelse ".";

    // Handle absolute vs relative paths
    const resolved = if (std.fs.path.isAbsolute(path))
        try allocator.dupe(u8, path)
    else
        try std.fs.path.join(allocator, &.{ cwd, path });
    errdefer allocator.free(resolved);

    // Normalize the path to resolve .. and .
    const normalized = try normalizePath(allocator, resolved);
    allocator.free(resolved);
    errdefer allocator.free(normalized);

    // Check if the normalized path is within the working directory
    const abs_cwd = if (std.fs.path.isAbsolute(cwd))
        try allocator.dupe(u8, cwd)
    else blk: {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const real_cwd = std.fs.cwd().realpath(cwd, &buf) catch {
            // If we can't get real path, just use cwd as-is
            break :blk try allocator.dupe(u8, cwd);
        };
        break :blk try allocator.dupe(u8, real_cwd);
    };
    defer allocator.free(abs_cwd);

    // Ensure the path starts with the working directory
    if (!std.mem.startsWith(u8, normalized, abs_cwd)) {
        allocator.free(normalized);
        return null; // Path traversal attempt
    }

    return normalized;
}

/// Normalize a path by resolving . and .. components
fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var components = std.ArrayList([]const u8).init(allocator);
    defer components.deinit();

    var iter = std.mem.splitScalar(u8, path, '/');
    const is_absolute = path.len > 0 and path[0] == '/';

    while (iter.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".")) {
            // Skip empty and . components
            continue;
        } else if (std.mem.eql(u8, component, "..")) {
            // Go up one directory if possible
            if (components.items.len > 0) {
                _ = components.pop();
            }
        } else {
            try components.append(component);
        }
    }

    // Reconstruct the path
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    if (is_absolute) {
        try result.append('/');
    }

    for (components.items, 0..) |component, i| {
        if (i > 0) {
            try result.append('/');
        }
        try result.appendSlice(component);
    }

    if (result.items.len == 0) {
        try result.append('.');
    }

    return result.toOwnedSlice();
}

/// Check if a file exists
pub fn fileExists(path: []const u8) bool {
    const file = std.fs.openFileAbsolute(path, .{}) catch return false;
    file.close();
    return true;
}

/// Check if a directory exists
pub fn directoryExists(path: []const u8) bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
    dir.close();
    return true;
}

/// Get file modification time in milliseconds
pub fn getFileModTime(path: []const u8) !i64 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const stat = try file.stat();
    return @divFloor(stat.mtime, std.time.ns_per_ms);
}

/// Create parent directories if they don't exist
pub fn ensureParentDirectories(allocator: std.mem.Allocator, path: []const u8) !void {
    const dir_path = std.fs.path.dirname(path) orelse return;
    if (dir_path.len == 0) return;

    // Try to create the directory structure
    std.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        error.FileNotFound => {
            // Parent doesn't exist, create it recursively
            try ensureParentDirectories(allocator, dir_path);
            std.fs.makeDirAbsolute(dir_path) catch |e| switch (e) {
                error.PathAlreadyExists => return,
                else => return e,
            };
        },
        else => return err,
    };
}

/// Read file contents
pub fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    return try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
}

/// Write file contents
pub fn writeFileContents(path: []const u8, content: []const u8) !void {
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();

    try file.writeAll(content);
}

/// Format file with line numbers (like cat -n)
pub fn formatWithLineNumbers(allocator: std.mem.Allocator, content: []const u8, start_line: u32) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var line_num: u32 = start_line;
    var iter = std.mem.splitScalar(u8, content, '\n');

    while (iter.next()) |line| {
        // Format: "     6\tline content"
        const num_str = try std.fmt.allocPrint(allocator, "{d: >6}\t", .{line_num});
        defer allocator.free(num_str);

        try result.appendSlice(num_str);
        try result.appendSlice(line);
        try result.append('\n');

        line_num += 1;
    }

    return result.toOwnedSlice();
}

test "normalizePath handles simple paths" {
    const allocator = std.testing.allocator;

    const result = try normalizePath(allocator, "/foo/bar/baz");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/foo/bar/baz", result);
}

test "normalizePath handles .. components" {
    const allocator = std.testing.allocator;

    const result = try normalizePath(allocator, "/foo/bar/../baz");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/foo/baz", result);
}

test "normalizePath handles . components" {
    const allocator = std.testing.allocator;

    const result = try normalizePath(allocator, "/foo/./bar/./baz");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/foo/bar/baz", result);
}

test "resolveAndValidatePathSecure blocks traversal" {
    const allocator = std.testing.allocator;

    // This should return null because it tries to escape
    const result = try resolveAndValidatePathSecure(allocator, "../../../etc/passwd", "/home/user");
    try std.testing.expect(result == null);
}
