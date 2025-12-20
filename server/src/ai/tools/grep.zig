const std = @import("std");
const types = @import("../types.zig");

/// Grep match result
pub const GrepMatch = struct {
    path: []const u8,
    line_number: u32,
    text: []const u8,
    absolute_offset: ?u64 = null,
};

/// Grep result
pub const GrepResult = struct {
    success: bool,
    matches: []GrepMatch = &.{},
    formatted_output: ?[]const u8 = null,
    error_msg: ?[]const u8 = null,
    truncated: bool = false,
    total_count: ?u32 = null,
};

/// Grep parameters
pub const GrepParams = struct {
    pattern: []const u8,
    path: ?[]const u8 = null,
    glob: ?[]const u8 = null,
    multiline: bool = false,
    case_insensitive: bool = false,
    max_count: ?u32 = null,
    context_before: ?u32 = null,
    context_after: ?u32 = null,
    context_lines: ?u32 = null,
    head_limit: u32 = 0,
    offset: u32 = 0,
};

/// Execute grep using ripgrep
pub fn grepImpl(
    allocator: std.mem.Allocator,
    params: GrepParams,
    working_dir: ?[]const u8,
) !GrepResult {
    var args = std.ArrayList([]const u8){};
    defer args.deinit(allocator);

    // Base ripgrep arguments
    try args.appendSlice(allocator, &.{
        "rg",
        "--json",
        "--hidden",
        "--glob=!**/.git/**",
    });

    // Multiline mode
    if (params.multiline) {
        try args.appendSlice(allocator, &.{ "-U", "--multiline-dotall" });
    }

    // Case insensitive
    if (params.case_insensitive) {
        try args.append(allocator, "-i");
    }

    // Context lines
    if (params.context_lines) |c| {
        const arg = try std.fmt.allocPrint(allocator, "-C{d}", .{c});
        defer allocator.free(arg);
        try args.append(allocator, try allocator.dupe(u8, arg));
    } else {
        if (params.context_after) |c| {
            const arg = try std.fmt.allocPrint(allocator, "-A{d}", .{c});
            defer allocator.free(arg);
            try args.append(allocator, try allocator.dupe(u8, arg));
        }
        if (params.context_before) |c| {
            const arg = try std.fmt.allocPrint(allocator, "-B{d}", .{c});
            defer allocator.free(arg);
            try args.append(allocator, try allocator.dupe(u8, arg));
        }
    }

    // Glob filter
    if (params.glob) |g| {
        const arg = try std.fmt.allocPrint(allocator, "--glob={s}", .{g});
        defer allocator.free(arg);
        try args.append(allocator, try allocator.dupe(u8, arg));
    }

    // Max count
    if (params.max_count) |m| {
        const arg = try std.fmt.allocPrint(allocator, "--max-count={d}", .{m});
        defer allocator.free(arg);
        try args.append(allocator, try allocator.dupe(u8, arg));
    }

    // Pattern
    try args.append(allocator, params.pattern);

    // Path
    if (params.path) |p| {
        try args.append(allocator, p);
    }

    // Spawn ripgrep process
    var child = std.process.Child.init(args.items, allocator);
    child.cwd = working_dir;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read output
    const stdout_file = child.stdout.?;
    const output = stdout_file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch {
        return GrepResult{
            .success = false,
            .matches = &.{},
            .formatted_output = try allocator.dupe(u8, "Error reading output"),
            .total_count = 0,
        };
    };
    defer allocator.free(output);

    const result = try child.wait();

    // Exit code 1 means no matches
    if (result.Exited == 1) {
        return GrepResult{
            .success = true,
            .matches = &.{},
            .formatted_output = try allocator.dupe(u8, "No matches found"),
            .total_count = 0,
        };
    }

    // Parse JSON output
    var matches: std.ArrayList(GrepMatch) = .{};
    defer matches.deinit(allocator);

    var formatted: std.ArrayList(u8) = .{};
    defer formatted.deinit(allocator);

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: u32 = 0;
    var skipped: u32 = 0;

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Parse JSON line
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        const obj = parsed.value.object;
        const msg_type = obj.get("type") orelse continue;

        if (msg_type != .string) continue;
        if (!std.mem.eql(u8, msg_type.string, "match")) continue;

        const data = obj.get("data") orelse continue;
        if (data != .object) continue;

        const path_obj = data.object.get("path") orelse continue;
        const path_text = if (path_obj == .object)
            path_obj.object.get("text")
        else
            null;
        const path = if (path_text) |pt| pt.string else continue;

        const line_number_obj = data.object.get("line_number") orelse continue;
        const line_number = if (line_number_obj == .integer)
            @as(u32, @intCast(line_number_obj.integer))
        else
            continue;

        const lines_obj = data.object.get("lines") orelse continue;
        const lines_text = if (lines_obj == .object)
            lines_obj.object.get("text")
        else
            null;
        const text = if (lines_text) |lt| lt.string else continue;

        // Apply offset
        if (skipped < params.offset) {
            skipped += 1;
            continue;
        }

        // Apply head limit
        if (params.head_limit > 0 and count >= params.head_limit) {
            break;
        }

        try matches.append(allocator, .{
            .path = try allocator.dupe(u8, path),
            .line_number = line_number,
            .text = try allocator.dupe(u8, text),
        });

        // Add to formatted output
        try formatted.writer(allocator).print("{s}:{d}:{s}\n", .{ path, line_number, text });

        count += 1;
    }

    return GrepResult{
        .success = true,
        .matches = try matches.toOwnedSlice(allocator),
        .formatted_output = try formatted.toOwnedSlice(allocator),
        .total_count = count,
        .truncated = params.head_limit > 0 and count >= params.head_limit,
    };
}

