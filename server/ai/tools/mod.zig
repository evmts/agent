// Tools module - aggregates all agent tools
const std = @import("std");
const client = @import("../client.zig");
const types = @import("../types.zig");

/// Helper to stringify a JSON value to a string
fn stringifySchema(allocator: std.mem.Allocator, value: std.json.Value) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{});
}

// Import all tools
pub const filesystem = @import("filesystem.zig");
pub const grep = @import("grep.zig");
pub const read_file = @import("read_file.zig");
pub const write_file = @import("write_file.zig");
pub const multiedit = @import("multiedit.zig");
pub const web_fetch = @import("web_fetch.zig");
pub const github = @import("github.zig");

// Re-export key types
pub const GrepParams = grep.GrepParams;
pub const GrepResult = grep.GrepResult;
pub const GrepMatch = grep.GrepMatch;
pub const ReadFileParams = read_file.ReadFileParams;
pub const ReadFileResult = read_file.ReadFileResult;
pub const WriteFileParams = write_file.WriteFileParams;
pub const WriteFileResult = write_file.WriteFileResult;
pub const MultieditParams = multiedit.MultieditParams;
pub const MultieditResult = multiedit.MultieditResult;
pub const EditOperation = multiedit.EditOperation;
pub const WebFetchParams = web_fetch.WebFetchParams;
pub const WebFetchResult = web_fetch.WebFetchResult;
pub const GitHubParams = github.GitHubParams;
pub const GitHubResult = github.GitHubResult;

/// Tool names
pub const ToolName = enum {
    grep,
    read_file,
    write_file,
    multiedit,
    web_fetch,
    github,

    pub fn toString(self: ToolName) []const u8 {
        return switch (self) {
            .grep => "grep",
            .read_file => "readFile",
            .write_file => "writeFile",
            .multiedit => "multiedit",
            .web_fetch => "webFetch",
            .github => "github",
        };
    }
};

/// All tool names for iteration
pub const ALL_TOOLS: []const ToolName = &.{
    .grep,
    .read_file,
    .write_file,
    .multiedit,
    .web_fetch,
    .github,
};

/// Get tools enabled for a specific agent
pub fn getEnabledTools(
    allocator: std.mem.Allocator,
    agent_name: []const u8,
    enabled_config: types.AgentConfig.ToolsEnabled,
) ![]client.Tool {
    var tools = std.ArrayList(client.Tool){};
    errdefer tools.deinit(allocator);

    _ = agent_name;

    if (enabled_config.grep) {
        try tools.append(allocator, client.Tool{
            .name = "grep",
            .description = "Search for patterns in files using ripgrep",
            .input_schema = try stringifySchema(allocator, try grep.createGrepSchema(allocator)),
        });
    }

    if (enabled_config.read_file) {
        try tools.append(allocator, client.Tool{
            .name = "readFile",
            .description = "Read a file with line numbers",
            .input_schema = try stringifySchema(allocator, try read_file.createReadFileSchema(allocator)),
        });
    }

    if (enabled_config.write_file) {
        try tools.append(allocator, client.Tool{
            .name = "writeFile",
            .description = "Write content to a file",
            .input_schema = try stringifySchema(allocator, try write_file.createWriteFileSchema(allocator)),
        });
    }

    if (enabled_config.multiedit) {
        try tools.append(allocator, client.Tool{
            .name = "multiedit",
            .description = "Apply multiple find-replace edits to a file",
            .input_schema = try stringifySchema(allocator, try multiedit.createMultieditSchema(allocator)),
        });
    }

    if (enabled_config.web_fetch) {
        try tools.append(allocator, client.Tool{
            .name = "webFetch",
            .description = "Fetch content from a URL",
            .input_schema = try stringifySchema(allocator, try web_fetch.createWebFetchSchema(allocator)),
        });
    }

    if (enabled_config.github) {
        try tools.append(allocator, client.Tool{
            .name = "github",
            .description = "Execute GitHub CLI commands",
            .input_schema = try stringifySchema(allocator, try github.createGitHubSchema(allocator)),
        });
    }

    return tools.toOwnedSlice(allocator);
}

