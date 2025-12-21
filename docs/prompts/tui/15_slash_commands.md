# 15: Slash Commands

## Goal

Implement slash command parsing, execution, and help system.

## Context

- Users can type `/command` to trigger actions
- Commands include: /new, /sessions, /switch, /model, /effort, /help, /quit, etc.
- Reference: `/Users/williamcory/plue/tui/src/index.ts` command handling

## Commands

| Command | Args | Description |
|---------|------|-------------|
| `/new` | - | Create new session |
| `/sessions` | - | List all sessions |
| `/switch` | `<id>` | Switch to session |
| `/model` | `[name]` | List or set model |
| `/effort` | `[level]` | Set reasoning effort |
| `/status` | - | Show session status |
| `/undo` | `[n]` | Undo last n turns |
| `/mention` | `<file>` | Include file in message |
| `/diff` | - | Show session diffs |
| `/abort` | - | Abort current task |
| `/clear` | - | Clear screen |
| `/help` | `[cmd]` | Show help |
| `/quit`, `/q` | - | Exit |

## Tasks

### 1. Create Command Registry (src/commands/registry.zig)

```zig
const std = @import("std");

pub const Command = struct {
    name: []const u8,
    aliases: []const []const u8 = &.{},
    args: []const Arg = &.{},
    description: []const u8,
    examples: []const []const u8 = &.{},

    pub const Arg = struct {
        name: []const u8,
        required: bool = false,
        description: []const u8,
    };
};

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
        .aliases = &.{"h", "?"},
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

pub fn findCommand(name: []const u8) ?*const Command {
    for (&COMMANDS) |*cmd| {
        if (std.mem.eql(u8, cmd.name, name)) return cmd;
        for (cmd.aliases) |alias| {
            if (std.mem.eql(u8, alias, name)) return cmd;
        }
    }
    return null;
}

pub fn getCompletions(prefix: []const u8) []const []const u8 {
    var matches: [COMMANDS.len][]const u8 = undefined;
    var count: usize = 0;

    for (&COMMANDS) |cmd| {
        if (std.mem.startsWith(u8, cmd.name, prefix)) {
            matches[count] = cmd.name;
            count += 1;
        }
    }

    return matches[0..count];
}
```

### 2. Create Command Parser (src/commands/parser.zig)

```zig
const std = @import("std");
const registry = @import("registry.zig");

pub const ParsedCommand = struct {
    command: *const registry.Command,
    args: []const []const u8,
    raw_input: []const u8,
};

pub const ParseError = error{
    NotACommand,
    UnknownCommand,
    MissingRequiredArg,
    TooManyArgs,
};

pub fn parse(allocator: std.mem.Allocator, input: []const u8) ParseError!ParsedCommand {
    const trimmed = std.mem.trim(u8, input, " \t\n");

    // Must start with /
    if (trimmed.len == 0 or trimmed[0] != '/') {
        return ParseError.NotACommand;
    }

    // Split command and args
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    var iter = std.mem.split(u8, trimmed[1..], " ");
    while (iter.next()) |part| {
        if (part.len > 0) {
            parts.append(part) catch return ParseError.UnknownCommand;
        }
    }

    if (parts.items.len == 0) {
        return ParseError.NotACommand;
    }

    const cmd_name = parts.items[0];
    const command = registry.findCommand(cmd_name) orelse return ParseError.UnknownCommand;

    // Check required args
    const args = parts.items[1..];
    var required_count: usize = 0;
    for (command.args) |arg| {
        if (arg.required) required_count += 1;
    }

    if (args.len < required_count) {
        return ParseError.MissingRequiredArg;
    }

    return .{
        .command = command,
        .args = args,
        .raw_input = trimmed,
    };
}

pub fn isCommand(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\n");
    return trimmed.len > 0 and trimmed[0] == '/';
}
```

### 3. Create Command Executor (src/commands/executor.zig)

