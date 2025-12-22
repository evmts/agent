//! Agent SSE (Server-Sent Events) Handler
//!
//! Handles SSE connections for agent streaming. Clients connect via EventSource
//! and receive real-time token streaming, tool calls, and results.
//!
//! Protocol:
//! Client → Server: HTTP GET /api/sessions/:sessionId/stream (EventSource connection)
//! Client → Server: HTTP POST /api/sessions/:sessionId/abort (abort execution)
//! Server → Client: SSE events: token, tool_start, tool_end, done, error

const std = @import("std");
const httpz = @import("httpz");
const client = @import("../ai/client.zig");
const types = @import("../ai/types.zig");

const log = std.log.scoped(.agent_sse);

/// SSE event types sent to client
pub const SSEEventType = enum {
    token,
    tool_start,
    tool_end,
    tool_result,
    done,
    @"error",
    keepalive,
};

/// Agent SSE response handler - handles per-connection state
pub fn AgentSSEResponse(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        aborted: std.atomic.Value(bool),

        /// Initialize the SSE response handler
        pub fn init(writer: Writer, allocator: std.mem.Allocator, session_id: []const u8) Self {
            log.info("Agent SSE handler initialized for session: {s}", .{session_id});

            return .{
                .writer = writer,
                .allocator = allocator,
                .session_id = session_id,
                .aborted = std.atomic.Value(bool).init(false),
            };
        }

    // =========================================================================
    // Server → Client SSE event sending
    // =========================================================================

    /// Send a token event (text delta from Claude)
    pub fn sendToken(self: *Self, session_id: []const u8, message_id: []const u8, text: []const u8, token_index: usize) !void {
        var buf: [8192]u8 = undefined;
        const escaped = escapeJsonString(&buf, text);
        var msg_buf: [16384]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "{{\"type\":\"token\",\"session_id\":\"{s}\",\"message_id\":\"{s}\",\"text\":{s},\"token_index\":{d}}}", .{
            session_id,
            message_id,
            escaped,
            token_index,
        }) catch return error.BufferTooSmall;
        try self.sendSSE("token", msg);
    }

    /// Send a tool start event
    pub fn sendToolStart(self: *Self, session_id: []const u8, message_id: []const u8, tool_id: []const u8, tool_name: []const u8) !void {
        var buf: [4096]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"tool_start\",\"session_id\":\"{s}\",\"message_id\":\"{s}\",\"tool_id\":\"{s}\",\"tool_name\":\"{s}\"}}", .{
            session_id,
            message_id,
            tool_id,
            tool_name,
        }) catch return error.BufferTooSmall;
        try self.sendSSE("tool_start", msg);
    }

    /// Send a tool end event
    pub fn sendToolEnd(self: *Self, session_id: []const u8, tool_id: []const u8, tool_state: []const u8, output: ?[]const u8) !void {
        var buf: [8192]u8 = undefined;
        var escaped_buf: [4096]u8 = undefined;

        const msg = if (output) |out| blk: {
            const escaped = escapeJsonString(&escaped_buf, out);
            break :blk std.fmt.bufPrint(&buf, "{{\"type\":\"tool_end\",\"session_id\":\"{s}\",\"tool_id\":\"{s}\",\"tool_state\":\"{s}\",\"output\":{s}}}", .{
                session_id,
                tool_id,
                tool_state,
                escaped,
            }) catch return error.BufferTooSmall;
        } else blk: {
            break :blk std.fmt.bufPrint(&buf, "{{\"type\":\"tool_end\",\"session_id\":\"{s}\",\"tool_id\":\"{s}\",\"tool_state\":\"{s}\"}}", .{
                session_id,
                tool_id,
                tool_state,
            }) catch return error.BufferTooSmall;
        };
        try self.sendSSE("tool_end", msg);
    }

    /// Send a done event
    pub fn sendDone(self: *Self, session_id: []const u8) !void {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"done\",\"session_id\":\"{s}\"}}", .{session_id}) catch return error.BufferTooSmall;
        try self.sendSSE("done", msg);
    }

    /// Send an error event
    pub fn sendError(self: *Self, message: []const u8) !void {
        var buf: [1024]u8 = undefined;
        var escaped_buf: [512]u8 = undefined;
        const escaped = escapeJsonString(&escaped_buf, message);
        const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"error\",\"message\":{s}}}", .{escaped}) catch return error.BufferTooSmall;
        try self.sendSSE("error", msg);
    }

    /// Send a keepalive comment (to prevent connection timeout)
    pub fn sendKeepalive(self: *Self) !void {
        self.writer.writeAll(": keepalive\n\n") catch |err| {
            log.err("Failed to send SSE keepalive: {}", .{err});
            return err;
        };
    }

    /// Send an SSE event with event type and data
    fn sendSSE(self: *Self, event_type: []const u8, data: []const u8) !void {
        self.writer.print("event: {s}\ndata: {s}\n\n", .{ event_type, data }) catch |err| {
            log.err("Failed to send SSE event: {}", .{err});
            return err;
        };
    }

    /// Check if the connection is aborted
    pub fn isAborted(self: *const Self) bool {
        return self.aborted.load(.acquire);
    }

    /// Mark as aborted
    pub fn abort(self: *Self) void {
        self.aborted.store(true, .release);
        log.info("Session {s} aborted", .{self.session_id});
    }
    };
}

