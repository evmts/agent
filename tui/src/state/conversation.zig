const std = @import("std");
const message_mod = @import("message.zig");
const Message = message_mod.Message;
const ToolCall = message_mod.ToolCall;

/// Streaming message state
pub const StreamingMessage = struct {
    text_buffer: std.ArrayList(u8),
    tool_calls: std.ArrayList(ToolCall),
    started_at: i64,
};

/// Conversation state managing messages and streaming
pub const Conversation = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayList(Message),
    next_id: u64 = 1,

    // Streaming state
    is_streaming: bool = false,
    streaming_message: ?StreamingMessage = null,

    /// Initialize a new conversation
    pub fn init(allocator: std.mem.Allocator) Conversation {
        return .{
            .allocator = allocator,
            .messages = std.ArrayList(Message){},
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *Conversation) void {
        for (self.messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.messages.deinit(self.allocator);
        if (self.streaming_message) |*sm| {
            sm.text_buffer.deinit(self.allocator);
            for (sm.tool_calls.items) |*tc| {
                tc.deinit(self.allocator);
            }
            sm.tool_calls.deinit(self.allocator);
        }
    }

    /// Add a user message to the conversation
    pub fn addUserMessage(self: *Conversation, content: []const u8) !*Message {
        const id = self.next_id;
        self.next_id += 1;

        try self.messages.append(self.allocator, .{
            .id = id,
            .role = .user,
            .content = .{ .text = try self.allocator.dupe(u8, content) },
            .timestamp = std.time.timestamp(),
            .tool_calls = std.ArrayList(ToolCall){},
        });

        return &self.messages.items[self.messages.items.len - 1];
    }

    /// Start streaming a new assistant message
    pub fn startStreaming(self: *Conversation) void {
        self.is_streaming = true;
        self.streaming_message = .{
            .text_buffer = std.ArrayList(u8){},
            .tool_calls = std.ArrayList(ToolCall){},
            .started_at = std.time.timestamp(),
        };
    }

    /// Append text to the current streaming message
    pub fn appendStreamingText(self: *Conversation, text: []const u8) !void {
        if (self.streaming_message) |*sm| {
            try sm.text_buffer.appendSlice(self.allocator, text);
        }
    }

    /// Add a tool call to the current streaming message
    pub fn addStreamingToolCall(self: *Conversation, tool_call: ToolCall) !void {
        if (self.streaming_message) |*sm| {
            try sm.tool_calls.append(self.allocator, tool_call);
        }
    }

    /// Finish streaming and convert to a permanent message
    pub fn finishStreaming(self: *Conversation) !?*Message {
        if (self.streaming_message) |*sm| {
            self.is_streaming = false;

            if (sm.text_buffer.items.len == 0 and sm.tool_calls.items.len == 0) {
                self.streaming_message = null;
                return null;
            }

            const id = self.next_id;
            self.next_id += 1;

            try self.messages.append(self.allocator, .{
                .id = id,
                .role = .assistant,
                .content = .{ .text = try self.allocator.dupe(u8, sm.text_buffer.items) },
                .timestamp = std.time.timestamp(),
                .tool_calls = sm.tool_calls,
            });

            sm.text_buffer.deinit(self.allocator);
            self.streaming_message = null;

            return &self.messages.items[self.messages.items.len - 1];
        }
        return null;
    }

    /// Abort current streaming and discard the message
    pub fn abortStreaming(self: *Conversation) void {
        if (self.streaming_message) |*sm| {
            sm.text_buffer.deinit(self.allocator);
            for (sm.tool_calls.items) |*tc| {
                tc.deinit(self.allocator);
            }
            sm.tool_calls.deinit(self.allocator);
        }
        self.streaming_message = null;
        self.is_streaming = false;
    }

    /// Get the current streaming text (if streaming)
    pub fn getStreamingText(self: *Conversation) ?[]const u8 {
        if (self.streaming_message) |sm| {
            return sm.text_buffer.items;
        }
        return null;
    }

    /// Get the last N messages
    pub fn getLastMessages(self: *Conversation, count: usize) []Message {
        if (count >= self.messages.items.len) {
            return self.messages.items;
        }
        return self.messages.items[self.messages.items.len - count ..];
    }

    /// Clear all messages from the conversation
    pub fn clear(self: *Conversation) void {
        for (self.messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.messages.clearRetainingCapacity();
        self.next_id = 1;
    }
};