/// Create JSON schema for grep tool parameters
pub fn createGrepSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    // pattern property
    var pattern_prop = std.json.ObjectMap.init(allocator);
    try pattern_prop.put("type", std.json.Value{ .string = "string" });
    try pattern_prop.put("description", std.json.Value{ .string = "Regular expression pattern to search for" });
    try properties.put("pattern", std.json.Value{ .object = pattern_prop });

    // path property
    var path_prop = std.json.ObjectMap.init(allocator);
    try path_prop.put("type", std.json.Value{ .string = "string" });
    try path_prop.put("description", std.json.Value{ .string = "Directory or file to search in" });
    try properties.put("path", std.json.Value{ .object = path_prop });

    // glob property
    var glob_prop = std.json.ObjectMap.init(allocator);
    try glob_prop.put("type", std.json.Value{ .string = "string" });
    try glob_prop.put("description", std.json.Value{ .string = "File pattern filter (e.g., *.ts)" });
    try properties.put("glob", std.json.Value{ .object = glob_prop });

    // multiline property
    var multiline_prop = std.json.ObjectMap.init(allocator);
    try multiline_prop.put("type", std.json.Value{ .string = "boolean" });
    try multiline_prop.put("description", std.json.Value{ .string = "Enable multiline mode" });
    try properties.put("multiline", std.json.Value{ .object = multiline_prop });

    // caseInsensitive property
    var case_prop = std.json.ObjectMap.init(allocator);
    try case_prop.put("type", std.json.Value{ .string = "boolean" });
    try case_prop.put("description", std.json.Value{ .string = "Case insensitive search" });
    try properties.put("caseInsensitive", std.json.Value{ .object = case_prop });

    try schema.put("properties", std.json.Value{ .object = properties });

    // Required fields
    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "pattern" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

// ============================================================================
// Tests
// ============================================================================