/// Manager for tracking abort flags per session
/// Since SSE is one-way, abort is handled via REST endpoint
pub const ConnectionManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    abort_flags: std.StringHashMap(std.atomic.Value(bool)),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .abort_flags = std.StringHashMap(std.atomic.Value(bool)).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var key_it = self.abort_flags.keyIterator();
        while (key_it.next()) |key| {
            self.allocator.free(key.*);
        }

        self.abort_flags.deinit();
    }

    /// Set abort flag for a session
    pub fn abort(self: *Self, session_id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.abort_flags.getPtr(session_id)) |flag| {
            flag.store(true, .release);
            log.info("Abort flag set for session: {s}", .{session_id});
        } else {
            // Create abort flag if it doesn't exist
            const owned_id = try self.allocator.dupe(u8, session_id);
            var flag = std.atomic.Value(bool).init(true);
            try self.abort_flags.put(owned_id, flag);
            log.info("Abort flag created and set for session: {s}", .{session_id});
        }
    }

    /// Check if session is aborted
    pub fn isAborted(self: *Self, session_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.abort_flags.getPtr(session_id)) |flag| {
            return flag.load(.acquire);
        }
        return false;
    }

    /// Clear abort flag for a session (called when starting new execution)
    pub fn clearAbort(self: *Self, session_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.abort_flags.getPtr(session_id)) |flag| {
            flag.store(false, .release);
            log.info("Abort flag cleared for session: {s}", .{session_id});
        }
    }

    /// Remove session from tracking
    pub fn removeSession(self: *Self, session_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.abort_flags.fetchRemove(session_id)) |entry| {
            self.allocator.free(entry.key);
            log.info("Session removed from abort tracking: {s}", .{session_id});
        }
    }
};

// =============================================================================
// Helper Functions
// =============================================================================

/// Escape a string for JSON (inline, no allocation)
fn escapeJsonString(buf: []u8, input: []const u8) []const u8 {
    var pos: usize = 0;

    // Start with quote
    if (pos < buf.len) {
        buf[pos] = '"';
        pos += 1;
    }

    for (input) |char| {
        if (pos + 2 >= buf.len) break;

        switch (char) {
            '"' => {
                buf[pos] = '\\';
                buf[pos + 1] = '"';
                pos += 2;
            },
            '\\' => {
                buf[pos] = '\\';
                buf[pos + 1] = '\\';
                pos += 2;
            },
            '\n' => {
                buf[pos] = '\\';
                buf[pos + 1] = 'n';
                pos += 2;
            },
            '\r' => {
                buf[pos] = '\\';
                buf[pos + 1] = 'r';
                pos += 2;
            },
            '\t' => {
                buf[pos] = '\\';
                buf[pos + 1] = 't';
                pos += 2;
            },
            else => {
                buf[pos] = char;
                pos += 1;
            },
        }
    }

    // End with quote
    if (pos < buf.len) {
        buf[pos] = '"';
        pos += 1;
    }

    return buf[0..pos];
}

// =============================================================================
// Tests
// =============================================================================

test "escapeJsonString basic" {
    var buf: [256]u8 = undefined;

    const result = escapeJsonString(&buf, "hello");
    try std.testing.expectEqualStrings("\"hello\"", result);
}

test "escapeJsonString with newline" {
    var buf: [256]u8 = undefined;

    const result = escapeJsonString(&buf, "hello\nworld");
    try std.testing.expectEqualStrings("\"hello\\nworld\"", result);
}

test "escapeJsonString with quotes" {
    var buf: [256]u8 = undefined;

    const result = escapeJsonString(&buf, "say \"hello\"");
    try std.testing.expectEqualStrings("\"say \\\"hello\\\"\"", result);
}

test "ConnectionManager init/deinit" {
    var manager = ConnectionManager.init(std.testing.allocator);
    defer manager.deinit();
}

test "AgentSSEResponse is a function" {
    // AgentSSEResponse is now a function that returns a type
    const ResponseType = AgentSSEResponse(std.io.AnyWriter);
    const info = @typeInfo(ResponseType);
    try std.testing.expect(info == .@"struct");
}
