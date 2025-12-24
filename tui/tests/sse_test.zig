const std = @import("std");
const sse = @import("../client/sse.zig");
const protocol = @import("../client/protocol.zig");
const testing = std.testing;

test "parseSseLine with valid data line" {
    const line = "data: {\"type\":\"text\",\"data\":\"hello\"}";
    const result = sse.parseSseLine(line);

    try testing.expect(result != null);
    try testing.expectEqualStrings("{\"type\":\"text\",\"data\":\"hello\"}", result.?);
}

test "parseSseLine with whitespace" {
    const line = "  data: {\"type\":\"done\"}  ";
    const result = sse.parseSseLine(line);

    try testing.expect(result != null);
    try testing.expectEqualStrings("{\"type\":\"done\"}", result.?);
}

test "parseSseLine with non-data line" {
    const line = "event: message";
    const result = sse.parseSseLine(line);

    try testing.expect(result == null);
}

test "parseSseLine with empty line" {
    const line = "";
    const result = sse.parseSseLine(line);

    try testing.expect(result == null);
}

test "parseSseLine with CRLF" {
    const line = "data: {\"type\":\"done\"}\r\n";
    const result = sse.parseSseLine(line);

    try testing.expect(result != null);
    try testing.expectEqualStrings("{\"type\":\"done\"}", result.?);
}

test "EventQueue push and pop" {
    const allocator = testing.allocator;
    var queue = sse.EventQueue.init(allocator);
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
    var queue = sse.EventQueue.init(allocator);
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

test "EventQueue thread safety - concurrent push and pop" {
    const allocator = testing.allocator;
    var queue = sse.EventQueue.init(allocator);
    defer queue.deinit();

    const Context = struct {
        q: *sse.EventQueue,

        fn pusher(self: *@This()) void {
            var i: usize = 0;
            while (i < 100) : (i += 1) {
                self.q.push(protocol.StreamEvent{ .done = {} });
                std.time.sleep(1_000_000); // 1ms
            }
        }

        fn popper(self: *@This()) void {
            var count: usize = 0;
            while (count < 100) {
                if (self.q.pop()) |_| {
                    count += 1;
                }
                std.time.sleep(1_000_000); // 1ms
            }
        }
    };

    var ctx = Context{ .q = &queue };

    const t1 = try std.Thread.spawn(.{}, Context.pusher, .{&ctx});
    const t2 = try std.Thread.spawn(.{}, Context.popper, .{&ctx});

    t1.join();
    t2.join();

    // After both threads finish, queue should be empty
    try testing.expect(queue.isEmpty());
}

test "EventQueue close and isClosed" {
    const allocator = testing.allocator;
    var queue = sse.EventQueue.init(allocator);
    defer queue.deinit();

    try testing.expect(!queue.isClosed());

    queue.close();
    try testing.expect(queue.isClosed());
}

test "SseClient init and deinit" {
    const allocator = testing.allocator;
    var client = sse.SseClient.init(allocator, "http://localhost:4000");
    defer client.deinit();

    // Just verify it initializes without error
    try testing.expect(client.buffer.items.len == 0);
}