```zig
const std = @import("std");
const parser = @import("parser.zig");
const registry = @import("registry.zig");

const AppState = @import("../state/app_state.zig").AppState;
const PlueClient = @import("../client/client.zig").PlueClient;

pub const CommandExecutor = struct {
    allocator: std.mem.Allocator,
    state: *AppState,
    client: *PlueClient,

    // Callbacks for UI actions
    on_mode_change: ?*const fn (AppState.UiMode) void = null,
    on_quit: ?*const fn () void = null,
    on_clear: ?*const fn () void = null,
    on_message: ?*const fn ([]const u8) void = null,

    pub fn init(allocator: std.mem.Allocator, state: *AppState, client: *PlueClient) CommandExecutor {
        return .{
            .allocator = allocator,
            .state = state,
            .client = client,
        };
    }

    pub fn execute(self: *CommandExecutor, input: []const u8) !ExecuteResult {
        const parsed = parser.parse(self.allocator, input) catch |err| {
            return switch (err) {
                parser.ParseError.NotACommand => .{ .error_message = "Not a command" },
                parser.ParseError.UnknownCommand => .{ .error_message = "Unknown command. Type /help for available commands." },
                parser.ParseError.MissingRequiredArg => .{ .error_message = "Missing required argument" },
                parser.ParseError.TooManyArgs => .{ .error_message = "Too many arguments" },
            };
        };

        const cmd = parsed.command;

        if (std.mem.eql(u8, cmd.name, "new")) {
            return self.executeNew();
        } else if (std.mem.eql(u8, cmd.name, "sessions")) {
            return self.executeSessions();
        } else if (std.mem.eql(u8, cmd.name, "switch")) {
            return self.executeSwitch(parsed.args);
        } else if (std.mem.eql(u8, cmd.name, "model")) {
            return self.executeModel(parsed.args);
        } else if (std.mem.eql(u8, cmd.name, "effort")) {
            return self.executeEffort(parsed.args);
        } else if (std.mem.eql(u8, cmd.name, "status")) {
            return self.executeStatus();
        } else if (std.mem.eql(u8, cmd.name, "undo")) {
            return self.executeUndo(parsed.args);
        } else if (std.mem.eql(u8, cmd.name, "mention")) {
            return self.executeMention(parsed.args);
        } else if (std.mem.eql(u8, cmd.name, "diff")) {
            return self.executeDiff();
        } else if (std.mem.eql(u8, cmd.name, "abort")) {
            return self.executeAbort();
        } else if (std.mem.eql(u8, cmd.name, "clear")) {
            return self.executeClear();
        } else if (std.mem.eql(u8, cmd.name, "help")) {
            return self.executeHelp(parsed.args);
        } else if (std.mem.eql(u8, cmd.name, "quit")) {
            return self.executeQuit();
        }

        return .{ .error_message = "Command not implemented" };
    }

    fn executeNew(self: *CommandExecutor) !ExecuteResult {
        // Create new session via API
        const cwd = self.state.working_directory;
        const model = "claude-sonnet-4-20250514"; // Default

        const session = self.client.createSession(cwd, model) catch |err| {
            return .{ .error_message = @errorName(err) };
        };

        try self.state.session_manager.addSession(.{
            .id = session.id,
            .title = null,
            .model = model,
            .reasoning_effort = .medium,
            .directory = cwd,
            .created_at = std.time.timestamp(),
            .updated_at = std.time.timestamp(),
        });

        try self.state.session_manager.switchToSession(session.id);

        return .{ .success_message = "New session created" };
    }

    fn executeSessions(self: *CommandExecutor) ExecuteResult {
        if (self.on_mode_change) |cb| {
            cb(.session_select);
        }
        return .{ .mode_changed = .session_select };
    }

    fn executeSwitch(self: *CommandExecutor, args: []const []const u8) ExecuteResult {
        if (args.len == 0) {
            return .{ .error_message = "Usage: /switch <session-id>" };
        }

        const id = args[0];
        self.state.session_manager.switchToSession(id) catch {
            return .{ .error_message = "Session not found" };
        };

        return .{ .success_message = "Switched to session" };
    }

    fn executeModel(self: *CommandExecutor, args: []const []const u8) ExecuteResult {
        if (args.len == 0) {
            // Show model picker
            if (self.on_mode_change) |cb| {
                cb(.model_select);
            }
            return .{ .mode_changed = .model_select };
        }

        // Set model directly
        const model_name = args[0];

        // Validate model
        var valid = false;
        for (self.state.available_models) |m| {
            if (std.mem.indexOf(u8, m, model_name) != null) {
                if (self.state.currentSession()) |session| {
                    self.client.updateSession(session.id, m, null) catch {};
                    self.state.session_manager.updateSessionModel(session.id, m) catch {};
                }
                valid = true;
                break;
            }
        }

        if (!valid) {
            return .{ .error_message = "Unknown model. Use /model to see available options." };
        }

        return .{ .success_message = "Model updated" };
    }

    fn executeEffort(self: *CommandExecutor, args: []const []const u8) ExecuteResult {
        if (args.len == 0) {
            // Show effort picker - would need mode for this
            return .{ .success_message = "Current effort: medium" };
        }

        const Session = @import("../state/session_manager.zig").Session;
        const effort = Session.ReasoningEffort.fromString(args[0]) orelse {
            return .{ .error_message = "Invalid effort. Use: minimal, low, medium, high" };
        };

        if (self.state.currentSession()) |session| {
            self.client.updateSession(session.id, null, effort.toString()) catch {};
        }

        return .{ .success_message = "Reasoning effort updated" };
    }

    fn executeStatus(self: *CommandExecutor) ExecuteResult {
        _ = self;
        // TODO: Build status message
        return .{ .success_message = "Status: Connected" };
    }

    fn executeUndo(self: *CommandExecutor, args: []const []const u8) !ExecuteResult {
        const turns: u32 = if (args.len > 0)
            std.fmt.parseInt(u32, args[0], 10) catch 1
        else
            1;

        if (self.state.currentSession()) |session| {
            self.client.undo(session.id, turns) catch |err| {
                return .{ .error_message = @errorName(err) };
            };

            // Also remove messages from local state
            const conv = self.state.currentConversation();
            if (conv) |c| {
                var to_remove = turns * 2; // User + assistant
                while (to_remove > 0 and c.messages.items.len > 0) {
                    _ = c.messages.pop();
                    to_remove -= 1;
                }
            }
        }

        return .{ .success_message = "Undid last turn(s)" };
    }

    fn executeMention(self: *CommandExecutor, args: []const []const u8) ExecuteResult {
        if (args.len == 0) {
            return .{ .error_message = "Usage: /mention <file-path>" };
        }

        const path = args[0];

        // Read file
        const file = std.fs.cwd().openFile(path, .{}) catch {
            return .{ .error_message = "Could not open file" };
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch {
            return .{ .error_message = "Could not read file" };
        };

        // Inject into input
        const mention_text = std.fmt.allocPrint(
            self.allocator,
            "@{s}\n```\n{s}\n```\n",
            .{ path, content },
        ) catch {
            return .{ .error_message = "Could not format mention" };
        };

        self.state.input_buffer.appendSlice(mention_text) catch {};

        return .{ .success_message = "File added to message" };
    }

    fn executeDiff(self: *CommandExecutor) ExecuteResult {
        _ = self;
        // TODO: Show diff view
        return .{ .success_message = "Diff view not yet implemented" };
    }

    fn executeAbort(self: *CommandExecutor) !ExecuteResult {
        if (self.state.currentSession()) |session| {
            self.client.abort(session.id) catch |err| {
                return .{ .error_message = @errorName(err) };
            };

            if (self.state.currentConversation()) |conv| {
                conv.abortStreaming();
            }
        }

        return .{ .success_message = "Aborted" };
    }

    fn executeClear(self: *CommandExecutor) ExecuteResult {
        if (self.on_clear) |cb| cb();
        return .{ .cleared = true };
    }

    fn executeHelp(self: *CommandExecutor, args: []const []const u8) ExecuteResult {
        _ = self;

        if (args.len > 0) {
            const cmd = registry.findCommand(args[0]);
            if (cmd) |c| {
                return .{ .help_text = formatCommandHelp(c) };
            }
            return .{ .error_message = "Unknown command" };
        }

        return .{ .help_text = formatAllHelp() };
    }

    fn executeQuit(self: *CommandExecutor) ExecuteResult {
        if (self.on_quit) |cb| cb();
        return .{ .quit = true };
    }

    fn formatCommandHelp(cmd: *const registry.Command) []const u8 {
        _ = cmd;
        return "Command help"; // TODO: Format properly
    }

    fn formatAllHelp() []const u8 {
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
            \\  /help        Show this help
            \\  /quit        Exit
        ;
    }
};

pub const ExecuteResult = struct {
    success_message: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    help_text: ?[]const u8 = null,
    mode_changed: ?AppState.UiMode = null,
    cleared: bool = false,
    quit: bool = false,
};
```

