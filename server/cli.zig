//! Plue CLI - Workflow and Prompt Management
//!
//! Commands:
//!   plue workflow list                     - List all workflows
//!   plue workflow run <name>               - Run workflow manually
//!   plue workflow run <name> --input k=v   - Run with inputs
//!   plue workflow lint                     - Lint .py and .prompt.md files
//!   plue run list                          - List recent runs
//!   plue run view <run-id>                 - View run details
//!   plue run watch <run-id>                - Watch live run (SSE stream)
//!   plue run cancel <run-id>               - Cancel running workflow
//!   plue prompt preview <file>             - Render prompt with sample inputs
//!   plue prompt test <file>                - Test prompt execution

const std = @import("std");
const workflows = @import("workflows/mod.zig");

const log = std.log.scoped(.cli);

// Simple writer wrappers for stdout/stderr using std.debug.print
const StdoutWriter = struct {
    pub const Error = error{};
    pub const Writer = std.io.Writer(StdoutWriter, Error, write);

    pub fn write(self: StdoutWriter, bytes: []const u8) Error!usize {
        _ = self;
        std.debug.print("{s}", .{bytes});
        return bytes.len;
    }

    pub fn writeAll(self: StdoutWriter, bytes: []const u8) Error!void {
        _ = try self.write(bytes);
    }

    pub fn print(self: StdoutWriter, comptime format: []const u8, args: anytype) Error!void {
        _ = self;
        std.debug.print(format, args);
    }

    pub fn writer(self: StdoutWriter) Writer {
        return .{ .context = self };
    }
};

const StderrWriter = struct {
    pub const Error = error{};
    pub const Writer = std.io.Writer(StderrWriter, Error, write);

    pub fn write(self: StderrWriter, bytes: []const u8) Error!usize {
        _ = self;
        std.debug.print("{s}", .{bytes});
        return bytes.len;
    }

    pub fn writeAll(self: StderrWriter, bytes: []const u8) Error!void {
        _ = try self.write(bytes);
    }

    pub fn print(self: StderrWriter, comptime format: []const u8, args: anytype) Error!void {
        _ = self;
        std.debug.print(format, args);
    }

    pub fn writer(self: StderrWriter) Writer {
        return .{ .context = self };
    }
};


pub const Command = enum {
    workflow_list,
    workflow_run,
    workflow_lint,
    run_list,
    run_view,
    run_watch,
    run_cancel,
    prompt_preview,
    prompt_test,
    help,
    unknown,
};

pub const CliArgs = struct {
    command: Command,
    args: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CliArgs) void {
        _ = self;
        // Args are owned by process.argsAlloc, freed by caller
    }
};

/// Parse CLI arguments and determine command
pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !CliArgs {
    if (args.len < 2) {
        return CliArgs{
            .command = .help,
            .args = args,
            .allocator = allocator,
        };
    }

    const subcommand = args[1];
    const rest = if (args.len > 2) args[2..] else args[0..0];

    const command: Command = blk: {
        if (std.mem.eql(u8, subcommand, "workflow")) {
            if (rest.len == 0) break :blk .help;
            const verb = rest[0];
            if (std.mem.eql(u8, verb, "list")) break :blk .workflow_list;
            if (std.mem.eql(u8, verb, "run")) break :blk .workflow_run;
            if (std.mem.eql(u8, verb, "lint")) break :blk .workflow_lint;
            break :blk .unknown;
        } else if (std.mem.eql(u8, subcommand, "run")) {
            if (rest.len == 0) break :blk .help;
            const verb = rest[0];
            if (std.mem.eql(u8, verb, "list")) break :blk .run_list;
            if (std.mem.eql(u8, verb, "view")) break :blk .run_view;
            if (std.mem.eql(u8, verb, "watch")) break :blk .run_watch;
            if (std.mem.eql(u8, verb, "cancel")) break :blk .run_cancel;
            break :blk .unknown;
        } else if (std.mem.eql(u8, subcommand, "prompt")) {
            if (rest.len == 0) break :blk .help;
            const verb = rest[0];
            if (std.mem.eql(u8, verb, "preview")) break :blk .prompt_preview;
            if (std.mem.eql(u8, verb, "test")) break :blk .prompt_test;
            break :blk .unknown;
        } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
            break :blk .help;
        } else {
            break :blk .unknown;
        }
    };

    return CliArgs{
        .command = command,
        .args = rest,
        .allocator = allocator,
    };
}

