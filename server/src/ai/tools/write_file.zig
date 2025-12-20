const std = @import("std");
const types = @import("../types.zig");
const filesystem = @import("filesystem.zig");

/// Write file parameters
pub const WriteFileParams = struct {
    file_path: []const u8,
    content: []const u8,
};

/// Write file result
pub const WriteFileResult = struct {
    success: bool,
    error_msg: ?[]const u8 = null,
    bytes_written: ?usize = null,
};

/// Write file implementation with read-before-write safety
pub fn writeFileImpl(
    allocator: std.mem.Allocator,
    params: WriteFileParams,
    ctx: types.ToolContext,
) !WriteFileResult {
    // Validate and resolve path
    const resolved_path = try filesystem.resolveAndValidatePathSecure(
        allocator,
        params.file_path,
        ctx.working_dir,
    ) orelse {
        return WriteFileResult{
            .success = false,
            .error_msg = "Path traversal not allowed",
        };
    };
    defer allocator.free(resolved_path);

    // Check read-before-write safety
    if (ctx.file_tracker) |tracker| {
        const file_exists = filesystem.fileExists(resolved_path);

        if (file_exists) {
            // File exists - must have been read first
            if (!tracker.wasReadBefore(resolved_path)) {
                return WriteFileResult{
                    .success = false,
                    .error_msg = "File must be read before writing. Use readFile first.",
                };
            }

            // Check if file was modified since read
            const current_mod_time = filesystem.getFileModTime(resolved_path) catch {
                return WriteFileResult{
                    .success = false,
                    .error_msg = "Failed to get file modification time",
                };
            };

            const last_known_mod_time = tracker.getLastModTime(resolved_path);
            if (last_known_mod_time) |last_mod| {
                if (current_mod_time > last_mod) {
                    return WriteFileResult{
                        .success = false,
                        .error_msg = "File was modified since last read. Please read it again.",
                    };
                }
            }
        }
    }

    // Ensure parent directories exist
    filesystem.ensureParentDirectories(allocator, resolved_path) catch |err| {
        return WriteFileResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };

    // Write the file
    filesystem.writeFileContents(resolved_path, params.content) catch |err| {
        return WriteFileResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };

    // Update tracker with new modification time
    if (ctx.file_tracker) |tracker| {
        const new_mod_time = filesystem.getFileModTime(resolved_path) catch std.time.milliTimestamp();
        try tracker.recordRead(resolved_path, std.time.milliTimestamp(), new_mod_time);
    }

    return WriteFileResult{
        .success = true,
        .bytes_written = params.content.len,
    };
}

/// Create JSON schema for write file tool parameters
pub fn createWriteFileSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    // file_path property
    var path_prop = std.json.ObjectMap.init(allocator);
    try path_prop.put("type", std.json.Value{ .string = "string" });
    try path_prop.put("description", std.json.Value{ .string = "The absolute path to the file to write" });
    try properties.put("file_path", std.json.Value{ .object = path_prop });

    // content property
    var content_prop = std.json.ObjectMap.init(allocator);
    try content_prop.put("type", std.json.Value{ .string = "string" });
    try content_prop.put("description", std.json.Value{ .string = "The content to write to the file" });
    try properties.put("content", std.json.Value{ .object = content_prop });

    try schema.put("properties", std.json.Value{ .object = properties });

    // Required fields
    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "file_path" });
    try required.append(std.json.Value{ .string = "content" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

// ============================================================================
// Tests
// ============================================================================

test "WriteFileParams" {
    const params = WriteFileParams{
        .file_path = "/test/path.txt",
        .content = "Hello, World!",
    };

    try std.testing.expectEqualStrings("/test/path.txt", params.file_path);
    try std.testing.expectEqualStrings("Hello, World!", params.content);
}

test "WriteFileResult success" {
    const result = WriteFileResult{
        .success = true,
        .bytes_written = 100,
    };

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(usize, 100), result.bytes_written.?);
    try std.testing.expect(result.error_msg == null);
}

test "WriteFileResult error" {
    const result = WriteFileResult{
        .success = false,
        .error_msg = "Permission denied",
    };

    try std.testing.expect(!result.success);
    try std.testing.expectEqualStrings("Permission denied", result.error_msg.?);
    try std.testing.expect(result.bytes_written == null);
}

test "WriteFileResult path traversal error" {
    const result = WriteFileResult{
        .success = false,
        .error_msg = "Path traversal not allowed",
    };

    try std.testing.expect(!result.success);
    try std.testing.expect(std.mem.indexOf(u8, result.error_msg.?, "Path traversal") != null);
}

test "WriteFileResult read-before-write error" {
    const result = WriteFileResult{
        .success = false,
        .error_msg = "File must be read before writing. Use readFile first.",
    };

    try std.testing.expect(!result.success);
    try std.testing.expect(std.mem.indexOf(u8, result.error_msg.?, "read before writing") != null);
}

test "createWriteFileSchema" {
    const allocator = std.testing.allocator;

    const schema = try createWriteFileSchema(allocator);

    // Schema should be an object
    try std.testing.expect(schema == .object);

    // Should have type = object
    const type_val = schema.object.get("type").?;
    try std.testing.expectEqualStrings("object", type_val.string);

    // Should have properties
    const props = schema.object.get("properties").?;
    try std.testing.expect(props == .object);

    // Should have file_path property
    try std.testing.expect(props.object.get("file_path") != null);

    // Should have content property
    try std.testing.expect(props.object.get("content") != null);

    // Should have required array with both fields
    const required = schema.object.get("required").?;
    try std.testing.expect(required == .array);
    try std.testing.expectEqual(@as(usize, 2), required.array.items.len);
}
