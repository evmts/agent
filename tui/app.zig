const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const types = @import("types.zig");
const AppState = @import("state/app_state.zig").AppState;
const PlueClient = @import("client/client.zig").PlueClient;
const EventQueue = @import("client/sse.zig").EventQueue;
const StreamEvent = @import("client/protocol.zig").StreamEvent;

// Phase 5-6 integrations
const parser = @import("commands/parser.zig");
const registry = @import("commands/registry.zig");
const approval_mod = @import("state/approval.zig");
const ApprovalManager = approval_mod.ApprovalManager;
const HelpView = @import("widgets/help_view.zig").HelpView;
const CommandApproval = @import("widgets/command_approval.zig").CommandApproval;
const mentions = @import("utils/mentions.zig");

/// Main App widget orchestrating the TUI
pub const App = struct {
    state: *AppState,
    client: *PlueClient,
    event_queue: *EventQueue,
    approval_manager: ApprovalManager,
    help_view: HelpView,
    scroll_offset: usize = 0,

    /// Initialize the app
    pub fn init(allocator: std.mem.Allocator, state: *AppState, client: *PlueClient, event_queue: *EventQueue) App {
        return .{
            .state = state,
            .client = client,
            .event_queue = event_queue,
            .approval_manager = ApprovalManager.init(allocator),
            .help_view = HelpView{},
        };
    }

    pub fn deinit(self: *App) void {
        self.approval_manager.deinit();
    }

    /// Return a vxfw.Widget for this app
    pub fn widget(self: *App) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = typeErasedEventHandler,
            .drawFn = typeErasedDrawFn,
        };
    }

    /// Event handler called by vxfw runtime
    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *App = @ptrCast(@alignCast(ptr));

        switch (event) {
            .init => {
                // Initial setup - connect to server
                try self.handleInit(ctx);
            },
            .key_press => |key| {
                try self.handleKeyPress(ctx, key);
            },
            .tick => {
                try self.handleTick(ctx);
            },
            else => {},
        }
    }

    /// Draw function called by vxfw runtime
    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *App = @ptrCast(@alignCast(ptr));
        const max_size = ctx.max.size();

        // Create surface for the entire screen
        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), max_size);

        // Layout: Header (1 line) | Chat | Status (1 line) | Composer (3 lines)
        const header_height: u16 = 1;
        const status_height: u16 = 1;
        const composer_height: u16 = 3;
        const chat_height = max_size.height -| header_height -| status_height -| composer_height;

        // Draw placeholder sections
        try self.drawHeader(&surface, 0, max_size.width, ctx);
        try self.drawChat(&surface, header_height, max_size.width, chat_height, ctx);
        try self.drawStatus(&surface, header_height + chat_height, max_size.width, ctx);
        try self.drawComposer(&surface, header_height + chat_height + status_height, max_size.width, composer_height, ctx);

        // Draw overlay if needed
        if (self.state.mode != .chat) {
            try self.drawOverlay(&surface, max_size, ctx);
        }

        return surface;
    }

    // Event handling

    fn handleInit(self: *App, ctx: *vxfw.EventContext) !void {
        // Start connecting to server
        self.state.connection = .connecting;

        // Spawn task to check health and load sessions
        const thread = try std.Thread.spawn(.{}, connectThread, .{ self.state, self.client });
        thread.detach();

        ctx.consumeAndRedraw();
    }

    fn connectThread(state: *AppState, client: *PlueClient) void {
        // Try to connect
        const healthy = client.healthCheck() catch {
            state.connection = .err;
            _ = state.setError("Failed to connect to API server") catch {};
            return;
        };

        if (!healthy) {
            state.connection = .err;
            _ = state.setError("API server is unhealthy") catch {};
            return;
        }

        // Load sessions
        const sessions = client.listSessions() catch |err| {
            state.connection = .err;
            const err_msg = std.fmt.allocPrint(state.allocator, "Failed to load sessions: {s}", .{@errorName(err)}) catch "Failed to load sessions";
            _ = state.setError(err_msg) catch {};
            return;
        };

        // Add sessions to state
        for (sessions) |sess| {
            const converted = convertSession(state.allocator, sess) catch continue;
            state.addSession(converted) catch {};
        }

        state.connection = .connected;
        state.clearError();
    }

    fn convertSession(allocator: std.mem.Allocator, proto_sess: @import("client/protocol.zig").Session) !@import("state/session.zig").Session {
        const reasoning = @import("state/session.zig").ReasoningEffort.fromString(proto_sess.reasoning_effort) orelse .medium;
        return .{
            .id = try allocator.dupe(u8, proto_sess.id),
            .title = if (proto_sess.title) |t| try allocator.dupe(u8, t) else null,
            .model = try allocator.dupe(u8, proto_sess.model),
            .reasoning_effort = reasoning,
            .directory = try allocator.dupe(u8, proto_sess.directory),
            .created_at = proto_sess.created_at,
            .updated_at = proto_sess.created_at,
        };
    }

    fn handleKeyPress(self: *App, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        // Global shortcuts
        if (key.matches('c', .{ .ctrl = true })) {
            if (self.state.isStreaming()) {
                // Abort current operation
                try self.abortStreaming(ctx);
            } else {
                ctx.quit = true;
            }
            ctx.consumeAndRedraw();
            return;
        }

        if (key.matches('l', .{ .ctrl = true })) {
            // Clear screen - just redraw
            ctx.consumeAndRedraw();
            return;
        }

        // Mode-specific handling
        switch (self.state.mode) {
            .chat => try self.handleChatMode(ctx, key),
            .model_select, .session_select, .file_search => try self.handleSelectMode(ctx, key),
            .approval => try self.handleApprovalMode(ctx, key),
            .help => try self.handleHelpMode(ctx, key),
        }
    }

    fn handleTick(self: *App, ctx: *vxfw.EventContext) !void {
        // Process SSE events from queue
        while (self.event_queue.pop()) |event| {
            try self.processStreamEvent(event);
            ctx.consumeAndRedraw();
        }

        // If streaming, request redraw
        if (self.state.isStreaming()) {
            ctx.consumeAndRedraw();
        }
    }

    fn processStreamEvent(self: *App, event: StreamEvent) !void {
        const conv = self.state.currentConversation() orelse return;

        switch (event) {
            .text => |text_event| {
                if (text_event.data) |data| {
                    try conv.appendStreamingText(data);
                }
            },
            .tool_call => |tc_event| {
                if (tc_event.tool_name != null and tc_event.tool_id != null) {
                    const tool_call = @import("state/message.zig").ToolCall{
                        .id = try self.state.allocator.dupe(u8, tc_event.tool_id.?),
                        .name = try self.state.allocator.dupe(u8, tc_event.tool_name.?),
                        .args = if (tc_event.args) |a| try self.state.allocator.dupe(u8, a) else try self.state.allocator.dupe(u8, "{}"),
                        .status = .running,
                        .started_at = std.time.timestamp(),
                        .result = null,
                    };
                    try conv.addStreamingToolCall(tool_call);
                }
            },
            .tool_result => |tr_event| {
                // Tool result - update the tool call status
                _ = tr_event;
                // TODO: Update tool call in conversation
            },
            .error_event => |err_event| {
                if (err_event.error_msg) |msg| {
                    try self.state.setError(msg);
                }
                conv.abortStreaming();
            },
            .done => {
                _ = try conv.finishStreaming();
            },
        }
    }

    fn abortStreaming(self: *App, ctx: *vxfw.EventContext) !void {
        if (self.state.currentSession()) |sess| {
            try self.client.abort(sess.id);
        }
        if (self.state.currentConversation()) |conv| {
            conv.abortStreaming();
        }
        ctx.consumeAndRedraw();
    }

    // Mode-specific handlers

    fn handleChatMode(self: *App, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        if (key.matches(vaxis.Key.enter, .{})) {
            // Submit message
            const input = self.state.getInput();
            if (input.len > 0) {
                if (input[0] == '/') {
                    try self.handleSlashCommand(ctx, input);
                } else {
                    try self.submitMessage(ctx, input);
                }
                self.state.clearInput();
            }
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.up, .{})) {
            // History navigation
            self.state.navigateHistory(-1);
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.down, .{})) {
            // History navigation
            self.state.navigateHistory(1);
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.left, .{})) {
            // Move cursor left
            self.state.moveCursor(-1);
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.right, .{})) {
            // Move cursor right
            self.state.moveCursor(1);
            ctx.consumeAndRedraw();
        } else if (key.text) |text| {
            // Regular text input
            try self.state.insertText(text);
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.backspace, .{})) {
            // Delete character
            self.state.deleteBackward();
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.delete, .{})) {
            // Delete forward
            self.state.deleteForward();
            ctx.consumeAndRedraw();
        }
    }

    fn handleSelectMode(self: *App, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        if (key.matches(vaxis.Key.escape, .{})) {
            self.state.mode = .chat;
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.up, .{})) {
            if (self.state.selected_index > 0) {
                self.state.selected_index -= 1;
            }
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.down, .{})) {
            self.state.selected_index += 1;
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.enter, .{})) {
            // Select item based on mode
            switch (self.state.mode) {
                .model_select => try self.selectModel(ctx),
                .session_select => try self.selectSession(ctx),
                else => {},
            }
            self.state.mode = .chat;
            ctx.consumeAndRedraw();
        }
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

    fn handleHelpMode(self: *App, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        if (key.matches(vaxis.Key.escape, .{}) or key.codepoint == 'q') {
            self.state.mode = .chat;
        } else if (key.codepoint == 'j' or key.matches(vaxis.Key.down, .{})) {
            self.help_view.scroll_offset += 1;
        } else if (key.codepoint == 'k' or key.matches(vaxis.Key.up, .{})) {
            if (self.help_view.scroll_offset > 0) {
                self.help_view.scroll_offset -= 1;
            }
        }
        ctx.consumeAndRedraw();
    }

    fn handleSlashCommand(self: *App, ctx: *vxfw.EventContext, input: []const u8) !void {
        // Use the command parser
        const parsed = parser.parse(self.state.allocator, input) catch |err| {
            switch (err) {
                parser.ParseError.NotACommand => {},
                parser.ParseError.UnknownCommand => {
                    try self.state.setError("Unknown command. Type /help for available commands.");
                },
                parser.ParseError.MissingRequiredArg => {
                    try self.state.setError("Missing required argument for command.");
                },
                else => {},
            }
            ctx.consumeAndRedraw();
            return;
        };

        // Execute the command based on name
        if (std.mem.eql(u8, parsed.command.name, "model")) {
            self.state.mode = .model_select;
            self.state.selected_index = 0;
        } else if (std.mem.eql(u8, parsed.command.name, "sessions")) {
            self.state.mode = .session_select;
            self.state.selected_index = 0;
        } else if (std.mem.eql(u8, parsed.command.name, "help")) {
            self.state.mode = .help;
            self.help_view.scroll_offset = 0;
        } else if (std.mem.eql(u8, parsed.command.name, "new")) {
            try self.createNewSession(ctx);
        } else if (std.mem.eql(u8, parsed.command.name, "quit")) {
            ctx.quit = true;
        } else if (std.mem.eql(u8, parsed.command.name, "clear")) {
            if (self.state.currentConversation()) |conv| {
                conv.clear();
            }
        } else if (std.mem.eql(u8, parsed.command.name, "effort")) {
            // Handle effort command - if arg provided, set it; otherwise show picker
            if (parsed.getArg(0)) |arg| {
                const level = @import("state/session.zig").ReasoningEffort.fromString(arg);
                if (level) |lvl| {
                    if (self.state.currentSession()) |sess| {
                        sess.reasoning_effort = lvl;
                        try self.client.updateSession(sess.id, null, arg);
                    }
                } else {
                    try self.state.setError("Invalid effort level. Use: minimal, low, medium, or high");
                }
            } else {
                // Show current effort level in status
                if (self.state.currentSession()) |sess| {
                    _ = sess; // Status bar shows current effort
                }
            }
        } else if (std.mem.eql(u8, parsed.command.name, "undo")) {
            const turns: u32 = if (parsed.getArg(0)) |arg|
                std.fmt.parseInt(u32, arg, 10) catch 1
            else
                1;
            if (self.state.currentSession()) |sess| {
                try self.client.undo(sess.id, turns);
                if (self.state.currentConversation()) |conv| {
                    // Remove turns from conversation
                    var i: u32 = 0;
                    while (i < turns and conv.messages.items.len > 0) : (i += 1) {
                        _ = conv.messages.pop();
                    }
                }
            }
        } else if (std.mem.eql(u8, parsed.command.name, "abort")) {
            try self.abortStreaming(ctx);
        } else if (std.mem.eql(u8, parsed.command.name, "switch")) {
            if (parsed.getArg(0)) |arg| {
                // Find session by partial ID match
                for (self.state.sessions.items) |*sess| {
                    if (std.mem.startsWith(u8, sess.id, arg)) {
                        try self.state.switchToSession(sess.id);
                        break;
                    }
                }
            } else {
                self.state.mode = .session_select;
                self.state.selected_index = 0;
            }
        } else if (std.mem.eql(u8, parsed.command.name, "status")) {
            // Status is always shown in header - just acknowledge
            self.state.clearError();
        } else if (std.mem.eql(u8, parsed.command.name, "diff")) {
            // Show diffs - TODO: implement diff view mode
            try self.state.setError("Diff view not yet implemented");
        }

        ctx.consumeAndRedraw();
    }

    fn submitMessage(self: *App, ctx: *vxfw.EventContext, content: []const u8) !void {
        // Save to history
        try self.state.saveToHistory();

        // Get or create session
        if (self.state.currentSession() == null) {
            try self.createNewSession(ctx);
        }

        const session = self.state.currentSession() orelse return;
        const conv = self.state.currentConversation() orelse return;

        // Expand @mentions in content before sending
        const expanded_content = if (mentions.hasMentions(content))
            mentions.expandMentions(self.state.allocator, content, self.state.working_directory) catch content
        else
            content;
        defer if (mentions.hasMentions(content)) {
            self.state.allocator.free(expanded_content);
        };

        // Add user message (show original, not expanded)
        _ = try conv.addUserMessage(content);

        // Start streaming
        conv.startStreaming();

        // Send expanded message to API
        try self.client.sendMessageAsync(session.id, expanded_content, null, self.event_queue);

        ctx.consumeAndRedraw();
    }

    fn createNewSession(self: *App, ctx: *vxfw.EventContext) !void {
        _ = ctx;
        const model = self.state.available_models[0];
        const proto_sess = try self.client.createSession(self.state.working_directory, model);
        const sess = try convertSession(self.state.allocator, proto_sess);
        try self.state.addSession(sess);
        try self.state.switchToSession(sess.id);
    }

    fn selectModel(self: *App, ctx: *vxfw.EventContext) !void {
        _ = ctx;
        if (self.state.selected_index < self.state.available_models.len) {
            const model = self.state.available_models[self.state.selected_index];
            if (self.state.currentSession()) |sess| {
                try self.client.updateSession(sess.id, model, null);
                self.state.allocator.free(sess.model);
                sess.model = try self.state.allocator.dupe(u8, model);
            }
        }
    }

    fn selectSession(self: *App, ctx: *vxfw.EventContext) !void {
        _ = ctx;
        if (self.state.selected_index < self.state.sessions.items.len) {
            const sess = &self.state.sessions.items[self.state.selected_index];
            try self.state.switchToSession(sess.id);
        }
    }

    // Drawing functions

    fn drawHeader(self: *App, surface: *vxfw.Surface, row: u16, width: u16, ctx: vxfw.DrawContext) !void {
        _ = ctx;
        const session_text = if (self.state.currentSession()) |s|
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

    fn drawChat(self: *App, surface: *vxfw.Surface, start_row: u16, width: u16, height: u16, ctx: vxfw.DrawContext) !void {
        _ = ctx;
        const conv = self.state.currentConversation();
        if (conv == null) return;

        var row = start_row;

        for (conv.?.messages.items) |msg| {
            if (row >= start_row + height) break;

            const prefix: []const u8 = switch (msg.role) {
                .user => "> ",
                .assistant => "  ",
                .system => "* ",
            };

            const style = vaxis.Cell.Style{
                .fg = switch (msg.role) {
                    .user => .{ .index = 12 }, // Blue
                    .assistant => .{ .index = 10 }, // Green
                    .system => .{ .index = 14 }, // Cyan
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
            const content = switch (msg.content) {
                .text => |t| t,
                .parts => "[parts]",
            };
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
        if (conv.?.is_streaming) {
            if (conv.?.getStreamingText()) |text| {
                if (row < start_row + height) {
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
    }

    fn drawStatus(self: *App, surface: *vxfw.Surface, row: u16, width: u16, ctx: vxfw.DrawContext) !void {
        _ = ctx;
        const status = if (self.state.isStreaming())
            "Streaming..."
        else if (self.state.connection == .connected)
            "Ready"
        else if (self.state.connection == .connecting)
            "Connecting..."
        else if (self.state.connection == .err)
            if (self.state.last_error) |e| e else "Error"
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

    fn drawComposer(self: *App, surface: *vxfw.Surface, start_row: u16, width: u16, height: u16, ctx: vxfw.DrawContext) !void {
        _ = height;
        _ = ctx;
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
        const cursor_col: u16 = @intCast(prompt.len + self.state.input_cursor);
        if (cursor_col < width) {
            surface.writeCell(cursor_col, start_row, .{
                .char = .{ .grapheme = "_", .width = 1 },
                .style = .{ .reverse = true },
            });
        }
    }

    fn drawOverlay(self: *App, surface: *vxfw.Surface, size: vxfw.Size, ctx: vxfw.DrawContext) !void {
        _ = ctx;

        // Special handling for help mode - full screen overlay
        if (self.state.mode == .help) {
            self.drawHelpOverlay(surface, size);
            return;
        }

        // Simple overlay for other modes
        const title = switch (self.state.mode) {
            .model_select => "Select Model (ESC to cancel)",
            .session_select => "Select Session (ESC to cancel)",
            .approval => "Approve Action? (y/n)",
            .file_search => "File Search",
            else => return,
        };

        // Draw centered box
        const box_width: u16 = 50;
        const box_height: u16 = 15;
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

        // Draw list items for selection modes
        if (self.state.mode == .model_select) {
            var item_row = start_row + 3;
            for (self.state.available_models, 0..) |model, i| {
                if (item_row >= start_row + box_height - 1) break;

                const is_selected = i == self.state.selected_index;
                const item_style = vaxis.Cell.Style{
                    .fg = .{ .index = if (is_selected) 11 else 15 },
                    .bg = .{ .index = 0 },
                    .reverse = is_selected,
                };

                const prefix = if (is_selected) "> " else "  ";
                var item_col = start_col + 2;

                for (prefix) |char| {
                    surface.writeCell(item_col, item_row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = item_style,
                    });
                    item_col += 1;
                }

                for (model) |char| {
                    if (item_col >= start_col + box_width - 2) break;
                    surface.writeCell(item_col, item_row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = item_style,
                    });
                    item_col += 1;
                }

                item_row += 1;
            }
        } else if (self.state.mode == .session_select) {
            var item_row = start_row + 3;
            for (self.state.sessions.items, 0..) |sess, i| {
                if (item_row >= start_row + box_height - 1) break;

                const is_selected = i == self.state.selected_index;
                const item_style = vaxis.Cell.Style{
                    .fg = .{ .index = if (is_selected) 11 else 15 },
                    .bg = .{ .index = 0 },
                    .reverse = is_selected,
                };

                const label = sess.title orelse sess.id;
                const prefix = if (is_selected) "> " else "  ";
                var item_col = start_col + 2;

                for (prefix) |char| {
                    surface.writeCell(item_col, item_row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = item_style,
                    });
                    item_col += 1;
                }

                for (label) |char| {
                    if (item_col >= start_col + box_width - 2) break;
                    surface.writeCell(item_col, item_row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = item_style,
                    });
                    item_col += 1;
                }

                item_row += 1;
            }
        }
    }

    fn drawHelpOverlay(self: *App, surface: *vxfw.Surface, size: vxfw.Size) void {
        // Clear background
        const bg_style = vaxis.Cell.Style{ .bg = .{ .index = 0 }, .fg = .{ .index = 15 } };
        for (0..size.height) |row_idx| {
            for (0..size.width) |col_idx| {
                surface.writeCell(@intCast(col_idx), @intCast(row_idx), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = bg_style,
                });
            }
        }

        // Title
        const title = "Help - Available Commands";
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(i + 2), 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true, .bg = .{ .index = 0 } },
            });
        }

        // Separator
        for (0..size.width) |col| {
            surface.writeCell(@intCast(col), 1, .{
                .char = .{ .grapheme = "─", .width = 1 },
                .style = .{ .fg = .{ .index = 8 }, .bg = .{ .index = 0 } },
            });
        }

        // Commands
        var row: u16 = 3;
        var cmd_idx: usize = 0;
        for (registry.COMMANDS) |cmd| {
            // Skip if scrolled past
            if (cmd_idx < self.help_view.scroll_offset) {
                cmd_idx += 1;
                continue;
            }

            if (row >= size.height -| 2) break;

            // Command name
            var col: u16 = 2;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = "/", .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bg = .{ .index = 0 } },
            });
            col += 1;

            for (cmd.name) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 14 }, .bold = true, .bg = .{ .index = 0 } },
                });
                col += 1;
            }

            // Args
            for (cmd.args) |arg| {
                col += 1;
                const bracket: []const u8 = if (arg.required) "<" else "[";
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = bracket, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 }, .bg = .{ .index = 0 } },
                });
                col += 1;

                for (arg.name) |char| {
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = .{ .fg = .{ .index = 11 }, .bg = .{ .index = 0 } },
                    });
                    col += 1;
                }

                const close_bracket: []const u8 = if (arg.required) ">" else "]";
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = close_bracket, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 }, .bg = .{ .index = 0 } },
                });
                col += 1;
            }

            // Description (aligned)
            col = 25;
            for (cmd.description) |char| {
                if (col >= size.width -| 2) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 7 }, .bg = .{ .index = 0 } },
                });
                col += 1;
            }

            row += 1;
            cmd_idx += 1;
        }

        // Footer hint
        const hint = "Press ESC or q to close, j/k to scroll";
        for (hint, 0..) |char, i| {
            surface.writeCell(@intCast(i + 2), @intCast(size.height -| 1), .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 }, .bg = .{ .index = 0 } },
            });
        }
    }
};
