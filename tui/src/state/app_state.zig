const std = @import("std");
const types = @import("../types.zig");
const session_mod = @import("session.zig");
const conversation_mod = @import("conversation.zig");

const Session = session_mod.Session;
const ReasoningEffort = session_mod.ReasoningEffort;
const Conversation = conversation_mod.Conversation;
const Message = @import("message.zig").Message;

/// Unified application state
pub const AppState = struct {
    allocator: std.mem.Allocator,

    // Configuration
    api_url: []const u8,
    working_directory: []const u8,

    // Connection state
    connection: types.ConnectionState = .disconnected,
    last_error: ?[]const u8 = null,

    // Session management
    sessions: std.ArrayList(Session),
    current_session: ?*Session = null,
    conversations: std.StringHashMap(Conversation),

    // Input state
    input_buffer: std.ArrayList(u8),
    input_cursor: usize = 0,
    input_history: std.ArrayList([]const u8),
    history_index: ?usize = null,

    // UI state
    mode: types.UiMode = .chat,
    scroll_offset: usize = 0,
    selected_index: usize = 0,

    // Token tracking
    token_usage: types.TokenUsage = .{},

    // Available models
    available_models: []const []const u8 = &.{
        "claude-sonnet-4-20250514",
        "claude-opus-4-20250514",
        "claude-3-5-sonnet-20241022",
        "claude-3-5-haiku-20241022",
    },

    /// Initialize the application state
    pub fn init(allocator: std.mem.Allocator, api_url: []const u8) !AppState {
        // Get current working directory
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = try std.fs.cwd().realpath(".", &cwd_buf);

        return .{
            .allocator = allocator,
            .api_url = api_url,
            .working_directory = try allocator.dupe(u8, cwd),
            .sessions = std.ArrayList(Session){},
            .conversations = std.StringHashMap(Conversation).init(allocator),
            .input_buffer = std.ArrayList(u8){},
            .input_history = std.ArrayList([]const u8){},
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *AppState) void {
        self.allocator.free(self.working_directory);

        for (self.sessions.items) |*s| {
            s.deinit(self.allocator);
        }
        self.sessions.deinit(self.allocator);

        var it = self.conversations.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.conversations.deinit();

        self.input_buffer.deinit(self.allocator);

        for (self.input_history.items) |h| {
            self.allocator.free(h);
        }
        self.input_history.deinit(self.allocator);

        if (self.last_error) |e| {
            self.allocator.free(e);
        }
    }

    // Session management

    /// Add a new session
    pub fn addSession(self: *AppState, sess: Session) !void {
        try self.sessions.append(self.allocator, sess);
        try self.conversations.put(sess.id, Conversation.init(self.allocator));
    }

    /// Switch to a different session by ID
    pub fn switchToSession(self: *AppState, id: []const u8) !void {
        for (self.sessions.items) |*sess| {
            if (std.mem.eql(u8, sess.id, id)) {
                self.current_session = sess;
                return;
            }
        }
        return error.SessionNotFound;
    }

    /// Get the current session (if any)
    pub fn currentSession(self: *AppState) ?*Session {
        return self.current_session;
    }

    /// Get the conversation for the current session
    pub fn currentConversation(self: *AppState) ?*Conversation {
        if (self.current_session) |sess| {
            return self.conversations.getPtr(sess.id);
        }
        return null;
    }

    /// Check if currently streaming
    pub fn isStreaming(self: *AppState) bool {
        if (self.currentConversation()) |conv| {
            return conv.is_streaming;
        }
        return false;
    }

    // Input handling

    /// Insert text at the current cursor position
    pub fn insertText(self: *AppState, text: []const u8) !void {
        try self.input_buffer.insertSlice(self.allocator, self.input_cursor, text);
        self.input_cursor += text.len;
    }

    /// Delete character before cursor
    pub fn deleteBackward(self: *AppState) void {
        if (self.input_cursor > 0) {
            _ = self.input_buffer.orderedRemove(self.input_cursor - 1);
            self.input_cursor -= 1;
        }
    }

    /// Delete character at cursor
    pub fn deleteForward(self: *AppState) void {
        if (self.input_cursor < self.input_buffer.items.len) {
            _ = self.input_buffer.orderedRemove(self.input_cursor);
        }
    }

    /// Move cursor by delta (can be negative)
    pub fn moveCursor(self: *AppState, delta: i32) void {
        const new_pos = @as(i64, @intCast(self.input_cursor)) + delta;
        if (new_pos < 0) {
            self.input_cursor = 0;
        } else if (new_pos > self.input_buffer.items.len) {
            self.input_cursor = self.input_buffer.items.len;
        } else {
            self.input_cursor = @intCast(new_pos);
        }
    }

    /// Get the current input text
    pub fn getInput(self: *AppState) []const u8 {
        return self.input_buffer.items;
    }

    /// Clear the input buffer
    pub fn clearInput(self: *AppState) void {
        self.input_buffer.clearRetainingCapacity();
        self.input_cursor = 0;
    }

    /// Save current input to history
    pub fn saveToHistory(self: *AppState) !void {
        if (self.input_buffer.items.len > 0) {
            const copy = try self.allocator.dupe(u8, self.input_buffer.items);
            try self.input_history.append(self.allocator, copy);
            self.history_index = null;
        }
    }

    /// Navigate through input history
    pub fn navigateHistory(self: *AppState, direction: i32) void {
        if (self.input_history.items.len == 0) return;

        const current = self.history_index orelse self.input_history.items.len;
        const new_idx = @as(i64, @intCast(current)) + direction;

        if (new_idx < 0) {
            self.history_index = 0;
        } else if (new_idx >= self.input_history.items.len) {
            self.history_index = null;
            self.clearInput();
            return;
        } else {
            self.history_index = @intCast(new_idx);
        }

        if (self.history_index) |idx| {
            self.input_buffer.clearRetainingCapacity();
            self.input_buffer.appendSlice(self.allocator, self.input_history.items[idx]) catch {};
            self.input_cursor = self.input_buffer.items.len;
        }
    }

    // Error handling

    /// Set an error message
    pub fn setError(self: *AppState, err_msg: []const u8) !void {
        if (self.last_error) |e| {
            self.allocator.free(e);
        }
        self.last_error = try self.allocator.dupe(u8, err_msg);
        self.connection = .err;
    }

    /// Clear the current error
    pub fn clearError(self: *AppState) void {
        if (self.last_error) |e| {
            self.allocator.free(e);
            self.last_error = null;
        }
        if (self.connection == .err) {
            self.connection = .disconnected;
        }
    }
};
