//! Agent WebSocket Handler
//!
//! Handles WebSocket connections for agent streaming. Clients can subscribe to
//! sessions and receive real-time token streaming, tool calls, and results.
//!
//! Protocol:
//! Client → Server: { "type": "subscribe" | "unsubscribe" | "abort" | "ping", "session_id": "..." }
//! Server → Client: { "type": "token" | "tool_start" | "tool_end" | "done" | "error" | "pong", ... }

const std = @import("std");
const httpz = @import("httpz");
const client = @import("../ai/client.zig");
const types = @import("../ai/types.zig");

const log = std.log.scoped(.agent_ws);

/// WebSocket message types from client
pub const ClientMessageType = enum {
    subscribe,
    unsubscribe,
    abort,
    ping,
};

/// WebSocket message types to client
pub const ServerMessageType = enum {
    token,
    tool_start,
    tool_end,
    tool_result,
    done,
    @"error",
    pong,
};

/// Context passed during WebSocket upgrade
pub const UpgradeContext = struct {
    session_id: ?[]const u8,
    allocator: std.mem.Allocator,
};

/// Agent WebSocket handler - handles per-connection state
pub const AgentWebSocket = struct {
    conn: *httpz.websocket.Conn,
    allocator: std.mem.Allocator,
    session_id: ?[]const u8,
    running: std.atomic.Value(bool),
    aborted: std.atomic.Value(bool),

    /// Initialize the WebSocket handler
    pub fn init(conn: *httpz.websocket.Conn, ctx: *const UpgradeContext) !AgentWebSocket {
        log.info("Agent WebSocket handler initialized", .{});

        return .{
            .conn = conn,
            .allocator = ctx.allocator,
            .session_id = if (ctx.session_id) |sid| try ctx.allocator.dupe(u8, sid) else null,
            .running = std.atomic.Value(bool).init(true),
            .aborted = std.atomic.Value(bool).init(false),
        };
    }

    /// Called after initialization
    pub fn afterInit(self: *AgentWebSocket) !void {
        log.info("Agent WebSocket connection established, session: {?s}", .{self.session_id});

        // Send connection acknowledgment
        try self.sendPong();
    }

    /// Handle incoming WebSocket messages from client
    pub fn clientMessage(self: *AgentWebSocket, data: []const u8) !void {
        // Parse JSON message
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, data, .{}) catch {
            try self.sendError("Invalid JSON message");
            return;
        };
        defer parsed.deinit();

        const root = parsed.value.object;
        const msg_type_str = root.get("type") orelse {
            try self.sendError("Missing 'type' field");
            return;
        };

        if (msg_type_str != .string) {
            try self.sendError("'type' must be a string");
            return;
        }

        const msg_type = msg_type_str.string;

        if (std.mem.eql(u8, msg_type, "ping")) {
            try self.sendPong();
        } else if (std.mem.eql(u8, msg_type, "subscribe")) {
            if (root.get("session_id")) |sid| {
                if (sid == .string) {
                    // Update subscription
                    if (self.session_id) |old| {
                        self.allocator.free(old);
                    }
                    self.session_id = try self.allocator.dupe(u8, sid.string);
                    log.info("Client subscribed to session: {s}", .{self.session_id.?});
                    try self.sendJson("{\"type\":\"subscribed\"}");
                }
            }
        } else if (std.mem.eql(u8, msg_type, "unsubscribe")) {
            if (self.session_id) |sid| {
                log.info("Client unsubscribed from session: {s}", .{sid});
                self.allocator.free(sid);
                self.session_id = null;
            }
            try self.sendJson("{\"type\":\"unsubscribed\"}");
        } else if (std.mem.eql(u8, msg_type, "abort")) {
            self.aborted.store(true, .release);
            log.info("Client requested abort for session: {?s}", .{self.session_id});
            try self.sendJson("{\"type\":\"aborted\"}");
        } else {
            try self.sendError("Unknown message type");
        }
    }

    /// Called when WebSocket connection closes
    pub fn close(self: *AgentWebSocket) void {
        log.info("Agent WebSocket closing, session: {?s}", .{self.session_id});
        self.running.store(false, .release);

        if (self.session_id) |sid| {
            self.allocator.free(sid);
        }
    }

    // =========================================================================
    // Server → Client message sending
    // =========================================================================

    /// Send a token event (text delta from Claude)
    pub fn sendToken(self: *AgentWebSocket, session_id: []const u8, message_id: []const u8, text: []const u8, token_index: usize) !void {
        var buf: [8192]u8 = undefined;
        const escaped = escapeJsonString(&buf, text);
        var msg_buf: [16384]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "{{\"type\":\"token\",\"session_id\":\"{s}\",\"message_id\":\"{s}\",\"text\":{s},\"token_index\":{d}}}", .{
            session_id,
            message_id,
            escaped,
            token_index,
        }) catch return error.BufferTooSmall;
        try self.sendJson(msg);
    }

    /// Send a tool start event
    pub fn sendToolStart(self: *AgentWebSocket, session_id: []const u8, message_id: []const u8, tool_id: []const u8, tool_name: []const u8) !void {
        var buf: [4096]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"tool_start\",\"session_id\":\"{s}\",\"message_id\":\"{s}\",\"tool_id\":\"{s}\",\"tool_name\":\"{s}\"}}", .{
            session_id,
            message_id,
            tool_id,
            tool_name,
        }) catch return error.BufferTooSmall;
        try self.sendJson(msg);
    }

    /// Send a tool end event
    pub fn sendToolEnd(self: *AgentWebSocket, session_id: []const u8, tool_id: []const u8, tool_state: []const u8, output: ?[]const u8) !void {
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
        try self.sendJson(msg);
    }

    /// Send a done event
    pub fn sendDone(self: *AgentWebSocket, session_id: []const u8) !void {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"done\",\"session_id\":\"{s}\"}}", .{session_id}) catch return error.BufferTooSmall;
        try self.sendJson(msg);
    }

    /// Send an error event
    pub fn sendError(self: *AgentWebSocket, message: []const u8) !void {
        var buf: [1024]u8 = undefined;
        var escaped_buf: [512]u8 = undefined;
        const escaped = escapeJsonString(&escaped_buf, message);
        const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"error\",\"message\":{s}}}", .{escaped}) catch return error.BufferTooSmall;
        try self.sendJson(msg);
    }

    /// Send a pong response
    fn sendPong(self: *AgentWebSocket) !void {
        try self.sendJson("{\"type\":\"pong\"}");
    }

    /// Send raw JSON message
    fn sendJson(self: *AgentWebSocket, json: []const u8) !void {
        self.conn.write(json) catch |err| {
            log.err("Failed to send WebSocket message: {}", .{err});
            return err;
        };
    }

    /// Check if the connection is aborted
    pub fn isAborted(self: *const AgentWebSocket) bool {
        return self.aborted.load(.acquire);
    }

    /// Check if the connection is still running
    pub fn isRunning(self: *const AgentWebSocket) bool {
        return self.running.load(.acquire);
    }
};

