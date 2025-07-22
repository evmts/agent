const std = @import("std");
const clap = @import("clap");
const StartCommand = @import("commands/start.zig");

const Subcommands = enum {
    start,
};

const main_parsers = .{
    .command = clap.parsers.enumeration(Subcommands),
};

const main_params = clap.parseParamsComptime(
    \\-h, --help Display this help and exit.
    \\<command>
);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    
    var iter = std.process.ArgIterator.init();
    _ = iter.next();
    
    if (iter.next()) |first_arg| {
        if (std.mem.eql(u8, first_arg, "start")) {
            try StartCommand.run(allocator, &iter);
            return;
        }
        if (std.mem.eql(u8, first_arg, "-h") or std.mem.eql(u8, first_arg, "--help")) {
            try printHelp();
            return;
        }
        std.log.err("Unknown command: {s}", .{first_arg});
        try printHelp();
        return;
    }
    
    std.log.info("Hello, world!", .{});
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("plue - A git wrapper application\n\n");
    try stdout.writeAll("Usage: plue [command]\n\n");
    try stdout.writeAll("Commands:\n");
    try stdout.writeAll("  start    Start command that blocks gracefully\n");
    try stdout.writeAll("  -h, --help Show this help\n");
}

test "main command works" {
    try std.testing.expect(true);
}