### 4. Create Help View (src/widgets/help_view.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const registry = @import("../commands/registry.zig");

pub const HelpView = struct {
    scroll_offset: usize = 0,

    pub fn widget(self: *HelpView) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = HelpView.handleEvent,
            .drawFn = HelpView.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *HelpView = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.page_up, .{})) {
                    if (self.scroll_offset > 10) self.scroll_offset -= 10 else self.scroll_offset = 0;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.page_down, .{})) {
                    self.scroll_offset += 10;
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *HelpView = @ptrCast(@alignCast(ptr));
        _ = self;
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, undefined, size);

        // Title
        const title = "Help - Available Commands";
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(i + 2), 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Separator
        for (0..size.width) |col| {
            surface.writeCell(@intCast(col), 1, .{
                .char = .{ .grapheme = "─", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Commands
        var row: u16 = 3;
        for (registry.COMMANDS) |cmd| {
            if (row >= size.height - 2) break;

            // Command name
            var col: u16 = 2;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = "/", .width = 1 },
                .style = .{ .fg = .{ .index = 14 } },
            });
            col += 1;

            for (cmd.name) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 14 }, .bold = true },
                });
                col += 1;
            }

            // Args
            for (cmd.args) |arg| {
                col += 1;
                const bracket = if (arg.required) "<" else "[";
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = bracket, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
                col += 1;

                for (arg.name) |char| {
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = .{ .fg = .{ .index = 11 } },
                    });
                    col += 1;
                }

                const close_bracket = if (arg.required) ">" else "]";
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = close_bracket, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
                col += 1;
            }

            // Description
            col = 25;
            for (cmd.description) |char| {
                if (col >= size.width - 2) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 7 } },
                });
                col += 1;
            }

            row += 1;
        }

        // Footer hint
        const hint = "Press ESC to close";
        for (hint, 0..) |char, i| {
            surface.writeCell(@intCast(i + 2), size.height - 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        return surface;
    }
};
```

## Acceptance Criteria

- [ ] Commands parse correctly with /prefix
- [ ] Unknown commands show error
- [ ] Missing required args show error
- [ ] /new creates session
- [ ] /sessions shows session picker
- [ ] /switch changes session
- [ ] /model shows model picker or sets model
- [ ] /effort changes reasoning effort
- [ ] /undo removes turns
- [ ] /mention reads and injects file
- [ ] /abort stops streaming
- [ ] /help shows command list
- [ ] /quit exits application
- [ ] Tab completion for command names

## Files to Create

1. `tui-zig/src/commands/registry.zig`
2. `tui-zig/src/commands/parser.zig`
3. `tui-zig/src/commands/executor.zig`
4. `tui-zig/src/widgets/help_view.zig`

## Next

Proceed to `16_file_mentions.md` for file handling.