/// Execute a tool by name
pub fn executeTool(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    input: std.json.Value,
    ctx: types.ToolContext,
) ![]const u8 {
    if (std.mem.eql(u8, tool_name, "grep")) {
        const params = try parseGrepParams(input);
        const result = try grep.grepImpl(allocator, params, ctx.working_dir);
        return result.formatted_output orelse result.error_msg orelse "No output";
    }

    if (std.mem.eql(u8, tool_name, "readFile")) {
        const params = try parseReadFileParams(input);
        const result = try read_file.readFileImpl(allocator, params, ctx);
        return result.content orelse result.error_msg orelse "No output";
    }

    if (std.mem.eql(u8, tool_name, "writeFile")) {
        const params = try parseWriteFileParams(input);
        const result = try write_file.writeFileImpl(allocator, params, ctx);
        if (result.success) {
            return try std.fmt.allocPrint(allocator, "Wrote {d} bytes", .{result.bytes_written orelse 0});
        }
        return result.error_msg orelse "Write failed";
    }

    if (std.mem.eql(u8, tool_name, "multiedit")) {
        const params = try parseMultieditParams(allocator, input);
        const result = try multiedit.multieditImpl(allocator, params, ctx);
        if (result.success) {
            return try std.fmt.allocPrint(allocator, "Applied {d} edits", .{result.edits_applied});
        }
        return result.error_msg orelse "Edit failed";
    }

    if (std.mem.eql(u8, tool_name, "webFetch")) {
        const params = try parseWebFetchParams(input);
        const result = try web_fetch.webFetchImpl(allocator, params);
        return result.content orelse result.error_msg orelse "No content";
    }

    if (std.mem.eql(u8, tool_name, "github")) {
        const params = try parseGitHubParams(allocator, input);
        const result = try github.githubImpl(allocator, params, ctx.working_dir);
        return result.output orelse result.error_msg orelse "No output";
    }

    return error.ToolExecutionFailed;
}

// Parameter parsing helpers
fn parseGrepParams(input: std.json.Value) !GrepParams {
    const obj = input.object;
    return GrepParams{
        .pattern = if (obj.get("pattern")) |v| v.string else return error.InvalidToolParameters,
        .path = if (obj.get("path")) |v| v.string else null,
        .glob = if (obj.get("glob")) |v| v.string else null,
        .multiline = if (obj.get("multiline")) |v| v.bool else false,
        .case_insensitive = if (obj.get("caseInsensitive")) |v| v.bool else false,
    };
}

fn parseReadFileParams(input: std.json.Value) !ReadFileParams {
    const obj = input.object;
    return ReadFileParams{
        .file_path = if (obj.get("file_path")) |v| v.string else return error.InvalidToolParameters,
        .offset = if (obj.get("offset")) |v| @intCast(v.integer) else null,
        .limit = if (obj.get("limit")) |v| @intCast(v.integer) else null,
    };
}

fn parseWriteFileParams(input: std.json.Value) !WriteFileParams {
    const obj = input.object;
    return WriteFileParams{
        .file_path = if (obj.get("file_path")) |v| v.string else return error.InvalidToolParameters,
        .content = if (obj.get("content")) |v| v.string else return error.InvalidToolParameters,
    };
}

fn parseMultieditParams(allocator: std.mem.Allocator, input: std.json.Value) !MultieditParams {
    const obj = input.object;
    const file_path = if (obj.get("file_path")) |v| v.string else return error.InvalidToolParameters;
    const edits_arr = if (obj.get("edits")) |v| v.array else return error.InvalidToolParameters;

    var edits = std.ArrayList(EditOperation){};
    errdefer edits.deinit(allocator);

    for (edits_arr.items) |edit| {
        const edit_obj = edit.object;
        try edits.append(allocator, .{
            .old_string = if (edit_obj.get("old_string")) |v| v.string else continue,
            .new_string = if (edit_obj.get("new_string")) |v| v.string else continue,
            .replace_all = if (edit_obj.get("replace_all")) |v| v.bool else false,
        });
    }

    return MultieditParams{
        .file_path = file_path,
        .edits = try edits.toOwnedSlice(allocator),
    };
}

fn parseWebFetchParams(input: std.json.Value) !WebFetchParams {
    const obj = input.object;
    return WebFetchParams{
        .url = if (obj.get("url")) |v| v.string else return error.InvalidToolParameters,
        .timeout_ms = if (obj.get("timeout_ms")) |v| @intCast(v.integer) else 30000,
    };
}

fn parseGitHubParams(allocator: std.mem.Allocator, input: std.json.Value) !GitHubParams {
    const obj = input.object;
    const args_arr = if (obj.get("args")) |v| v.array else return error.InvalidToolParameters;

    var args = std.ArrayList([]const u8){};
    errdefer args.deinit(allocator);

    for (args_arr.items) |arg| {
        try args.append(allocator, arg.string);
    }

    return GitHubParams{
        .args = try args.toOwnedSlice(allocator),
    };
}

test {
    std.testing.refAllDecls(@This());
}
