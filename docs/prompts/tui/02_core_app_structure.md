# 02: Core Application Structure

## Goal

Implement the main App widget using vxfw, with proper state management and event handling.

## Context

- libvaxis vxfw provides the high-level framework
- The app needs to manage: connection state, current session, conversation, UI mode
- Reference: `/Users/williamcory/plue/libvaxis/src/vxfw/App.zig`

## Architecture

```
App (root widget)
├── State
│   ├── connection: ConnectionState
│   ├── session: ?Session
│   ├── messages: ArrayList(Message)
│   ├── input_buffer: ArrayList(u8)
│   └── ui_mode: UiMode
├── Children
│   ├── Header (session info)
│   ├── ChatHistory (scrollable)
│   ├── StatusBar (tokens, status)
│   └── Composer (input)
└── Overlays (modal dialogs)
```

## Tasks

### 1. Define Core Types (src/types.zig)

```zig
const std = @import("std");

pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    error,
};

pub const UiMode = enum {
    chat,           // Normal chat mode
    model_select,   // Selecting model
    session_select, // Selecting session
    file_search,    // File picker
    approval,       // Approval overlay
    help,           // Help screen
};

pub const Message = struct {
    role: Role,
    content: []const u8,
    timestamp: i64,
    tool_calls: ?[]ToolCall = null,

    pub const Role = enum { user, assistant, system };
};

pub const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    args: []const u8,
    result: ?[]const u8 = null,
    status: Status = .pending,
    duration_ms: ?u64 = null,

    pub const Status = enum { pending, running, completed, failed };
};

pub const Session = struct {
    id: []const u8,
    title: ?[]const u8,
    model: []const u8,
    reasoning_effort: ReasoningEffort,
    directory: []const u8,
    created_at: i64,

    pub const ReasoningEffort = enum { minimal, low, medium, high };
};

pub const TokenUsage = struct {
    input: u64 = 0,
    output: u64 = 0,
    cached: u64 = 0,
};
```

### 2. Create App State (src/state/app_state.zig)

```zig
const std = @import("std");
const types = @import("../types.zig");

pub const AppState = struct {
    allocator: std.mem.Allocator,

    // Connection
    api_url: []const u8,
    connection: types.ConnectionState = .disconnected,

    // Session
    session: ?types.Session = null,
    sessions: std.ArrayList(types.Session),

    // Conversation
    messages: std.ArrayList(types.Message),
    pending_tool_calls: std.StringHashMap(types.ToolCall),

    // Input
    input_buffer: std.ArrayList(u8),
    input_history: std.ArrayList([]const u8),
    history_index: ?usize = null,

    // UI
    mode: types.UiMode = .chat,
    scroll_offset: usize = 0,

    // Status
    is_streaming: bool = false,
    streaming_text: std.ArrayList(u8),
    token_usage: types.TokenUsage = .{},
    error_message: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, api_url: []const u8) AppState {
        return .{
            .allocator = allocator,
            .api_url = api_url,
            .sessions = std.ArrayList(types.Session).init(allocator),
            .messages = std.ArrayList(types.Message).init(allocator),
            .pending_tool_calls = std.StringHashMap(types.ToolCall).init(allocator),
            .input_buffer = std.ArrayList(u8).init(allocator),
            .input_history = std.ArrayList([]const u8).init(allocator),
            .streaming_text = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *AppState) void {
        self.sessions.deinit();
        self.messages.deinit();
        self.pending_tool_calls.deinit();
        self.input_buffer.deinit();
        self.input_history.deinit();
        self.streaming_text.deinit();
    }

    pub fn addMessage(self: *AppState, role: types.Message.Role, content: []const u8) !void {
        const content_copy = try self.allocator.dupe(u8, content);
        try self.messages.append(.{
            .role = role,
            .content = content_copy,
            .timestamp = std.time.timestamp(),
        });
    }

    pub fn clearInput(self: *AppState) void {
        self.input_buffer.clearRetainingCapacity();
    }

    pub fn getInput(self: *AppState) []const u8 {
        return self.input_buffer.items;
    }
};
```

