const std = @import("std");
const httpz = @import("httpz");
const pty = @import("pty.zig");

const log = std.log.scoped(.ws);

/// Context passed to WebSocket handler during upgrade
pub const UpgradeContext = struct {
    session: *pty.Session,
};

/// WebSocket client handler for PTY connections
pub const PtyWebSocket = struct {
    conn: *httpz.websocket.Conn,
    session: *pty.Session,
    running: std.atomic.Value(bool),
    reader_thread: ?std.Thread,

    /// Initialize the WebSocket handler
    pub fn init(conn: *httpz.websocket.Conn, ctx: *const UpgradeContext) !PtyWebSocket {
        log.info("WebSocket handler initialized for PTY session: {s}", .{ctx.session.id});

        return .{
            .conn = conn,
            .session = ctx.session,
            .running = std.atomic.Value(bool).init(true),
            .reader_thread = null,
        };
    }

    /// Called after initialization - start the output reader thread
    pub fn afterInit(self: *PtyWebSocket) !void {
        log.info("Starting output reader for PTY session: {s}", .{self.session.id});

        // Send welcome message
        try self.conn.write("PTY session connected\r\n");

        // Start reader thread
        self.reader_thread = try std.Thread.spawn(.{}, outputReaderThread, .{self});
    }

    /// Handle incoming WebSocket messages (user input to PTY)
    pub fn clientMessage(self: *PtyWebSocket, data: []const u8) !void {
        // Check if it's a control message (JSON)
        if (data.len > 0 and data[0] == '{') {
            // Try to parse as JSON control message
            self.handleControlMessage(data) catch {
                // Not a valid control message, treat as regular input
                try self.session.write(data);
            };
        } else {
            // Regular input - write to PTY
            try self.session.write(data);
        }
    }

    /// Handle control messages (resize, etc.)
    fn handleControlMessage(self: *PtyWebSocket, data: []const u8) !void {
        _ = self;
        // Simple JSON parsing for control messages
        // Format: {"type":"resize","cols":80,"rows":24}

        // Check for resize message
        if (std.mem.indexOf(u8, data, "\"type\":\"resize\"") != null) {
            // Extract cols and rows
            // For now, we'll just log it since terminal resize requires
            // additional system calls (TIOCSWINSZ)
            log.info("Resize request received (not yet implemented): {s}", .{data});

            // TODO: Implement terminal resize using ioctl TIOCSWINSZ
            // This requires:
            // 1. Parse cols and rows from JSON
            // 2. Create winsize struct
            // 3. Call ioctl(master_fd, TIOCSWINSZ, &winsize)
        }
    }

    /// Called when WebSocket connection closes
    pub fn close(self: *PtyWebSocket) void {
        log.info("WebSocket closing for PTY session: {s}", .{self.session.id});

        // Signal reader thread to stop
        self.running.store(false, .release);

        // Wait for reader thread to finish
        if (self.reader_thread) |thread| {
            thread.join();
        }

        log.info("WebSocket closed for PTY session: {s}", .{self.session.id});
    }

    /// Background thread that reads PTY output and sends to WebSocket
    fn outputReaderThread(self: *PtyWebSocket) void {
        log.info("Output reader thread started for PTY session: {s}", .{self.session.id});

        while (self.running.load(.acquire)) {
            // Check if session is still running
            self.session.checkStatus();
            if (!self.session.running) {
                log.info("PTY session ended: {s}", .{self.session.id});
                // Send a final message and close
                self.conn.write("PTY session ended\r\n") catch {};
                break;
            }

            // Try to read output from PTY
            if (self.session.read()) |maybe_data| {
                if (maybe_data) |data| {
                    // Send to WebSocket
                    self.conn.write(data) catch |err| {
                        log.err("Failed to write to WebSocket: {}", .{err});
                        break;
                    };
                }
            } else |err| {
                log.err("Failed to read from PTY: {}", .{err});
                break;
            }

            // Small sleep to prevent busy loop
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }

        log.info("Output reader thread exiting for PTY session: {s}", .{self.session.id});
    }
};

test "PtyWebSocket basic" {
    // Basic compile test - WebSocket handlers require actual connections to test
    const T = PtyWebSocket;
    _ = T;
}

test "UpgradeContext structure" {
    // Test that UpgradeContext has the expected structure
    const T = UpgradeContext;
    _ = T;

    // The struct should have a session field
    const info = @typeInfo(UpgradeContext);
    try std.testing.expect(info == .@"struct");
}

test "PtyWebSocket struct fields" {
    // Test struct layout
    const info = @typeInfo(PtyWebSocket);
    try std.testing.expect(info == .@"struct");

    // Should have fields: conn, session, running, reader_thread
    const fields = info.@"struct".fields;
    try std.testing.expect(fields.len == 4);
}

test "control message detection" {
    // Test logic for detecting JSON control messages
    const json_msg = "{\"type\":\"resize\",\"cols\":80,\"rows\":24}";
    const regular_msg = "ls -la\n";

    // JSON messages start with '{'
    try std.testing.expect(json_msg.len > 0 and json_msg[0] == '{');
    try std.testing.expect(regular_msg.len > 0 and regular_msg[0] != '{');
}

test "resize message detection" {
    const resize_msg = "{\"type\":\"resize\",\"cols\":80,\"rows\":24}";
    const other_msg = "{\"type\":\"ping\"}";

    // Check for resize type
    try std.testing.expect(std.mem.indexOf(u8, resize_msg, "\"type\":\"resize\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, other_msg, "\"type\":\"resize\"") == null);
}