test "GrepParams defaults" {
    const params = GrepParams{
        .pattern = "test",
    };

    try std.testing.expectEqualStrings("test", params.pattern);
    try std.testing.expect(params.path == null);
    try std.testing.expect(params.glob == null);
    try std.testing.expect(!params.multiline);
    try std.testing.expect(!params.case_insensitive);
    try std.testing.expect(params.max_count == null);
    try std.testing.expectEqual(@as(u32, 0), params.head_limit);
    try std.testing.expectEqual(@as(u32, 0), params.offset);
}

test "GrepParams with all options" {
    const params = GrepParams{
        .pattern = "function",
        .path = "/src",
        .glob = "*.ts",
        .multiline = true,
        .case_insensitive = true,
        .max_count = 50,
        .context_before = 3,
        .context_after = 3,
        .head_limit = 100,
        .offset = 10,
    };

    try std.testing.expectEqualStrings("function", params.pattern);
    try std.testing.expectEqualStrings("/src", params.path.?);
    try std.testing.expectEqualStrings("*.ts", params.glob.?);
    try std.testing.expect(params.multiline);
    try std.testing.expect(params.case_insensitive);
    try std.testing.expectEqual(@as(u32, 50), params.max_count.?);
    try std.testing.expectEqual(@as(u32, 3), params.context_before.?);
    try std.testing.expectEqual(@as(u32, 3), params.context_after.?);
    try std.testing.expectEqual(@as(u32, 100), params.head_limit);
    try std.testing.expectEqual(@as(u32, 10), params.offset);
}

test "GrepMatch" {
    const match = GrepMatch{
        .path = "src/main.zig",
        .line_number = 42,
        .text = "const foo = bar;",
    };

    try std.testing.expectEqualStrings("src/main.zig", match.path);
    try std.testing.expectEqual(@as(u32, 42), match.line_number);
    try std.testing.expectEqualStrings("const foo = bar;", match.text);
    try std.testing.expect(match.absolute_offset == null);
}

test "GrepResult success with matches" {
    const result = GrepResult{
        .success = true,
        .matches = &.{},
        .formatted_output = "file.zig:1:match",
        .total_count = 5,
        .truncated = false,
    };

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(u32, 5), result.total_count.?);
    try std.testing.expect(!result.truncated);
    try std.testing.expect(result.error_msg == null);
}

test "GrepResult no matches" {
    const result = GrepResult{
        .success = true,
        .matches = &.{},
        .formatted_output = "No matches found",
        .total_count = 0,
    };

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(u32, 0), result.total_count.?);
}

test "GrepResult truncated" {
    const result = GrepResult{
        .success = true,
        .truncated = true,
        .total_count = 100,
    };

    try std.testing.expect(result.truncated);
}

test "GrepResult error" {
    const result = GrepResult{
        .success = false,
        .error_msg = "Invalid pattern",
    };

    try std.testing.expect(!result.success);
    try std.testing.expectEqualStrings("Invalid pattern", result.error_msg.?);
}

test "createGrepSchema" {
    const allocator = std.testing.allocator;

    const schema = try createGrepSchema(allocator);

    // Schema should be an object
    try std.testing.expect(schema == .object);

    // Should have type = object
    const type_val = schema.object.get("type").?;
    try std.testing.expectEqualStrings("object", type_val.string);

    // Should have properties
    const props = schema.object.get("properties").?;
    try std.testing.expect(props == .object);

    // Should have pattern property
    try std.testing.expect(props.object.get("pattern") != null);

    // Should have path property
    try std.testing.expect(props.object.get("path") != null);

    // Should have glob property
    try std.testing.expect(props.object.get("glob") != null);

    // Should have multiline property
    try std.testing.expect(props.object.get("multiline") != null);

    // Should have caseInsensitive property
    try std.testing.expect(props.object.get("caseInsensitive") != null);

    // Should have required array with pattern
    const required = schema.object.get("required").?;
    try std.testing.expect(required == .array);
    try std.testing.expectEqual(@as(usize, 1), required.array.items.len);
}