### 3. Create Main App Widget (src/app.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const AppState = @import("state/app_state.zig").AppState;
const types = @import("types.zig");

pub const App = struct {
    state: *AppState,

    // Child widgets (to be implemented)
    // header: Header,
    // chat_history: ChatHistory,
    // composer: Composer,
    // status_bar: StatusBar,

    pub fn init(state: *AppState) App {
        return .{
            .state = state,
        };
    }

    pub fn widget(self: *App) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = App.handleEvent,
            .drawFn = App.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *App = @ptrCast(@alignCast(ptr));

        switch (event) {
            .init => {
                // Initial setup - connect to server, load sessions
                self.state.connection = .connecting;
                // TODO: Spawn connection task
            },
            .key_press => |key| {
                try self.handleKeyPress(ctx, key);
            },
            .tick => {
                // Handle streaming updates
                if (self.state.is_streaming) {
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn handleKeyPress(self: *App, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        // Global shortcuts
        if (key.matches('c', .{ .ctrl = true })) {
            if (self.state.is_streaming) {
                // Abort current operation
                self.state.is_streaming = false;
            } else {
                ctx.quit = true;
            }
            ctx.consumeAndRedraw();
            return;
        }

        // Mode-specific handling
        switch (self.state.mode) {
            .chat => try self.handleChatMode(ctx, key),
            .model_select => try self.handleSelectMode(ctx, key),
            .session_select => try self.handleSelectMode(ctx, key),
            .approval => try self.handleApprovalMode(ctx, key),
            .help => {
                if (key.matches(vaxis.Key.escape, .{})) {
                    self.state.mode = .chat;
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn handleChatMode(self: *App, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        if (key.matches(vaxis.Key.enter, .{})) {
            // Submit message
            const input = self.state.getInput();
            if (input.len > 0) {
                if (input[0] == '/') {
                    try self.handleSlashCommand(input);
                } else {
                    try self.submitMessage(input);
                }
                self.state.clearInput();
            }
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.up, .{})) {
            // History navigation
            if (self.state.input_history.items.len > 0) {
                const idx = self.state.history_index orelse self.state.input_history.items.len;
                if (idx > 0) {
                    self.state.history_index = idx - 1;
                    // Load history item into input
                    self.state.input_buffer.clearRetainingCapacity();
                    try self.state.input_buffer.appendSlice(
                        self.state.input_history.items[idx - 1]
                    );
                }
            }
            ctx.consumeAndRedraw();
        } else if (key.text) |text| {
            // Regular text input
            try self.state.input_buffer.appendSlice(text);
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.backspace, .{})) {
            // Delete character
            if (self.state.input_buffer.items.len > 0) {
                _ = self.state.input_buffer.pop();
            }
            ctx.consumeAndRedraw();
        }
    }

    fn handleSelectMode(self: *App, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        if (key.matches(vaxis.Key.escape, .{})) {
            self.state.mode = .chat;
            ctx.consumeAndRedraw();
        }
        // TODO: Arrow key navigation, enter to select
    }

    fn handleApprovalMode(self: *App, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        if (key.matches('y', .{})) {
            // Approve
            self.state.mode = .chat;
            // TODO: Send approval
            ctx.consumeAndRedraw();
        } else if (key.matches('n', .{}) or key.matches(vaxis.Key.escape, .{})) {
            // Decline
            self.state.mode = .chat;
            ctx.consumeAndRedraw();
        }
    }

    fn handleSlashCommand(self: *App, input: []const u8) !void {
        const cmd = input[1..]; // Skip '/'

        if (std.mem.startsWith(u8, cmd, "model")) {
            self.state.mode = .model_select;
        } else if (std.mem.startsWith(u8, cmd, "sessions")) {
            self.state.mode = .session_select;
        } else if (std.mem.startsWith(u8, cmd, "help")) {
            self.state.mode = .help;
        } else if (std.mem.startsWith(u8, cmd, "new")) {
            // Create new session
            // TODO: API call
        } else if (std.mem.startsWith(u8, cmd, "quit") or std.mem.startsWith(u8, cmd, "q")) {
            // Will be handled by exit
        }
        // TODO: More commands
    }

    fn submitMessage(self: *App, content: []const u8) !void {
        // Add to history
        const content_copy = try self.state.allocator.dupe(u8, content);
        try self.state.input_history.append(content_copy);
        self.state.history_index = null;

        // Add user message to display
        try self.state.addMessage(.user, content);

        // Start streaming
        self.state.is_streaming = true;
        self.state.streaming_text.clearRetainingCapacity();

        // TODO: Send to API via SSE client
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *App = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Layout: Header (1 line) | Chat | Status (1 line) | Composer (3 lines)
        const header_height: u16 = 1;
        const status_height: u16 = 1;
        const composer_height: u16 = 3;
        const chat_height = size.height -| header_height -| status_height -| composer_height;

        // Draw placeholder sections
        try self.drawHeader(&surface, 0, size.width, ctx);
        try self.drawChat(&surface, header_height, size.width, chat_height, ctx);
        try self.drawStatus(&surface, header_height + chat_height, size.width, ctx);
        try self.drawComposer(&surface, header_height + chat_height + status_height, size.width, composer_height, ctx);

        // Draw overlay if needed
        if (self.state.mode != .chat) {
            try self.drawOverlay(&surface, size, ctx);
        }

        return surface;
    }

    fn drawHeader(self: *App, surface: *vxfw.Surface, row: u16, width: u16, _: vxfw.DrawContext) !void {
        const session_text = if (self.state.session) |s|
            s.title orelse s.id
        else
            "No session";

        const style = vaxis.Cell.Style{ .fg = .{ .index = 14 }, .bold = true };

        for (session_text, 0..) |char, i| {
            if (i >= width) break;
            surface.writeCell(@intCast(i), row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
        }
    }

    fn drawChat(self: *App, surface: *vxfw.Surface, start_row: u16, width: u16, height: u16, _: vxfw.DrawContext) !void {
        var row = start_row;

        for (self.state.messages.items) |msg| {
            if (row >= start_row + height) break;

            const prefix: []const u8 = switch (msg.role) {
                .user => "> ",
                .assistant => "  ",
                .system => "* ",
            };

            const style = vaxis.Cell.Style{
                .fg = switch (msg.role) {
                    .user => .{ .index = 12 },      // Blue
                    .assistant => .{ .index = 10 }, // Green
                    .system => .{ .index = 14 },    // Cyan
                },
            };

            // Draw prefix
            for (prefix, 0..) |char, i| {
                surface.writeCell(@intCast(i), row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = style,
                });
            }

            // Draw content (simplified - real impl needs wrapping)
            const content = msg.content;
            var col: u16 = @intCast(prefix.len);
            for (content) |char| {
                if (col >= width) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = style,
                });
                col += 1;
            }

            row += 1;
        }

        // Show streaming text
        if (self.state.is_streaming and self.state.streaming_text.items.len > 0) {
            if (row < start_row + height) {
                const text = self.state.streaming_text.items;
                for (text, 0..) |char, i| {
                    if (i >= width) break;
                    surface.writeCell(@intCast(i), row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = .{ .fg = .{ .index = 10 } },
                    });
                }
            }
        }
    }

    fn drawStatus(self: *App, surface: *vxfw.Surface, row: u16, width: u16, _: vxfw.DrawContext) !void {
        const status = if (self.state.is_streaming)
            "Streaming..."
        else if (self.state.connection == .connected)
            "Ready"
        else
            "Disconnected";

        const style = vaxis.Cell.Style{ .fg = .{ .index = 8 }, .dim = true };

        for (status, 0..) |char, i| {
            if (i >= width) break;
            surface.writeCell(@intCast(i), row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
        }
    }

    fn drawComposer(self: *App, surface: *vxfw.Surface, start_row: u16, width: u16, _: u16, _: vxfw.DrawContext) !void {
        const prompt = "> ";
        const style = vaxis.Cell.Style{ .fg = .{ .index = 7 } };

        // Draw prompt
        for (prompt, 0..) |char, i| {
            surface.writeCell(@intCast(i), start_row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 12 } },
            });
        }

        // Draw input
        const input = self.state.input_buffer.items;
        var col: u16 = @intCast(prompt.len);
        for (input) |char| {
            if (col >= width) break;
            surface.writeCell(col, start_row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
            col += 1;
        }

        // Draw cursor
        surface.writeCell(col, start_row, .{
            .char = .{ .grapheme = "_", .width = 1 },
            .style = .{ .reverse = true },
        });
    }

    fn drawOverlay(self: *App, surface: *vxfw.Surface, size: vxfw.Size, _: vxfw.DrawContext) !void {
        // Simple overlay - full implementation later
        const title = switch (self.state.mode) {
            .model_select => "Select Model",
            .session_select => "Select Session",
            .help => "Help - Press ESC to close",
            .approval => "Approve Action? (y/n)",
            else => return,
        };

        // Draw centered box
        const box_width: u16 = 40;
        const box_height: u16 = 10;
        const start_col = (size.width -| box_width) / 2;
        const start_row = (size.height -| box_height) / 2;

        // Fill background
        const bg_style = vaxis.Cell.Style{ .bg = .{ .index = 0 }, .fg = .{ .index = 15 } };
        var row = start_row;
        while (row < start_row + box_height) : (row += 1) {
            var col = start_col;
            while (col < start_col + box_width) : (col += 1) {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = bg_style,
                });
            }
        }

        // Draw title
        const title_col = start_col + (box_width -| @as(u16, @intCast(title.len))) / 2;
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(title_col + i), start_row + 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true, .bg = .{ .index = 0 } },
            });
        }
    }
};
```

### 4. Update main.zig

```zig
const std = @import("std");
const vaxis = @import("vaxis");

