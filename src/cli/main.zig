const std = @import("std");
const clap = @import("clap");
const commands = @import("commands.zig");

const debug = std.debug;
const io = std.io;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help                 Display this help and exit.
        \\-v, --version              Display version information.
        \\-l, --print-logs           Print application logs.
        \\<str>...                   The command and its arguments.
        \\
    );

    // Parse the command line arguments
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report parsing errors
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    // Handle help flag
    if (res.args.help != 0) {
        try printHelp();
        return;
    }

    // Handle version flag
    if (res.args.version != 0) {
        try io.getStdOut().writer().print("plue version 0.1.0\n", .{});
        return;
    }

    // Get the command and arguments
    const args = res.positionals[0];
    if (args.len == 0) {
        // No command provided, show welcome message
        try printWelcome();
        return;
    }
    const command = args[0];

    // Store global options
    const global_options = commands.command.CommandOptions{
        .print_logs = res.args.@"print-logs" != 0,
    };

    // Route to appropriate command handler
    if (std.mem.eql(u8, command, "tui")) {
        try commands.tui.execute(allocator, global_options);
    } else if (std.mem.eql(u8, command, "run")) {
        // Handle run command with optional script argument
        const script = if (args.len > 1) args[1] else null;
        try commands.run.execute(allocator, global_options, script);
    } else if (std.mem.eql(u8, command, "generate")) {
        try commands.generate.execute(allocator, global_options);
    } else if (std.mem.eql(u8, command, "scrap")) {
        try commands.scrap.execute(allocator, global_options);
    } else if (std.mem.eql(u8, command, "auth")) {
        try commands.auth.execute(allocator, global_options);
    } else if (std.mem.eql(u8, command, "upgrade")) {
        try commands.upgrade.execute(allocator, global_options);
    } else if (std.mem.eql(u8, command, "serve")) {
        try commands.serve.execute(allocator, global_options);
    } else if (std.mem.eql(u8, command, "models")) {
        try commands.models.execute(allocator, global_options);
    } else {
        try io.getStdErr().writer().print("Unknown command: {s}\n", .{command});
        try printHelp();
        return error.UnknownCommand;
    }
}

fn printWelcome() !void {
    const stdout = io.getStdOut().writer();
    try stdout.print(
        \\Welcome to Plue multi-agent coding assistant CLI!
        \\
        \\Usage: plue [OPTIONS] <COMMAND>
        \\
        \\Try 'plue --help' for more information.
        \\
    , .{});
}

fn printHelp() !void {
    const stdout = io.getStdOut().writer();
    try stdout.print(
        \\Plue multi-agent coding assistant CLI
        \\
        \\Usage: plue [OPTIONS] <COMMAND>
        \\
        \\Commands:
        \\  tui         Launch the terminal user interface
        \\  run         Run a script
        \\  generate    Generate code
        \\  scrap       Scrap command
        \\  auth        Authenticate user
        \\  upgrade     Upgrade the CLI
        \\  serve       Start the server
        \\  models      Manage models
        \\
        \\Options:
        \\  -h, --help        Display this help and exit
        \\  -v, --version     Display version information
        \\  -l, --print-logs  Print application logs
        \\
    , .{});
}
