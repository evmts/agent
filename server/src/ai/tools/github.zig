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
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    try args.append("gh");
    for (params.args) |arg| {
        try args.append(arg);
    }

    // Spawn gh process
    var child = std.process.Child.init(args.items, allocator);
    child.cwd = working_dir;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read output
    const stdout = child.stdout.?.reader();
    const stderr = child.stderr.?.reader();

    var stdout_buf = std.ArrayList(u8).init(allocator);
    defer stdout_buf.deinit();

    var stderr_buf = std.ArrayList(u8).init(allocator);
    defer stderr_buf.deinit();

    stdout.readAllArrayList(&stdout_buf, 1024 * 1024) catch {};
    stderr.readAllArrayList(&stderr_buf, 1024 * 1024) catch {};

    const result = try child.wait();

    const exit_code: u8 = switch (result) {
        .Exited => |code| code,
        else => 1,
    };

    if (exit_code != 0) {
        return GitHubResult{
            .success = false,
            .output = if (stdout_buf.items.len > 0) try stdout_buf.toOwnedSlice() else null,
            .error_msg = if (stderr_buf.items.len > 0) try stderr_buf.toOwnedSlice() else "Command failed",
            .exit_code = exit_code,
        };
    }

    return GitHubResult{
        .success = true,
        .output = try stdout_buf.toOwnedSlice(),
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