/// Print help message
pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Plue CLI - Workflow and Prompt Management
        \\
        \\Usage:
        \\  plue <command> [options]
        \\
        \\Commands:
        \\  Workflow Management:
        \\    workflow list                   List all workflows in repository
        \\    workflow run <name>             Run workflow manually
        \\    workflow run <name> --input k=v Run with manual inputs
        \\    workflow lint                   Lint .py and .prompt.md files
        \\
        \\  Run Management:
        \\    run list                        List recent workflow runs
        \\    run view <run-id>               View run details and logs
        \\    run watch <run-id>              Watch live run (SSE stream)
        \\    run cancel <run-id>             Cancel running workflow
        \\
        \\  Prompt Development:
        \\    prompt preview <file>           Render prompt with sample inputs
        \\    prompt test <file>              Test prompt execution
        \\
        \\  General:
        \\    help                            Show this help message
        \\
        \\Examples:
        \\  plue workflow list
        \\  plue workflow run ci
        \\  plue run watch 123
        \\  plue prompt preview .plue/prompts/CodeReview.prompt.md
        \\
        \\For more information, see: docs/workflows-prd.md
        \\
    );
}

/// Execute a CLI command
pub fn execute(allocator: std.mem.Allocator, cli_args: CliArgs) !void {
    // Note: Using std.debug.print for simplicity due to Zig 0.15 stdio API changes
    // In production, we'd properly handle stdout/stderr file descriptors
    const stdout = StdoutWriter{};
    const stderr = StderrWriter{};

    switch (cli_args.command) {
        .help => {
            try printHelp(stdout);
            return;
        },
        .unknown => {
            try stderr.writeAll("Error: Unknown command\n\n");
            try printHelp(stderr);
            return error.UnknownCommand;
        },
        .workflow_list => {
            try executeWorkflowList(allocator, stdout);
        },
        .workflow_run => {
            if (cli_args.args.len < 2) {
                try stderr.writeAll("Error: workflow name required\n");
                try stderr.writeAll("Usage: plue workflow run <name>\n");
                return error.MissingArgument;
            }
            const workflow_name = cli_args.args[1];
            try executeWorkflowRun(allocator, stdout, workflow_name);
        },
        .workflow_lint => {
            try executeWorkflowLint(allocator, stdout);
        },
        .run_list => {
            try executeRunList(allocator, stdout);
        },
        .run_view => {
            if (cli_args.args.len < 2) {
                try stderr.writeAll("Error: run ID required\n");
                try stderr.writeAll("Usage: plue run view <run-id>\n");
                return error.MissingArgument;
            }
            const run_id = try std.fmt.parseInt(i32, cli_args.args[1], 10);
            try executeRunView(allocator, stdout, run_id);
        },
        .run_watch => {
            if (cli_args.args.len < 2) {
                try stderr.writeAll("Error: run ID required\n");
                try stderr.writeAll("Usage: plue run watch <run-id>\n");
                return error.MissingArgument;
            }
            const run_id = try std.fmt.parseInt(i32, cli_args.args[1], 10);
            try executeRunWatch(allocator, stdout, run_id);
        },
        .run_cancel => {
            if (cli_args.args.len < 2) {
                try stderr.writeAll("Error: run ID required\n");
                try stderr.writeAll("Usage: plue run cancel <run-id>\n");
                return error.MissingArgument;
            }
            const run_id = try std.fmt.parseInt(i32, cli_args.args[1], 10);
            try executeRunCancel(allocator, stdout, run_id);
        },
        .prompt_preview => {
            if (cli_args.args.len < 2) {
                try stderr.writeAll("Error: prompt file required\n");
                try stderr.writeAll("Usage: plue prompt preview <file>\n");
                return error.MissingArgument;
            }
            const file_path = cli_args.args[1];
            try executePromptPreview(allocator, stdout, file_path);
        },
        .prompt_test => {
            if (cli_args.args.len < 2) {
                try stderr.writeAll("Error: prompt file required\n");
                try stderr.writeAll("Usage: plue prompt test <file>\n");
                return error.MissingArgument;
            }
            const file_path = cli_args.args[1];
            try executePromptTest(allocator, stdout, file_path);
        },
    }
}

// ============================================================================
// Command Implementations
// ============================================================================

