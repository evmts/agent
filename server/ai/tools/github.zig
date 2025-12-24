const std = @import("std");
const types = @import("../types.zig");

/// GitHub CLI parameters
pub const GitHubParams = struct {
    args: []const []const u8,
};

/// GitHub result
pub const GitHubResult = struct {
    success: bool,
    output: ?[]const u8 = null,
    error_msg: ?[]const u8 = null,
    exit_code: ?u8 = null,
};

/// Whitelisted GitHub CLI commands
const ALLOWED_COMMANDS: []const []const u8 = &.{
    "pr",
    "issue",
    "repo",
    "run",
    "workflow",
    "release",
    "gist",
    "api",
};

/// Blocked subcommand patterns
const BLOCKED_PATTERNS: []const []const u8 = &.{
    "delete",
    "close",
    "merge",
    "auth",
    "secret",
    "force",
    "config",
    "--force",
    "-f",
};

/// GitHub CLI implementation
pub fn githubImpl(
    allocator: std.mem.Allocator,
    params: GitHubParams,
    working_dir: ?[]const u8,
) !GitHubResult {
    if (params.args.len == 0) {
        return GitHubResult{
            .success = false,
            .error_msg = "No command specified",
        };
    }

    // Check if command is allowed
    const command = params.args[0];
    var allowed = false;
    for (ALLOWED_COMMANDS) |ac| {
        if (std.mem.eql(u8, command, ac)) {
            allowed = true;
            break;
        }
    }

    if (!allowed) {
        return GitHubResult{
            .success = false,
            .error_msg = "Command not allowed. Allowed: pr, issue, repo, run, workflow, release, gist, api",
        };
    }

    // Check for blocked patterns
    for (params.args) |arg| {
        for (BLOCKED_PATTERNS) |pattern| {
            if (std.mem.eql(u8, arg, pattern)) {
                return GitHubResult{
                    .success = false,
                    .error_msg = "Destructive operation not allowed",
                };
            }
        }
    }

    // Build command
    var args: std.ArrayList([]const u8) = .{};
    defer args.deinit(allocator);

    try args.append(allocator, "gh");
    for (params.args) |arg| {
        try args.append(allocator, arg);
    }

    // Spawn gh process
    var child = std.process.Child.init(args.items, allocator);
    child.cwd = working_dir;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read output using readToEndAlloc
    const stdout_output = child.stdout.?.readToEndAlloc(allocator, 1024 * 1024) catch "";
    defer allocator.free(stdout_output);
    const stderr_output = child.stderr.?.readToEndAlloc(allocator, 1024 * 1024) catch "";
    defer allocator.free(stderr_output);

    const result = try child.wait();

    const exit_code: u8 = switch (result) {
        .Exited => |code| code,
        else => 1,
    };

    if (exit_code != 0) {
        return GitHubResult{
            .success = false,
            .output = if (stdout_output.len > 0) try allocator.dupe(u8, stdout_output) else null,
            .error_msg = if (stderr_output.len > 0) try allocator.dupe(u8, stderr_output) else "Command failed",
            .exit_code = exit_code,
        };
    }

    return GitHubResult{
        .success = true,
        .output = try allocator.dupe(u8, stdout_output),
        .exit_code = exit_code,
    };
}

/// Create JSON schema for GitHub tool parameters
pub fn createGitHubSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    // args property
    var args_prop = std.json.ObjectMap.init(allocator);
    try args_prop.put("type", std.json.Value{ .string = "array" });
    try args_prop.put("description", std.json.Value{ .string = "GitHub CLI command arguments (without 'gh' prefix)" });

    var items = std.json.ObjectMap.init(allocator);
    try items.put("type", std.json.Value{ .string = "string" });
    try args_prop.put("items", std.json.Value{ .object = items });

    try properties.put("args", std.json.Value{ .object = args_prop });

    try schema.put("properties", std.json.Value{ .object = properties });

    // Required fields
    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "args" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

// ============================================================================
// Helper for cleaning up JSON values in tests
// ============================================================================

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

// ============================================================================
// Tests
// ============================================================================

test "GitHubParams struct" {
    const params = GitHubParams{
        .args = &.{ "pr", "list" },
    };

    try std.testing.expectEqual(@as(usize, 2), params.args.len);
    try std.testing.expectEqualStrings("pr", params.args[0]);
    try std.testing.expectEqualStrings("list", params.args[1]);
}

test "GitHubResult success" {
    const result = GitHubResult{
        .success = true,
        .output = "Pull request #123",
        .exit_code = 0,
    };

    try std.testing.expect(result.success);
    try std.testing.expect(result.output != null);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code.?);
    try std.testing.expect(result.error_msg == null);
}

test "GitHubResult error" {
    const result = GitHubResult{
        .success = false,
        .error_msg = "Command not allowed",
        .exit_code = 1,
    };

    try std.testing.expect(!result.success);
    try std.testing.expect(result.error_msg != null);
    try std.testing.expect(result.output == null);
}

test "ALLOWED_COMMANDS contains expected commands" {
    // Verify key commands are in the allowed list
    const expected_commands = [_][]const u8{ "pr", "issue", "repo", "api", "workflow" };

    for (expected_commands) |expected| {
        var found = false;
        for (ALLOWED_COMMANDS) |cmd| {
            if (std.mem.eql(u8, cmd, expected)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "BLOCKED_PATTERNS contains security-sensitive patterns" {
    // Verify destructive operations are blocked
    const expected_blocked = [_][]const u8{ "delete", "force", "--force", "auth", "secret" };

    for (expected_blocked) |expected| {
        var found = false;
        for (BLOCKED_PATTERNS) |pattern| {
            if (std.mem.eql(u8, pattern, expected)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "createGitHubSchema" {
    const allocator = std.testing.allocator;

    var schema = try createGitHubSchema(allocator);
    defer freeJsonValue(allocator, &schema);

    // Schema should be an object
    try std.testing.expect(schema == .object);

    // Should have type = object
    const type_val = schema.object.get("type").?;
    try std.testing.expectEqualStrings("object", type_val.string);

    // Should have properties
    const props = schema.object.get("properties").?;
    try std.testing.expect(props == .object);

    // Should have args property
    const args_prop = props.object.get("args").?;
    try std.testing.expect(args_prop == .object);

    // args should be an array type
    const args_type = args_prop.object.get("type").?;
    try std.testing.expectEqualStrings("array", args_type.string);

    // Should have required array
    const required = schema.object.get("required").?;
    try std.testing.expect(required == .array);
    try std.testing.expectEqual(@as(usize, 1), required.array.items.len);
}
