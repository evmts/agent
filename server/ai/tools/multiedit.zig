const std = @import("std");
const types = @import("../types.zig");
const filesystem = @import("filesystem.zig");

/// Single edit operation
pub const EditOperation = struct {
    old_string: []const u8,
    new_string: []const u8,
    replace_all: bool = false,
};

/// Multiedit parameters
pub const MultieditParams = struct {
    file_path: []const u8,
    edits: []const EditOperation,
};

/// Multiedit result
pub const MultieditResult = struct {
    success: bool,
    error_msg: ?[]const u8 = null,
    edits_applied: u32 = 0,
};

/// Multiedit implementation - apply multiple find-replace operations
pub fn multieditImpl(
    allocator: std.mem.Allocator,
    params: MultieditParams,
    ctx: types.ToolContext,
) !MultieditResult {
    // Validate and resolve path
    const resolved_path = try filesystem.resolveAndValidatePathSecure(
        allocator,
        params.file_path,
        ctx.working_dir,
    ) orelse {
        return MultieditResult{
            .success = false,
            .error_msg = "Path traversal not allowed",
        };
    };
    defer allocator.free(resolved_path);

    // Check if file exists
    if (!filesystem.fileExists(resolved_path)) {
        return MultieditResult{
            .success = false,
            .error_msg = "File not found",
        };
    }

    // Check read-before-write safety
    if (ctx.file_tracker) |tracker| {
        if (!tracker.hasBeenRead(resolved_path)) {
            return MultieditResult{
                .success = false,
                .error_msg = "File must be read before editing. Use readFile first.",
            };
        }

        // Check if file was modified since read
        const current_mod_time = filesystem.getFileModTime(resolved_path) catch {
            return MultieditResult{
                .success = false,
                .error_msg = "Failed to get file modification time",
            };
        };

        const last_known_mod_time = tracker.getLastReadTime(resolved_path);
        if (last_known_mod_time) |last_mod| {
            if (current_mod_time > last_mod) {
                return MultieditResult{
                    .success = false,
                    .error_msg = "File was modified since last read. Please read it again.",
                };
            }
        }
    }

    // Read current content
    var content = try filesystem.readFileContents(allocator, resolved_path);
    defer allocator.free(content);

    // Validate all edits before applying (check for ambiguous matches)
    for (params.edits, 0..) |edit, i| {
        if (!edit.replace_all) {
            // Count occurrences
            var count: u32 = 0;
            var pos: usize = 0;
            while (pos < content.len) {
                if (std.mem.indexOf(u8, content[pos..], edit.old_string)) |idx| {
                    count += 1;
                    pos += idx + edit.old_string.len;
                } else {
                    break;
                }
            }

            if (count == 0) {
                const msg = try std.fmt.allocPrint(allocator, "Edit {d}: old_string not found in file", .{i + 1});
                return MultieditResult{
                    .success = false,
                    .error_msg = msg,
                };
            }

            if (count > 1) {
                const msg = try std.fmt.allocPrint(allocator, "Edit {d}: old_string found {d} times. Use replace_all=true or provide more context.", .{ i + 1, count });
                return MultieditResult{
                    .success = false,
                    .error_msg = msg,
                };
            }
        }
    }

    // Apply edits sequentially
    var edits_applied: u32 = 0;
    for (params.edits) |edit| {
        const new_content = if (edit.replace_all)
            try replaceAll(allocator, content, edit.old_string, edit.new_string)
        else
            try replaceFirst(allocator, content, edit.old_string, edit.new_string);

        if (new_content) |nc| {
            allocator.free(content);
            content = nc;
            edits_applied += 1;
        }
    }

    // Write the modified content
    filesystem.writeFileContents(resolved_path, content) catch |err| {
        return MultieditResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };

    // Update tracker with new modification time
    if (ctx.file_tracker) |tracker| {
        const new_mod_time = filesystem.getFileModTime(resolved_path) catch @as(i64, @truncate(std.time.milliTimestamp()));
        try tracker.recordRead(resolved_path, new_mod_time);
    }

    return MultieditResult{
        .success = true,
        .edits_applied = edits_applied,
    };
}

/// Replace first occurrence
fn replaceFirst(allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8, replacement: []const u8) !?[]const u8 {
    const idx = std.mem.indexOf(u8, haystack, needle) orelse return null;

    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, haystack[0..idx]);
    try result.appendSlice(allocator, replacement);
    try result.appendSlice(allocator, haystack[idx + needle.len ..]);

    const slice = try result.toOwnedSlice(allocator);
    return slice;
}

/// Replace all occurrences
fn replaceAll(allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8, replacement: []const u8) !?[]const u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var pos: usize = 0;
    var replaced = false;

    while (pos < haystack.len) {
        if (std.mem.indexOf(u8, haystack[pos..], needle)) |idx| {
            try result.appendSlice(allocator, haystack[pos .. pos + idx]);
            try result.appendSlice(allocator, replacement);
            pos += idx + needle.len;
            replaced = true;
        } else {
            try result.appendSlice(allocator, haystack[pos..]);
            break;
        }
    }

    if (!replaced) {
        result.deinit(allocator);
        return null;
    }

    const slice = try result.toOwnedSlice(allocator);
    return slice;
}