fn executeWorkflowList(allocator: std.mem.Allocator, writer: anytype) !void {
    // Scan .plue/workflows/ directory for workflow files
    const workflows_dir = ".plue/workflows";

    var dir = std.fs.cwd().openDir(workflows_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            try writer.writeAll("No workflows found. Create workflows in .plue/workflows/\n");
            return;
        }
        return err;
    };
    defer dir.close();

    try writer.writeAll("Workflows:\n");

    var iter = dir.iterate();
    var count: usize = 0;
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".py")) continue;

        // Parse the workflow to get its name
        const content = try dir.readFileAlloc(allocator, entry.name, 1024 * 1024);
        defer allocator.free(content);

        var evaluator = workflows.Evaluator.init(allocator);
        var result = evaluator.evaluateSource(content, entry.name) catch |err| {
            try writer.print("  {s} (parse error: {s})\n", .{ entry.name, @errorName(err) });
            continue;
        };
        defer result.deinit(allocator);

        if (result.workflows.len > 0) {
            const workflow = result.workflows[0];
            try writer.print("  {s} - {s} ({d} steps, {d} triggers)\n", .{
                workflow.name,
                entry.name,
                workflow.steps.len,
                workflow.triggers.len,
            });
            count += 1;
        }
    }

    if (count == 0) {
        try writer.writeAll("  (no valid workflows found)\n");
    }
}

fn executeWorkflowRun(allocator: std.mem.Allocator, writer: anytype, workflow_name: []const u8) !void {
    try writer.print("Running workflow: {s}\n", .{workflow_name});
    try writer.writeAll("Note: This CLI is currently a stub. To run workflows:\n");
    try writer.writeAll("  1. Start the server: zig build run\n");
    try writer.writeAll("  2. Use the API: POST /api/workflows/run\n");
    try writer.writeAll("  3. Or use the web UI at http://localhost:4000\n");
    _ = allocator;
}

fn executeWorkflowLint(allocator: std.mem.Allocator, writer: anytype) !void {
    const workflows_dir = ".plue/workflows";
    const prompts_dir = ".plue/prompts";

    var total_files: usize = 0;
    var total_errors: usize = 0;

    // Lint workflow files
    try writer.writeAll("Linting workflows...\n");
    var dir = std.fs.cwd().openDir(workflows_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            try writer.writeAll("  (no workflows directory found)\n");
        } else {
            return err;
        }

        // Skip to prompts section
        try writer.writeAll("\nLinting prompts...\n");
        var prompts_dir_handle = std.fs.cwd().openDir(prompts_dir, .{ .iterate = true }) catch |prompt_err| {
            if (prompt_err == error.FileNotFound) {
                try writer.writeAll("  (no prompts directory found)\n");
            } else {
                return prompt_err;
            }
            try writer.print("\nLint complete: {d} files, {d} errors\n", .{ total_files, total_errors });
            return if (total_errors > 0) error.LintFailed else {};
        };
        defer prompts_dir_handle.close();

        var prompt_iter = prompts_dir_handle.iterate();
        while (try prompt_iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".prompt.md")) continue;

            total_files += 1;

            const file_path = try std.fs.path.join(allocator, &[_][]const u8{ prompts_dir, entry.name });
            defer allocator.free(file_path);

            var prompt_def = workflows.prompt.parsePromptFile(allocator, file_path) catch |parse_err| {
                try writer.print("  ✗ {s}: {s}\n", .{ entry.name, @errorName(parse_err) });
                total_errors += 1;
                continue;
            };
            defer prompt_def.deinit();

            try writer.print("  ✓ {s} ({s})\n", .{ entry.name, prompt_def.name });
        }

        try writer.print("\nLint complete: {d} files, {d} errors\n", .{ total_files, total_errors });
        return if (total_errors > 0) error.LintFailed else {};
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".py")) continue;

        total_files += 1;
        const content = try dir.readFileAlloc(allocator, entry.name, 1024 * 1024);
        defer allocator.free(content);

        var evaluator = workflows.Evaluator.init(allocator);
        var result = evaluator.evaluateSource(content, entry.name) catch |err| {
            try writer.print("  ✗ {s}: {s}\n", .{ entry.name, @errorName(err) });
            total_errors += 1;
            continue;
        };
        defer result.deinit(allocator);

        // Validate each workflow
        for (result.workflows) |workflow| {
            var validation = try workflows.validateWorkflow(allocator, &workflow);
            defer validation.deinit();

            if (!validation.valid) {
                try writer.print("  ✗ {s} ({s}): validation failed\n", .{ entry.name, workflow.name });
                for (validation.errors) |issue| {
                    try writer.print("      {s}\n", .{issue.message});
                }
                total_errors += validation.errors.len;
            } else {
                try writer.print("  ✓ {s} ({s})\n", .{ entry.name, workflow.name });
            }
        }
    }

    try writer.print("\nLint complete: {d} files, {d} errors\n", .{ total_files, total_errors });
}

