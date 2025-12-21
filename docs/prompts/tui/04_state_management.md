# 04: Advanced State Management

## Goal

Implement comprehensive state management including conversation history, file tracking, undo/redo, and persistence.

## Context

- State needs to track: sessions, messages, tool calls, input, UI mode
- Undo functionality requires snapshot management
- Reference: `/Users/williamcory/plue/core/src/state.zig` (existing Zig state layer)
- Reference: `/Users/williamcory/plue/tui/src/client.ts` (TypeScript patterns)

## Tasks

### 1. Enhance Message Types (src/state/message.zig)

```zig
const std = @import("std");

pub const Message = struct {
    id: u64,
    role: Role,
    content: Content,
    timestamp: i64,
    tool_calls: std.ArrayList(ToolCall),

    pub const Role = enum { user, assistant, system };

    pub const Content = union(enum) {
        text: []const u8,
        parts: []Part,
    };

    pub const Part = union(enum) {
        text: []const u8,
        file_mention: FileMention,
        image: Image,
    };

    pub const FileMention = struct {
        path: []const u8,
        content: ?[]const u8 = null,
        line_start: ?u32 = null,
        line_end: ?u32 = null,
    };

    pub const Image = struct {
        path: []const u8,
        mime_type: []const u8,
        data: ?[]const u8 = null,
    };

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        switch (self.content) {
            .text => |t| allocator.free(t),
            .parts => |parts| {
                for (parts) |part| {
                    switch (part) {
                        .text => |t| allocator.free(t),
                        .file_mention => |f| {
                            allocator.free(f.path);
                            if (f.content) |c| allocator.free(c);
                        },
                        .image => |i| {
                            allocator.free(i.path);
                            allocator.free(i.mime_type);
                            if (i.data) |d| allocator.free(d);
                        },
                    }
                }
                allocator.free(parts);
            },
        }
        for (self.tool_calls.items) |*tc| {
            tc.deinit(allocator);
        }
        self.tool_calls.deinit();
    }
};

pub const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    args: []const u8,
    result: ?ToolResult = null,
    status: Status = .pending,
    started_at: ?i64 = null,
    completed_at: ?i64 = null,

    pub const Status = enum {
        pending,
        running,
        completed,
        failed,
        declined,
    };

    pub const ToolResult = struct {
        output: []const u8,
        is_error: bool = false,
    };

    pub fn deinit(self: *ToolCall, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.args);
        if (self.result) |r| {
            allocator.free(r.output);
        }
    }

    pub fn duration_ms(self: ToolCall) ?u64 {
        if (self.started_at) |start| {
            if (self.completed_at) |end| {
                return @intCast(end - start);
            }
        }
        return null;
    }
};
```

### 2. Create Conversation State (src/state/conversation.zig)