/// Manager for tracking WebSocket connections per session
pub const ConnectionManager = struct {
    const Self = @This();
    const ConnectionList = std.ArrayList(*AgentWebSocket);

    allocator: std.mem.Allocator,
    sessions: std.StringHashMap(ConnectionList),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .sessions = std.StringHashMap(ConnectionList).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.sessions.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.allocator);
        }

        var key_it = self.sessions.keyIterator();
        while (key_it.next()) |key| {
            self.allocator.free(key.*);
        }

        self.sessions.deinit();
    }

    /// Register a WebSocket connection for a session
    pub fn subscribe(self: *Self, session_id: []const u8, ws: *AgentWebSocket) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.getPtr(session_id)) |list| {
            try list.append(self.allocator, ws);
        } else {
            const owned_id = try self.allocator.dupe(u8, session_id);
            var list = ConnectionList{};
            try list.append(self.allocator, ws);
            try self.sessions.put(owned_id, list);
        }
    }

    /// Unregister a WebSocket connection
    pub fn unsubscribe(self: *Self, session_id: []const u8, ws: *AgentWebSocket) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.getPtr(session_id)) |list| {
            // Find and remove the connection
            var i: usize = 0;
            while (i < list.items.len) {
                if (list.items[i] == ws) {
                    _ = list.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }

    /// Broadcast a token event to all subscribers of a session
    pub fn broadcastToken(self: *Self, session_id: []const u8, message_id: []const u8, text: []const u8, token_index: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.get(session_id)) |list| {
            for (list.items) |ws| {
                ws.sendToken(session_id, message_id, text, token_index) catch |err| {
                    log.err("Failed to broadcast token: {}", .{err});
                };
            }
        }
    }

    /// Broadcast a tool start event
    pub fn broadcastToolStart(self: *Self, session_id: []const u8, message_id: []const u8, tool_id: []const u8, tool_name: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.get(session_id)) |list| {
            for (list.items) |ws| {
                ws.sendToolStart(session_id, message_id, tool_id, tool_name) catch |err| {
                    log.err("Failed to broadcast tool_start: {}", .{err});
                };
            }
        }
    }

    /// Broadcast a tool end event
    pub fn broadcastToolEnd(self: *Self, session_id: []const u8, tool_id: []const u8, tool_state: []const u8, output: ?[]const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.get(session_id)) |list| {
            for (list.items) |ws| {
                ws.sendToolEnd(session_id, tool_id, tool_state, output) catch |err| {
                    log.err("Failed to broadcast tool_end: {}", .{err});
                };
            }
        }
    }

    /// Broadcast a done event
    pub fn broadcastDone(self: *Self, session_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.get(session_id)) |list| {
            for (list.items) |ws| {
                ws.sendDone(session_id) catch |err| {
                    log.err("Failed to broadcast done: {}", .{err});
                };
            }
        }
    }

    /// Broadcast an error event
    pub fn broadcastError(self: *Self, session_id: []const u8, message: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.get(session_id)) |list| {
            for (list.items) |ws| {
                ws.sendError(message) catch |err| {
                    log.err("Failed to broadcast error: {}", .{err});
                };
            }
        }
    }

    /// Check if any subscriber has aborted
    pub fn isAborted(self: *Self, session_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.get(session_id)) |list| {
            for (list.items) |ws| {
                if (ws.isAborted()) return true;
            }
        }
        return false;
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

test "AgentWebSocket struct fields" {
    const info = @typeInfo(AgentWebSocket);
    try std.testing.expect(info == .@"struct");

    // Should have fields: conn, allocator, session_id, running, aborted
    const fields = info.@"struct".fields;
    try std.testing.expect(fields.len == 5);
}
