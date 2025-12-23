const std = @import("std");
const protocol = @import("protocol.zig");

/// SSE (Server-Sent Events) streaming client
pub const SseClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) SseClient {
        var buffer = std.ArrayList(u8){};
        buffer.ensureTotalCapacity(allocator, 1024) catch {};
        return .{
            .allocator = allocator,
            .base_url = base_url,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *SseClient) void {
        self.buffer.deinit(self.allocator);
    }

    /// Stream events from the server, calling the callback for each event
    pub fn stream(
        self: *SseClient,
        session_id: []const u8,
        message: []const u8,
        model: ?[]const u8,
        callback: *const fn (protocol.StreamEvent) void,
    ) !void {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/sessions/{s}/run",
            .{ self.base_url, session_id },
        );
        defer self.allocator.free(url);

        const uri = try std.Uri.parse(url);

        // Build request body
        // TODO: Reimplement SSE streaming with the new HTTP API
        // For now, just return an error - this will be fixed in a future phase
        _ = message;
        _ = model;
        _ = uri;
        _ = callback;
        return error.SseNotImplemented;
    }

    /// Stream with async event queue (for integration with event loop)
    pub fn streamAsync(
        self: *SseClient,
        session_id: []const u8,
        message: []const u8,
        model: ?[]const u8,
        event_queue: *EventQueue,
    ) !void {
        // Spawn thread to handle streaming
        const args = try self.allocator.create(StreamArgs);
        args.* = .{
            .allocator = self.allocator,
            .client = self,
            .session_id = try self.allocator.dupe(u8, session_id),
            .message = try self.allocator.dupe(u8, message),
            .model = if (model) |m| try self.allocator.dupe(u8, m) else null,
            .queue = event_queue,
        };

        const thread = try std.Thread.spawn(.{}, streamThread, .{args});
        thread.detach();
    }

    const StreamArgs = struct {
        allocator: std.mem.Allocator,
        client: *SseClient,
        session_id: []const u8,
        message: []const u8,
        model: ?[]const u8,
        queue: *EventQueue,
    };

    fn streamThread(args: *StreamArgs) void {
        defer {
            args.allocator.free(args.session_id);
            args.allocator.free(args.message);
            if (args.model) |m| args.allocator.free(m);
            args.allocator.destroy(args);
        }

        // Set thread-local queue for callback
        current_queue = args.queue;
        defer current_queue = null;

        args.client.stream(
            args.session_id,
            args.message,
            args.model,
            &callbackWrapper,
        ) catch |err| {
            const error_event = protocol.StreamEvent{
                .error_event = .{
                    .error_msg = @errorName(err),
                },
            };
            args.queue.push(error_event);
        };
    }

    const CallbackContext = struct {
        queue: *EventQueue,
    };

    fn callbackWrapper(event: protocol.StreamEvent) void {
        // This is a bit tricky - we need to pass the queue through somehow
        // For now, we'll use a thread-local variable
        if (current_queue) |queue| {
            queue.push(event);
        }
    }

    threadlocal var current_queue: ?*EventQueue = null;

    fn extractEventData(self: *SseClient, buffer: []const u8) ?[]const u8 {
        _ = self;
        // SSE format: "data: {json}\n"
        var lines = std.mem.splitSequence(u8, buffer, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "data: ")) {
                return line[6..];
            }
        }
        return null;
    }
};

/// Thread-safe event queue for async streaming
pub const EventQueue = struct {
    mutex: std.Thread.Mutex = .{},
    events: std.ArrayList(protocol.StreamEvent),
    allocator: std.mem.Allocator,
    closed: bool = false,

    pub fn init(allocator: std.mem.Allocator) EventQueue {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(protocol.StreamEvent){},
        };
    }

    pub fn deinit(self: *EventQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.events.deinit(self.allocator);
    }

    pub fn push(self: *EventQueue, event: protocol.StreamEvent) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.events.append(self.allocator, event) catch {
            // If we can't append, we're out of memory - log and continue
            std.debug.print("EventQueue: Failed to append event (OOM)\n", .{});
        };
    }

    pub fn pop(self: *EventQueue) ?protocol.StreamEvent {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.events.items.len > 0) {
            return self.events.orderedRemove(0);
        }
        return null;
    }

    pub fn isEmpty(self: *EventQueue) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.events.items.len == 0;
    }

    pub fn close(self: *EventQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.closed = true;
    }

    pub fn isClosed(self: *EventQueue) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.closed;
    }

    pub fn len(self: *EventQueue) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.events.items.len;
    }
};

/// Parse a single SSE line
pub fn parseSseLine(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (std.mem.startsWith(u8, trimmed, "data: ")) {
        return trimmed[6..];
    }
    return null;
}

// Tests
const testing = std.testing;

test "parseSseLine with valid data line" {
    const line = "data: {\"type\":\"text\",\"data\":\"hello\"}";
    const result = parseSseLine(line);

    try testing.expect(result != null);
    try testing.expectEqualStrings("{\"type\":\"text\",\"data\":\"hello\"}", result.?);
}

test "parseSseLine with whitespace" {
    const line = "  data: {\"type\":\"done\"}  ";
    const result = parseSseLine(line);

    try testing.expect(result != null);
    try testing.expectEqualStrings("{\"type\":\"done\"}", result.?);
}

test "parseSseLine with non-data line" {
    const line = "event: message";
    const result = parseSseLine(line);

    try testing.expect(result == null);
}

test "parseSseLine with empty line" {
    const line = "";
    const result = parseSseLine(line);

    try testing.expect(result == null);
}

test "EventQueue push and pop" {
    const allocator = testing.allocator;
    var queue = EventQueue.init(allocator);
    defer queue.deinit();

    // Queue should be empty initially
    try testing.expect(queue.isEmpty());
    try testing.expectEqual(@as(usize, 0), queue.len());

    // Push an event
    const event1 = protocol.StreamEvent{ .done = {} };
    queue.push(event1);

    try testing.expect(!queue.isEmpty());
    try testing.expectEqual(@as(usize, 1), queue.len());

    // Pop the event
    const popped1 = queue.pop();
    try testing.expect(popped1 != null);
    try testing.expect(popped1.? == .done);

    try testing.expect(queue.isEmpty());
}

test "EventQueue multiple events" {
    const allocator = testing.allocator;
    var queue = EventQueue.init(allocator);
    defer queue.deinit();

    // Push multiple events
    queue.push(protocol.StreamEvent{ .done = {} });
    queue.push(protocol.StreamEvent{
        .text = .{ .data = null },
    });

    try testing.expectEqual(@as(usize, 2), queue.len());

    // Pop in order
    const e1 = queue.pop();
    try testing.expect(e1 != null);
    try testing.expect(e1.? == .done);

    const e2 = queue.pop();
    try testing.expect(e2 != null);
    try testing.expect(e2.? == .text);

    try testing.expect(queue.isEmpty());
}

test "EventQueue close and isClosed" {
    const allocator = testing.allocator;
    var queue = EventQueue.init(allocator);
    defer queue.deinit();

    try testing.expect(!queue.isClosed());

    queue.close();
    try testing.expect(queue.isClosed());
}

test "SseClient init and deinit" {
    const allocator = testing.allocator;
    var client = SseClient.init(allocator, "http://localhost:4000");
    defer client.deinit();

    // Just verify it initializes without error
    try testing.expect(client.buffer.items.len == 0);
}