```zig
const std = @import("std");
const Message = @import("message.zig").Message;

pub const Conversation = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayList(Message),
    next_id: u64 = 1,

    // Streaming state
    is_streaming: bool = false,
    streaming_message: ?StreamingMessage = null,

    pub const StreamingMessage = struct {
        text_buffer: std.ArrayList(u8),
        tool_calls: std.ArrayList(Message.ToolCall),
        started_at: i64,
    };

    pub fn init(allocator: std.mem.Allocator) Conversation {
        return .{
            .allocator = allocator,
            .messages = std.ArrayList(Message).init(allocator),
        };
    }

    pub fn deinit(self: *Conversation) void {
        for (self.messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.messages.deinit();
        if (self.streaming_message) |*sm| {
            sm.text_buffer.deinit();
            sm.tool_calls.deinit();
        }
    }

    pub fn addUserMessage(self: *Conversation, content: []const u8) !*Message {
        const id = self.next_id;
        self.next_id += 1;

        try self.messages.append(.{
            .id = id,
            .role = .user,
            .content = .{ .text = try self.allocator.dupe(u8, content) },
            .timestamp = std.time.timestamp(),
            .tool_calls = std.ArrayList(Message.ToolCall).init(self.allocator),
        });

        return &self.messages.items[self.messages.items.len - 1];
    }

    pub fn startStreaming(self: *Conversation) void {
        self.is_streaming = true;
        self.streaming_message = .{
            .text_buffer = std.ArrayList(u8).init(self.allocator),
            .tool_calls = std.ArrayList(Message.ToolCall).init(self.allocator),
            .started_at = std.time.timestamp(),
        };
    }

    pub fn appendStreamingText(self: *Conversation, text: []const u8) !void {
        if (self.streaming_message) |*sm| {
            try sm.text_buffer.appendSlice(text);
        }
    }

    pub fn addStreamingToolCall(self: *Conversation, tool_call: Message.ToolCall) !void {
        if (self.streaming_message) |*sm| {
            try sm.tool_calls.append(tool_call);
        }
    }

    pub fn finishStreaming(self: *Conversation) !?*Message {
        if (self.streaming_message) |sm| {
            self.is_streaming = false;

            if (sm.text_buffer.items.len == 0 and sm.tool_calls.items.len == 0) {
                self.streaming_message = null;
                return null;
            }

            const id = self.next_id;
            self.next_id += 1;

            try self.messages.append(.{
                .id = id,
                .role = .assistant,
                .content = .{ .text = try self.allocator.dupe(u8, sm.text_buffer.items) },
                .timestamp = std.time.timestamp(),
                .tool_calls = sm.tool_calls,
            });

            sm.text_buffer.deinit();
            self.streaming_message = null;

            return &self.messages.items[self.messages.items.len - 1];
        }
        return null;
    }

    pub fn abortStreaming(self: *Conversation) void {
        if (self.streaming_message) |*sm| {
            sm.text_buffer.deinit();
            for (sm.tool_calls.items) |*tc| {
                tc.deinit(self.allocator);
            }
            sm.tool_calls.deinit();
        }
        self.streaming_message = null;
        self.is_streaming = false;
    }

    pub fn getStreamingText(self: *Conversation) ?[]const u8 {
        if (self.streaming_message) |sm| {
            return sm.text_buffer.items;
        }
        return null;
    }

    pub fn getLastMessages(self: *Conversation, count: usize) []Message {
        if (count >= self.messages.items.len) {
            return self.messages.items;
        }
        return self.messages.items[self.messages.items.len - count ..];
    }

    pub fn clear(self: *Conversation) void {
        for (self.messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.messages.clearRetainingCapacity();
        self.next_id = 1;
    }
};
```

### 3. Create Session Manager (src/state/session_manager.zig)

```zig
const std = @import("std");
const Conversation = @import("conversation.zig").Conversation;

pub const Session = struct {
    id: []const u8,
    title: ?[]const u8,
    model: []const u8,
    reasoning_effort: ReasoningEffort,
    directory: []const u8,
    created_at: i64,
    updated_at: i64,

    pub const ReasoningEffort = enum {
        minimal,
        low,
        medium,
        high,

        pub fn toString(self: ReasoningEffort) []const u8 {
            return switch (self) {
                .minimal => "minimal",
                .low => "low",
                .medium => "medium",
                .high => "high",
            };
        }

        pub fn fromString(s: []const u8) ?ReasoningEffort {
            if (std.mem.eql(u8, s, "minimal")) return .minimal;
            if (std.mem.eql(u8, s, "low")) return .low;
            if (std.mem.eql(u8, s, "medium")) return .medium;
            if (std.mem.eql(u8, s, "high")) return .high;
            return null;
        }
    };
};

pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    sessions: std.ArrayList(Session),
    current_session: ?*Session = null,
    conversations: std.StringHashMap(Conversation),

    pub fn init(allocator: std.mem.Allocator) SessionManager {
        return .{
            .allocator = allocator,
            .sessions = std.ArrayList(Session).init(allocator),
            .conversations = std.StringHashMap(Conversation).init(allocator),
        };
    }

    pub fn deinit(self: *SessionManager) void {
        for (self.sessions.items) |session| {
            self.allocator.free(session.id);
            if (session.title) |t| self.allocator.free(t);
            self.allocator.free(session.model);
            self.allocator.free(session.directory);
        }
        self.sessions.deinit();

        var it = self.conversations.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.conversations.deinit();
    }

    pub fn addSession(self: *SessionManager, session: Session) !void {
        try self.sessions.append(session);
        try self.conversations.put(session.id, Conversation.init(self.allocator));
    }

    pub fn switchToSession(self: *SessionManager, id: []const u8) !void {
        for (self.sessions.items) |*session| {
            if (std.mem.eql(u8, session.id, id)) {
                self.current_session = session;
                return;
            }
        }
        return error.SessionNotFound;
    }

    pub fn getCurrentConversation(self: *SessionManager) ?*Conversation {
        if (self.current_session) |session| {
            return self.conversations.getPtr(session.id);
        }
        return null;
    }

    pub fn updateSessionModel(self: *SessionManager, id: []const u8, model: []const u8) !void {
        for (self.sessions.items) |*session| {
            if (std.mem.eql(u8, session.id, id)) {
                self.allocator.free(session.model);
                session.model = try self.allocator.dupe(u8, model);
                session.updated_at = std.time.timestamp();
                return;
            }
        }
        return error.SessionNotFound;
    }

    pub fn getRecentSessions(self: *SessionManager, count: usize) []Session {
        // Sort by updated_at descending
        std.sort.sort(Session, self.sessions.items, {}, struct {
            fn compare(_: void, a: Session, b: Session) bool {
                return a.updated_at > b.updated_at;
            }
        }.compare);

        if (count >= self.sessions.items.len) {
            return self.sessions.items;
        }
        return self.sessions.items[0..count];
    }
};
```

