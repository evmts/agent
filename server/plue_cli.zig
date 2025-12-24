//! Plue CLI Entry Point
//!
//! This is the main entry point for the `plue` CLI tool.
//! It can be built as a standalone executable.

const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse and execute command
    var cli_args = try cli.parseArgs(allocator, args);
    defer cli_args.deinit();

    try cli.execute(allocator, cli_args);
}