/// Create JSON schema for multiedit tool parameters
pub fn createMultieditSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    // file_path property
    var path_prop = std.json.ObjectMap.init(allocator);
    try path_prop.put("type", std.json.Value{ .string = "string" });
    try path_prop.put("description", std.json.Value{ .string = "The absolute path to the file to edit" });
    try properties.put("file_path", std.json.Value{ .object = path_prop });

    // edits property
    var edits_prop = std.json.ObjectMap.init(allocator);
    try edits_prop.put("type", std.json.Value{ .string = "array" });
    try edits_prop.put("description", std.json.Value{ .string = "Array of edit operations" });

    var items = std.json.ObjectMap.init(allocator);
    try items.put("type", std.json.Value{ .string = "object" });

    var item_props = std.json.ObjectMap.init(allocator);

    var old_prop = std.json.ObjectMap.init(allocator);
    try old_prop.put("type", std.json.Value{ .string = "string" });
    try old_prop.put("description", std.json.Value{ .string = "The text to find" });
    try item_props.put("old_string", std.json.Value{ .object = old_prop });

    var new_prop = std.json.ObjectMap.init(allocator);
    try new_prop.put("type", std.json.Value{ .string = "string" });
    try new_prop.put("description", std.json.Value{ .string = "The replacement text" });
    try item_props.put("new_string", std.json.Value{ .object = new_prop });

    var replace_all_prop = std.json.ObjectMap.init(allocator);
    try replace_all_prop.put("type", std.json.Value{ .string = "boolean" });
    try replace_all_prop.put("description", std.json.Value{ .string = "Replace all occurrences" });
    try item_props.put("replace_all", std.json.Value{ .object = replace_all_prop });

    try items.put("properties", std.json.Value{ .object = item_props });
    try edits_prop.put("items", std.json.Value{ .object = items });
    try properties.put("edits", std.json.Value{ .object = edits_prop });

    try schema.put("properties", std.json.Value{ .object = properties });

    // Required fields
    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "file_path" });
    try required.append(std.json.Value{ .string = "edits" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

// Helper for cleaning up JSON values in tests
fn freeJsonValue(allocator: std.mem.Allocator, value: *std.json.Value) void {
    switch (value.*) {
        .object => |*obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                freeJsonValue(allocator, entry.value_ptr);
            }
            obj.deinit();
        },
        .array => |*arr| {
            for (arr.items) |*item| {
                freeJsonValue(allocator, item);
            }
            arr.deinit();
        },
        else => {},
    }
}

test "replaceFirst replaces first occurrence" {
    const allocator = std.testing.allocator;

    const result = try replaceFirst(allocator, "hello world world", "world", "zig");
    defer if (result) |r| allocator.free(r);

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("hello zig world", result.?);
}

test "replaceAll replaces all occurrences" {
    const allocator = std.testing.allocator;

    const result = try replaceAll(allocator, "hello world world", "world", "zig");
    defer if (result) |r| allocator.free(r);

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("hello zig zig", result.?);
}

test "replaceFirst returns null when not found" {
    const allocator = std.testing.allocator;

    const result = try replaceFirst(allocator, "hello world", "notfound", "zig");

    try std.testing.expect(result == null);
}

test "replaceAll returns null when not found" {
    const allocator = std.testing.allocator;

    const result = try replaceAll(allocator, "hello world", "notfound", "zig");

    try std.testing.expect(result == null);
}

test "replaceFirst handles empty replacement" {
    const allocator = std.testing.allocator;

    const result = try replaceFirst(allocator, "hello world", "world", "");
    defer if (result) |r| allocator.free(r);

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("hello ", result.?);
}

test "replaceAll handles overlapping patterns" {
    const allocator = std.testing.allocator;

    // Non-overlapping replacement
    const result = try replaceAll(allocator, "aaa", "aa", "b");
    defer if (result) |r| allocator.free(r);

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("ba", result.?);
}

test "EditOperation default values" {
    const op = EditOperation{
        .old_string = "foo",
        .new_string = "bar",
    };

    try std.testing.expectEqualStrings("foo", op.old_string);
    try std.testing.expectEqualStrings("bar", op.new_string);
    try std.testing.expect(!op.replace_all);
}

test "EditOperation with replace_all" {
    const op = EditOperation{
        .old_string = "foo",
        .new_string = "bar",
        .replace_all = true,
    };

    try std.testing.expect(op.replace_all);
}

test "MultieditParams struct" {
    const edits = [_]EditOperation{
        .{ .old_string = "foo", .new_string = "bar" },
        .{ .old_string = "baz", .new_string = "qux", .replace_all = true },
    };

    const params = MultieditParams{
        .file_path = "/test/file.txt",
        .edits = &edits,
    };

    try std.testing.expectEqualStrings("/test/file.txt", params.file_path);
    try std.testing.expectEqual(@as(usize, 2), params.edits.len);
}

test "MultieditResult success" {
    const result = MultieditResult{
        .success = true,
        .edits_applied = 3,
    };

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(u32, 3), result.edits_applied);
    try std.testing.expect(result.error_msg == null);
}

test "MultieditResult error" {
    const result = MultieditResult{
        .success = false,
        .error_msg = "File not found",
    };

    try std.testing.expect(!result.success);
    try std.testing.expectEqualStrings("File not found", result.error_msg.?);
    try std.testing.expectEqual(@as(u32, 0), result.edits_applied);
}

test "createMultieditSchema" {
    const allocator = std.testing.allocator;

    var schema = try createMultieditSchema(allocator);
    defer freeJsonValue(allocator, &schema);

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

    // Should have edits property
    const edits_prop = props.object.get("edits").?;
    try std.testing.expect(edits_prop == .object);

    // edits should be an array type
    const edits_type = edits_prop.object.get("type").?;
    try std.testing.expectEqualStrings("array", edits_type.string);

    // Should have required array with both fields
    const required = schema.object.get("required").?;
    try std.testing.expect(required == .array);
    try std.testing.expectEqual(@as(usize, 2), required.array.items.len);
}
