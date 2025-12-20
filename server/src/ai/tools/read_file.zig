const std = @import("std");
const types = @import("../types.zig");
const filesystem = @import("filesystem.zig");

/// Read file parameters
pub const ReadFileParams = struct {
    file_path: []const u8,
    offset: ?u32 = null,
    limit: ?u32 = null,
};

/// Read file result
pub const ReadFileResult = struct {
    success: bool,
    content: ?[]const u8 = null,
    error_msg: ?[]const u8 = null,
    line_count: u32 = 0,
    truncated: bool = false,
};

/// Default limits
const DEFAULT_LIMIT: u32 = 2000;
const MAX_LINE_LENGTH: usize = 2000;
const MAX_FILE_SIZE: usize = 10 * 1024 * 1024; // 10MB

/// Read file implementation with line numbers
pub fn readFileImpl(
    allocator: std.mem.Allocator,
    params: ReadFileParams,
    ctx: types.ToolContext,
) !ReadFileResult {
    // Validate and resolve path
    const resolved_path = try filesystem.resolveAndValidatePathSecure(
        allocator,
        params.file_path,
        ctx.working_dir,
    ) orelse {
        return ReadFileResult{
            .success = false,
            .error_msg = "Path traversal not allowed",
        };
    };
    defer allocator.free(resolved_path);

    // Check if file exists
    if (!filesystem.fileExists(resolved_path)) {
        return ReadFileResult{
            .success = false,
            .error_msg = "File not found",
        };
    }

    // Read file contents
    const content = filesystem.readFileContents(allocator, resolved_path) catch |err| {
        return ReadFileResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };
    defer allocator.free(content);

    // Track file read for read-before-write safety
    if (ctx.file_tracker) |tracker| {
        const mod_time = filesystem.getFileModTime(resolved_path) catch @as(i64, @truncate(std.time.milliTimestamp()));
        try tracker.recordRead(resolved_path, mod_time);
    }

    // Apply offset and limit
    const offset = params.offset orelse 1;
    const limit = params.limit orelse DEFAULT_LIMIT;

    var result: std.ArrayList(u8) = .{};
    defer result.deinit(allocator);

    var line_num: u32 = 1;
    var output_lines: u32 = 0;
    var truncated = false;

    var lines_iter = std.mem.splitScalar(u8, content, '\n');

    while (lines_iter.next()) |line| {
        // Skip lines before offset
        if (line_num < offset) {
            line_num += 1;
            continue;
        }

        // Check limit
        if (output_lines >= limit) {
            truncated = true;
            break;
        }

        // Truncate long lines
        const output_line = if (line.len > MAX_LINE_LENGTH)
            line[0..MAX_LINE_LENGTH]
        else
            line;

        // Format with line number (cat -n style)
        try result.writer(allocator).print("{d: >6}\t{s}\n", .{ line_num, output_line });

        line_num += 1;
        output_lines += 1;
    }

    return ReadFileResult{
        .success = true,
        .content = try result.toOwnedSlice(allocator),
        .line_count = output_lines,
        .truncated = truncated,
    };
}

/// Create JSON schema for read file tool parameters
pub fn createReadFileSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    // file_path property
    var path_prop = std.json.ObjectMap.init(allocator);
    try path_prop.put("type", std.json.Value{ .string = "string" });
    try path_prop.put("description", std.json.Value{ .string = "The absolute path to the file to read" });
    try properties.put("file_path", std.json.Value{ .object = path_prop });

    // offset property
    var offset_prop = std.json.ObjectMap.init(allocator);
    try offset_prop.put("type", std.json.Value{ .string = "integer" });
    try offset_prop.put("description", std.json.Value{ .string = "Line number to start reading from (1-based)" });
    try properties.put("offset", std.json.Value{ .object = offset_prop });

    // limit property
    var limit_prop = std.json.ObjectMap.init(allocator);
    try limit_prop.put("type", std.json.Value{ .string = "integer" });
    try limit_prop.put("description", std.json.Value{ .string = "Maximum number of lines to read" });
    try properties.put("limit", std.json.Value{ .object = limit_prop });

    try schema.put("properties", std.json.Value{ .object = properties });

    // Required fields
    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "file_path" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

// ============================================================================
// Tests
// ============================================================================

test "ReadFileParams defaults" {
    const params = ReadFileParams{
        .file_path = "/test/path.txt",
    };

    try std.testing.expectEqualStrings("/test/path.txt", params.file_path);
    try std.testing.expect(params.offset == null);
    try std.testing.expect(params.limit == null);
}

test "ReadFileParams with options" {
    const params = ReadFileParams{
        .file_path = "/test/path.txt",
        .offset = 10,
        .limit = 100,
    };

    try std.testing.expectEqual(@as(u32, 10), params.offset.?);
    try std.testing.expectEqual(@as(u32, 100), params.limit.?);
}

test "ReadFileResult success" {
    const result = ReadFileResult{
        .success = true,
        .content = "line 1\nline 2\n",
        .line_count = 2,
        .truncated = false,
    };

    try std.testing.expect(result.success);
    try std.testing.expect(result.content != null);
    try std.testing.expectEqual(@as(u32, 2), result.line_count);
    try std.testing.expect(!result.truncated);
}

test "ReadFileResult error" {
    const result = ReadFileResult{
        .success = false,
        .error_msg = "File not found",
    };

    try std.testing.expect(!result.success);
    try std.testing.expectEqualStrings("File not found", result.error_msg.?);
    try std.testing.expect(result.content == null);
}

test "DEFAULT_LIMIT constant" {
    try std.testing.expectEqual(@as(u32, 2000), DEFAULT_LIMIT);
}

test "MAX_LINE_LENGTH constant" {
    try std.testing.expectEqual(@as(usize, 2000), MAX_LINE_LENGTH);
}

test "MAX_FILE_SIZE constant" {
    try std.testing.expectEqual(@as(usize, 10 * 1024 * 1024), MAX_FILE_SIZE);
}

test "createReadFileSchema" {
    const allocator = std.testing.allocator;

    const schema = try createReadFileSchema(allocator);

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

    // Should have required array with file_path
    const required = schema.object.get("required").?;
    try std.testing.expect(required == .array);
    try std.testing.expect(required.array.items.len > 0);
}