const App = @import("app.zig").App;
const AppState = @import("state/app_state.zig").AppState;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Parse CLI arguments
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var api_url: []const u8 = "http://localhost:4000";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--api-url") and i + 1 < args.len) {
            api_url = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            try printHelp();
            return;
        } else if (std.mem.eql(u8, args[i], "--version") or std.mem.eql(u8, args[i], "-v")) {
            try std.io.getStdOut().writer().writeAll("plue-tui 0.1.0\n");
            return;
        }
    }

    // Initialize state
    var state = AppState.init(alloc, api_url);
    defer state.deinit();

    // Initialize vxfw app
    var vx_app = try vaxis.vxfw.App.init(alloc);
    defer vx_app.deinit();

    // Create main app widget
    var app = App.init(&state);

    // Run the TUI
    try vx_app.run(app.widget(), .{});
}

fn printHelp() !void {
    const help =
        \\Usage: plue-tui [OPTIONS]
        \\
        \\Options:
        \\  --api-url <URL>  API server URL (default: http://localhost:4000)
        \\  --help, -h       Show this help message
        \\  --version, -v    Show version
        \\
        \\Slash Commands:
        \\  /new             Create new session
        \\  /sessions        List sessions
        \\  /switch <id>     Switch to session
        \\  /model [name]    List or set model
        \\  /effort [level]  Set reasoning effort
        \\  /help            Show help
        \\  /quit            Exit
        \\
    ;
    try std.io.getStdOut().writer().writeAll(help);
}
```

## Acceptance Criteria

- [ ] App widget properly initializes with vxfw
- [ ] Event handling works for keyboard input
- [ ] Basic layout renders (header, chat, status, composer)
- [ ] Text input works in composer area
- [ ] Mode switching works (chat, overlays)
- [ ] Ctrl+C exits the application
- [ ] State management tracks messages and input

## Files to Create

1. `tui-zig/src/types.zig`
2. `tui-zig/src/state/app_state.zig`
3. `tui-zig/src/app.zig`
4. Update `tui-zig/src/main.zig`

## Next

Proceed to `03_sse_client.md` to implement the SSE client for streaming responses.
