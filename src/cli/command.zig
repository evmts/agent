const std = @import("std");

pub const CommandOptions = struct {
    print_logs: bool = false,
};

pub const CommandInfo = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    examples: []const []const u8 = &.{},
};

pub fn notImplemented(command_name: []const u8) !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.print("❌ The '{s}' command is not yet implemented.\n", .{command_name});
    try stderr.print("This feature is coming soon!\n", .{});
}

pub fn printCommandHelp(info: CommandInfo) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s} - {s}\n\n", .{ info.name, info.description });
    try stdout.print("Usage: {s}\n", .{info.usage});
    
    if (info.examples.len > 0) {
        try stdout.print("\nExamples:\n", .{});
        for (info.examples) |example| {
            try stdout.print("  {s}\n", .{example});
        }
    }
}

pub fn logInfo(options: CommandOptions, comptime fmt: []const u8, args: anytype) !void {
    if (options.print_logs) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("[INFO] " ++ fmt ++ "\n", args);
    }
}

pub fn printSuccess(comptime fmt: []const u8, args: anytype) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("✅ " ++ fmt ++ "\n", args);
}

pub fn printError(comptime fmt: []const u8, args: anytype) !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.print("❌ " ++ fmt ++ "\n", args);
}

pub fn printWarning(comptime fmt: []const u8, args: anytype) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("⚠️  " ++ fmt ++ "\n", args);
}