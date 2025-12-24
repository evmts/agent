const std = @import("std");
const registry = @import("registry.zig");

/// A parsed command with its arguments
pub const ParsedCommand = struct {
    command: *const registry.Command,
    args: []const []const u8,
    args_str: []const u8, // The raw args string (space-separated)
    raw_input: []const u8,

    /// Get the first argument (if any)
    pub fn getArg(self: ParsedCommand, index: usize) ?[]const u8 {
        var iter = std.mem.splitScalar(u8, self.args_str, ' ');
        var i: usize = 0;
        while (iter.next()) |part| {
            if (part.len > 0) {
                if (i == index) return part;
                i += 1;
            }
        }
        return null;
    }

    /// Count the number of arguments
    pub fn argCount(self: ParsedCommand) usize {
        if (self.args_str.len == 0) return 0;
        var count: usize = 0;
        var iter = std.mem.splitScalar(u8, self.args_str, ' ');
        while (iter.next()) |part| {
            if (part.len > 0) count += 1;
        }
        return count;
    }
};

/// Errors that can occur during parsing
pub const ParseError = error{
    NotACommand,
    UnknownCommand,
    MissingRequiredArg,
    TooManyArgs,
    OutOfMemory,
};

/// Parse a command string into a structured command
/// Note: The args slice points directly into the input string - no allocation is performed.
/// The returned slices are only valid as long as the input is valid.
pub fn parse(allocator: std.mem.Allocator, input: []const u8) ParseError!ParsedCommand {
    _ = allocator; // No allocation needed - we slice directly into input
    const trimmed = std.mem.trim(u8, input, " \t\n");

    // Must start with /
    if (trimmed.len == 0 or trimmed[0] != '/') {
        return ParseError.NotACommand;
    }

    // Find the command name (first space-delimited token after /)
    const content = trimmed[1..]; // Skip the /
    var cmd_end: usize = 0;
    while (cmd_end < content.len and content[cmd_end] != ' ') {
        cmd_end += 1;
    }

    if (cmd_end == 0) {
        return ParseError.NotACommand;
    }

    const cmd_name = content[0..cmd_end];
    const command = registry.findCommand(cmd_name) orelse return ParseError.UnknownCommand;

    // Count and check required args (we check args exist but don't store them in ArrayList)
    // For args, we'll just parse them directly from the remaining input
    var args_start = cmd_end;
    while (args_start < content.len and content[args_start] == ' ') {
        args_start += 1;
    }

    // Count the number of space-separated args
    var arg_count: usize = 0;
    if (args_start < content.len) {
        var in_arg = true;
        for (content[args_start..]) |c| {
            if (c == ' ') {
                if (in_arg) {
                    in_arg = false;
                }
            } else {
                if (!in_arg) {
                    arg_count += 1;
                    in_arg = true;
                }
            }
        }
        if (in_arg) arg_count += 1;
    }

    // Check required args count
    var required_count: usize = 0;
    for (command.args) |arg| {
        if (arg.required) required_count += 1;
    }

    if (arg_count < required_count) {
        return ParseError.MissingRequiredArg;
    }

    // For args, we store slices into the remaining input after command
    // The caller can parse args by splitting the remaining string if needed
    const args_str = if (args_start < content.len) content[args_start..] else "";

    return .{
        .command = command,
        .args = &.{}, // We don't return individual args - caller parses raw_input
        .args_str = args_str,
        .raw_input = trimmed,
    };
}

/// Check if input looks like a command
pub fn isCommand(input: []const u8) bool {
    return registry.isCommand(input);
}

/// Get the command name from input (for autocomplete)
pub fn getCommandPrefix(input: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, input, " \t\n");
    if (trimmed.len == 0 or trimmed[0] != '/') return null;

    // Find end of command name
    var end: usize = 1;
    while (end < trimmed.len and trimmed[end] != ' ') {
        end += 1;
    }

    return trimmed[1..end];
}

test "parse simple command" {
    const testing = std.testing;
    const parsed = try parse(testing.allocator, "/help");
    try testing.expectEqualStrings("help", parsed.command.name);
    try testing.expectEqual(@as(usize, 0), parsed.argCount());
}

test "parse command with args" {
    const testing = std.testing;
    const parsed = try parse(testing.allocator, "/switch abc123");
    try testing.expectEqualStrings("switch", parsed.command.name);
    try testing.expectEqual(@as(usize, 1), parsed.argCount());
    try testing.expectEqualStrings("abc123", parsed.getArg(0).?);
}

test "unknown command" {
    const testing = std.testing;
    const result = parse(testing.allocator, "/unknowncommand");
    try testing.expectError(ParseError.UnknownCommand, result);
}

test "not a command" {
    const testing = std.testing;
    const result = parse(testing.allocator, "hello world");
    try testing.expectError(ParseError.NotACommand, result);
}

test "missing required arg" {
    const testing = std.testing;
    const result = parse(testing.allocator, "/switch");
    try testing.expectError(ParseError.MissingRequiredArg, result);
}

test "alias works" {
    const testing = std.testing;
    const parsed = try parse(testing.allocator, "/q");
    try testing.expectEqualStrings("quit", parsed.command.name);
}