fn executeRunList(_: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("Recent workflow runs:\n");
    try writer.writeAll("Note: This CLI is currently a stub. To view runs:\n");
    try writer.writeAll("  1. Use the API: GET /api/workflows/runs\n");
    try writer.writeAll("  2. Or use the web UI at http://localhost:4000\n");
}

fn executeRunView(_: std.mem.Allocator, writer: anytype, run_id: i32) !void {
    try writer.print("Viewing run {d}:\n", .{run_id});
    try writer.writeAll("Note: This CLI is currently a stub. To view run details:\n");
    try writer.writeAll("  1. Use the API: GET /api/workflows/runs/{d}\n");
    try writer.writeAll("  2. Or use the web UI at http://localhost:4000/workflows/runs/{d}\n");
}

fn executeRunWatch(_: std.mem.Allocator, writer: anytype, run_id: i32) !void {
    try writer.print("Watching run {d}...\n", .{run_id});
    try writer.writeAll("Note: This CLI is currently a stub. To watch a live run:\n");
    try writer.writeAll("  1. Use SSE: GET /api/workflows/runs/{d}/stream\n");
    try writer.writeAll("  2. Or use the web UI at http://localhost:4000/workflows/runs/{d}\n");
}

fn executeRunCancel(_: std.mem.Allocator, writer: anytype, run_id: i32) !void {
    try writer.print("Cancelling run {d}...\n", .{run_id});
    try writer.writeAll("Note: This CLI is currently a stub. To cancel a run:\n");
    try writer.writeAll("  1. Use the API: POST /api/workflows/runs/{d}/cancel\n");
    try writer.writeAll("  2. Or use the web UI at http://localhost:4000/workflows/runs/{d}\n");
}

fn executePromptPreview(allocator: std.mem.Allocator, writer: anytype, file_path: []const u8) !void {
    try writer.print("Previewing prompt: {s}\n\n", .{file_path});

    var prompt_def = try workflows.prompt.parsePromptFile(allocator, file_path);
    defer prompt_def.deinit();

    try writer.print("Name: {s}\n", .{prompt_def.name});
    try writer.print("Client: {s}\n", .{prompt_def.client});
    try writer.print("Type: {s}\n", .{prompt_def.prompt_type});
    try writer.print("Max turns: {d}\n", .{prompt_def.max_turns});

    try writer.writeAll("\nTemplate body:\n");
    try writer.writeAll("---\n");
    try writer.print("{s}\n", .{prompt_def.body_template});
    try writer.writeAll("---\n");
}

fn executePromptTest(allocator: std.mem.Allocator, writer: anytype, file_path: []const u8) !void {
    try writer.print("Testing prompt: {s}\n", .{file_path});
    try writer.writeAll("Note: This CLI is currently a stub. To test a prompt:\n");
    try writer.writeAll("  1. Use the API: POST /api/prompts/test\n");
    try writer.writeAll("  2. Or use the web UI prompt editor\n");
    _ = allocator;
}

// ============================================================================
// Tests
// ============================================================================

test "parseArgs - help" {
    const allocator = std.testing.allocator;
    const args = &[_][]const u8{ "plue", "help" };
    const result = try parseArgs(allocator, args);
    try std.testing.expectEqual(Command.help, result.command);
}

test "parseArgs - workflow list" {
    const allocator = std.testing.allocator;
    const args = &[_][]const u8{ "plue", "workflow", "list" };
    const result = try parseArgs(allocator, args);
    try std.testing.expectEqual(Command.workflow_list, result.command);
}

test "parseArgs - workflow run" {
    const allocator = std.testing.allocator;
    const args = &[_][]const u8{ "plue", "workflow", "run", "ci" };
    const result = try parseArgs(allocator, args);
    try std.testing.expectEqual(Command.workflow_run, result.command);
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("ci", result.args[1]);
}

test "parseArgs - run view" {
    const allocator = std.testing.allocator;
    const args = &[_][]const u8{ "plue", "run", "view", "123" };
    const result = try parseArgs(allocator, args);
    try std.testing.expectEqual(Command.run_view, result.command);
}

test "parseArgs - prompt preview" {
    const allocator = std.testing.allocator;
    const args = &[_][]const u8{ "plue", "prompt", "preview", "test.prompt.md" };
    const result = try parseArgs(allocator, args);
    try std.testing.expectEqual(Command.prompt_preview, result.command);
}

test "parseArgs - unknown command" {
    const allocator = std.testing.allocator;
    const args = &[_][]const u8{ "plue", "foo" };
    const result = try parseArgs(allocator, args);
    try std.testing.expectEqual(Command.unknown, result.command);
}