### 4. Create Undo Manager (src/state/undo_manager.zig)

```zig
const std = @import("std");
const Message = @import("message.zig").Message;

pub const UndoManager = struct {
    allocator: std.mem.Allocator,
    snapshots: std.ArrayList(Snapshot),
    max_snapshots: usize = 50,

    pub const Snapshot = struct {
        message_count: usize,
        timestamp: i64,
        description: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) UndoManager {
        return .{
            .allocator = allocator,
            .snapshots = std.ArrayList(Snapshot).init(allocator),
        };
    }

    pub fn deinit(self: *UndoManager) void {
        for (self.snapshots.items) |snapshot| {
            self.allocator.free(snapshot.description);
        }
        self.snapshots.deinit();
    }

    pub fn createSnapshot(self: *UndoManager, message_count: usize, description: []const u8) !void {
        // Remove oldest if at capacity
        if (self.snapshots.items.len >= self.max_snapshots) {
            const old = self.snapshots.orderedRemove(0);
            self.allocator.free(old.description);
        }

        try self.snapshots.append(.{
            .message_count = message_count,
            .timestamp = std.time.timestamp(),
            .description = try self.allocator.dupe(u8, description),
        });
    }

    pub fn getUndoTarget(self: *UndoManager, turns: usize) ?Snapshot {
        if (turns == 0 or turns > self.snapshots.items.len) {
            return null;
        }

        const idx = self.snapshots.items.len - turns;
        return self.snapshots.items[idx];
    }

    pub fn popSnapshots(self: *UndoManager, count: usize) void {
        var i: usize = 0;
        while (i < count and self.snapshots.items.len > 0) : (i += 1) {
            const snapshot = self.snapshots.pop();
            self.allocator.free(snapshot.description);
        }
    }

    pub fn getSnapshotCount(self: *UndoManager) usize {
        return self.snapshots.items.len;
    }
};
```

### 5. Create Unified App State (src/state/app_state.zig)

