const std = @import("std");

/// Command argument definition
pub const Arg = struct {
    name: []const u8,
    required: bool = false,
    description: []const u8,
};

/// Command definition
pub const Command = struct {
    name: []const u8,
    aliases: []const []const u8 = &.{},
    args: []const Arg = &.{},
    description: []const u8,
    examples: []const []const u8 = &.{},
};

/// All available commands
pub const COMMANDS = [_]Command{
    .{
        .name = "new",
        .description = "Create a new session",
        .examples = &.{"/new"},
    },
    .{
        .name = "sessions",
        .aliases = &.{"ls"},
        .description = "List all sessions",
        .examples = &.{"/sessions"},
    },
    .{
        .name = "switch",
        .aliases = &.{"sw"},
        .args = &.{.{ .name = "id", .required = true, .description = "Session ID to switch to" }},
        .description = "Switch to a different session",
        .examples = &.{ "/switch abc123", "/sw abc" },
    },
    .{
        .name = "model",
        .aliases = &.{"m"},
        .args = &.{.{ .name = "name", .required = false, .description = "Model name to use" }},
        .description = "List available models or set current model",
        .examples = &.{ "/model", "/model sonnet-4" },
    },
    .{
        .name = "effort",
        .aliases = &.{"e"},
        .args = &.{.{ .name = "level", .required = false, .description = "minimal, low, medium, or high" }},
        .description = "Set reasoning effort level",
        .examples = &.{ "/effort", "/effort high" },
    },
    .{
        .name = "status",
        .description = "Show current session status",
        .examples = &.{"/status"},
    },
    .{
        .name = "undo",
        .args = &.{.{ .name = "n", .required = false, .description = "Number of turns to undo (default: 1)" }},
        .description = "Undo last n conversation turns",
        .examples = &.{ "/undo", "/undo 3" },
    },
    .{
        .name = "mention",
        .aliases = &.{"@"},
        .args = &.{.{ .name = "file", .required = true, .description = "File path to include" }},
        .description = "Include file content in next message",
        .examples = &.{ "/mention src/main.zig", "@README.md" },
    },
    .{
        .name = "diff",
        .description = "Show diffs from current session",
        .examples = &.{"/diff"},
    },
    .{
        .name = "abort",
        .description = "Abort current running task",
        .examples = &.{"/abort"},
    },
    .{
        .name = "clear",
        .aliases = &.{"cls"},
        .description = "Clear the screen",
        .examples = &.{"/clear"},
    },
    .{
        .name = "help",
        .aliases = &.{ "h", "?" },
        .args = &.{.{ .name = "command", .required = false, .description = "Command to get help for" }},
        .description = "Show help for commands",
        .examples = &.{ "/help", "/help model" },
    },
    .{
        .name = "quit",
        .aliases = &.{ "q", "exit" },
        .description = "Exit the application",
        .examples = &.{"/quit"},
    },
};

/// Find a command by name or alias
pub fn findCommand(name: []const u8) ?*const Command {
    for (&COMMANDS) |*cmd| {
        if (std.mem.eql(u8, cmd.name, name)) return cmd;
        for (cmd.aliases) |alias| {
            if (std.mem.eql(u8, alias, name)) return cmd;
        }
    }
    return null;
}

/// Get command completions for a prefix
pub fn getCompletions(allocator: std.mem.Allocator, prefix: []const u8) ![][]const u8 {
    var matches = std.ArrayList([]const u8){};

    for (&COMMANDS) |cmd| {
        if (std.mem.startsWith(u8, cmd.name, prefix)) {
            try matches.append(allocator, cmd.name);
        }
    }

    return matches.toOwnedSlice(allocator);
}

/// Check if input starts with a command prefix
pub fn isCommand(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\n");
    return trimmed.len > 0 and trimmed[0] == '/';
}

/// Format help text for all commands
pub fn formatAllHelp() []const u8 {
    return
        \\Available Commands:
        \\  /new         Create new session
        \\  /sessions    List sessions
        \\  /switch <id> Switch to session
        \\  /model       Change model
        \\  /effort      Set reasoning effort
        \\  /undo [n]    Undo turns
        \\  /mention     Include file
        \\  /abort       Stop current task
        \\  /clear       Clear screen
        \\  /help        Show this help
        \\  /quit        Exit
    ;
}
