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
        if (!tracker.wasReadBefore(resolved_path)) {
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

        const last_known_mod_time = tracker.getLastModTime(resolved_path);
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
        const new_mod_time = filesystem.getFileModTime(resolved_path) catch std.time.milliTimestamp();
        try tracker.recordRead(resolved_path, std.time.milliTimestamp(), new_mod_time);
    }

    return MultieditResult{
        .success = true,
        .edits_applied = edits_applied,
    };
}

/// Replace first occurrence
fn replaceFirst(allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8, replacement: []const u8) !?[]const u8 {
    const idx = std.mem.indexOf(u8, haystack, needle) orelse return null;

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.appendSlice(haystack[0..idx]);
    try result.appendSlice(replacement);
    try result.appendSlice(haystack[idx + needle.len ..]);

    return result.toOwnedSlice();
}

/// Replace all occurrences
fn replaceAll(allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8, replacement: []const u8) !?[]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var pos: usize = 0;
    var replaced = false;

    while (pos < haystack.len) {
        if (std.mem.indexOf(u8, haystack[pos..], needle)) |idx| {
            try result.appendSlice(haystack[pos .. pos + idx]);
            try result.appendSlice(replacement);
            pos += idx + needle.len;
            replaced = true;
        } else {
            try result.appendSlice(haystack[pos..]);
            break;
        }
    }

    if (!replaced) return null;

    return result.toOwnedSlice();
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