```zig
const std = @import("std");
const SessionManager = @import("session_manager.zig").SessionManager;
const Session = @import("session_manager.zig").Session;
const Conversation = @import("conversation.zig").Conversation;
const UndoManager = @import("undo_manager.zig").UndoManager;
const Message = @import("message.zig").Message;

pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    reconnecting,
    error,
};

pub const UiMode = enum {
    chat,
    model_select,
    session_select,
    file_search,
    approval,
    help,
    feedback,
};

pub const AppState = struct {
    allocator: std.mem.Allocator,

    // Configuration
    api_url: []const u8,
    working_directory: []const u8,

    // Connection
    connection: ConnectionState = .disconnected,
    last_error: ?[]const u8 = null,

    // Session management
    session_manager: SessionManager,
    undo_manager: UndoManager,

    // Input state
    input_buffer: std.ArrayList(u8),
    input_cursor: usize = 0,
    input_history: std.ArrayList([]const u8),
    history_index: ?usize = null,

    // UI state
    mode: UiMode = .chat,
    scroll_offset: usize = 0,
    selected_index: usize = 0,

    // Token tracking
    token_usage: TokenUsage = .{},

    // Available models
    available_models: []const []const u8 = &.{
        "claude-sonnet-4-20250514",
        "claude-opus-4-20250514",
        "claude-3-5-sonnet-20241022",
        "claude-3-5-haiku-20241022",
    },

    pub const TokenUsage = struct {
        input: u64 = 0,
        output: u64 = 0,
        cached: u64 = 0,

        pub fn total(self: TokenUsage) u64 {
            return self.input + self.output;
        }
    };

    pub fn init(allocator: std.mem.Allocator, api_url: []const u8) !AppState {
        // Get current working directory
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = try std.fs.cwd().realpath(".", &cwd_buf);

        return .{
            .allocator = allocator,
            .api_url = api_url,
            .working_directory = try allocator.dupe(u8, cwd),
            .session_manager = SessionManager.init(allocator),
            .undo_manager = UndoManager.init(allocator),
            .input_buffer = std.ArrayList(u8).init(allocator),
            .input_history = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *AppState) void {
        self.allocator.free(self.working_directory);
        self.session_manager.deinit();
        self.undo_manager.deinit();
        self.input_buffer.deinit();
        for (self.input_history.items) |h| {
            self.allocator.free(h);
        }
        self.input_history.deinit();
        if (self.last_error) |e| {
            self.allocator.free(e);
        }
    }

    // Convenience accessors
    pub fn currentSession(self: *AppState) ?*Session {
        return self.session_manager.current_session;
    }

    pub fn currentConversation(self: *AppState) ?*Conversation {
        return self.session_manager.getCurrentConversation();
    }

    pub fn isStreaming(self: *AppState) bool {
        if (self.currentConversation()) |conv| {
            return conv.is_streaming;
        }
        return false;
    }

    // Input handling
    pub fn insertText(self: *AppState, text: []const u8) !void {
        try self.input_buffer.insertSlice(self.input_cursor, text);
        self.input_cursor += text.len;
    }

    pub fn deleteBackward(self: *AppState) void {
        if (self.input_cursor > 0) {
            _ = self.input_buffer.orderedRemove(self.input_cursor - 1);
            self.input_cursor -= 1;
        }
    }

    pub fn deleteForward(self: *AppState) void {
        if (self.input_cursor < self.input_buffer.items.len) {
            _ = self.input_buffer.orderedRemove(self.input_cursor);
        }
    }

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

    pub fn getInput(self: *AppState) []const u8 {
        return self.input_buffer.items;
    }

    pub fn clearInput(self: *AppState) void {
        self.input_buffer.clearRetainingCapacity();
        self.input_cursor = 0;
    }

    pub fn saveToHistory(self: *AppState) !void {
        if (self.input_buffer.items.len > 0) {
            const copy = try self.allocator.dupe(u8, self.input_buffer.items);
            try self.input_history.append(copy);
            self.history_index = null;
        }
    }

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
            self.input_buffer.appendSlice(self.input_history.items[idx]) catch {};
            self.input_cursor = self.input_buffer.items.len;
        }
    }

    // Error handling
    pub fn setError(self: *AppState, message: []const u8) !void {
        if (self.last_error) |e| {
            self.allocator.free(e);
        }
        self.last_error = try self.allocator.dupe(u8, message);
        self.connection = .error;
    }

    pub fn clearError(self: *AppState) void {
        if (self.last_error) |e| {
            self.allocator.free(e);
            self.last_error = null;
        }
        if (self.connection == .error) {
            self.connection = .disconnected;
        }
    }
};
```

## Acceptance Criteria

- [ ] Message types support text, file mentions, images
- [ ] ToolCall tracks full lifecycle (pending → running → completed/failed)
- [ ] Conversation manages message history and streaming
- [ ] SessionManager handles multiple sessions
- [ ] UndoManager tracks snapshots for rollback
- [ ] AppState provides unified access to all state
- [ ] Input handling includes cursor, history, editing

## Files to Create

1. `tui-zig/src/state/message.zig`
2. `tui-zig/src/state/conversation.zig`
3. `tui-zig/src/state/session_manager.zig`
4. `tui-zig/src/state/undo_manager.zig`
5. Update `tui-zig/src/state/app_state.zig`

## Next

Proceed to `05_layout_system.md` for the layout and widget composition system.
