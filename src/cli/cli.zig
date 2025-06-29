const std = @import("std");
const clap = @import("clap");
const commands = @import("commands.zig");

const Cli = @This();

allocator: std.mem.Allocator,
args: [][:0]u8 = &.{},

const cli_params = clap.parseParamsComptime(
    \\-h, --help                 Display this help and exit.
    \\-v, --version              Display version information.
    \\-l, --print-logs           Print application logs.
    \\<str>...                   The command and its arguments.
    \\
);

pub fn init(allocator: std.mem.Allocator) !Cli {
    return .{
        .allocator = allocator,
        .args = try std.process.argsAlloc(allocator),
    };
}

pub fn deinit(self: *Cli) void {
    if (self.args.len > 0) {
        std.process.argsFree(self.allocator, self.args);
    }
}

pub fn run(self: *Cli) !void {
    // Parse the command line arguments
    var diag = clap.Diagnostic{};
    const res = clap.parse(clap.Help, &cli_params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = self.allocator,
    }) catch |err| {
        // Report parsing errors
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    // Handle help flag
    if (res.args.help != 0) {
        try self.printHelp();
        return;
    }

    // Handle version flag
    if (res.args.version != 0) {
        try self.printVersion();
        return;
    }

    // Get the command and arguments
    const args = res.positionals[0];
    if (args.len == 0) {
        // No command provided, show welcome message
        try self.printWelcome();
        return;
    }
    const command = args[0];

    // Store global options
    const global_options = commands.command.CommandOptions{
        .print_logs = res.args.@"print-logs" != 0,
    };

    // Route to appropriate command handler
    try self.routeCommand(command, args, global_options);
}

fn routeCommand(self: *Cli, command: []const u8, args: []const []const u8, options: commands.command.CommandOptions) !void {
    if (std.mem.eql(u8, command, "tui")) {
        try commands.tui.execute(self.allocator, options);
    } else if (std.mem.eql(u8, command, "run")) {
        // Handle run command with optional script argument
        const script = if (args.len > 1) args[1] else null;
        try commands.run.execute(self.allocator, options, script);
    } else if (std.mem.eql(u8, command, "generate")) {
        try commands.generate.execute(self.allocator, options);
    } else if (std.mem.eql(u8, command, "scrap")) {
        try commands.scrap.execute(self.allocator, options);
    } else if (std.mem.eql(u8, command, "auth")) {
        try commands.auth.execute(self.allocator, options);
    } else if (std.mem.eql(u8, command, "upgrade")) {
        try commands.upgrade.execute(self.allocator, options);
    } else if (std.mem.eql(u8, command, "serve")) {
        try commands.serve.execute(self.allocator, options);
    } else if (std.mem.eql(u8, command, "models")) {
        try commands.models.execute(self.allocator, options);
    } else {
        try std.io.getStdErr().writer().print("Unknown command: {s}\n", .{command});
        try self.printHelp();
        return error.UnknownCommand;
    }
}

fn printWelcome(self: *Cli) !void {
    _ = self;
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Welcome to Plue multi-agent coding assistant CLI!
        \\
        \\Usage: plue [OPTIONS] <COMMAND>
        \\
        \\Try 'plue --help' for more information.
        \\
    , .{});
}

fn printVersion(self: *Cli) !void {
    _ = self;
    try std.io.getStdOut().writer().print("plue version 0.1.0\n", .{});
}

fn printHelp(self: *Cli) !void {
    _ = self;
    const stdout = std.io.getStdOut().writer();
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