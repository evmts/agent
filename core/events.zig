const std = @import("std");
const models = @import("models/mod.zig");

/// Event types
pub const EventType = enum {
    // Session events
    session_created,
    session_updated,
    session_deleted,
    session_archived,

    // Message events
    message_created,
    message_updated,
    message_completed,
    message_failed,

    // Part events
    part_created,
    part_updated,
    part_completed,

    // Snapshot events
    snapshot_created,
    snapshot_restored,

    // Tool events
    tool_started,
    tool_completed,
    tool_failed,

    // Agent events
    agent_started,
    agent_stopped,
    agent_error,

    pub fn toString(self: EventType) []const u8 {
        return @tagName(self);
    }
};

/// Event payload
pub const EventPayload = union(enum) {
    session: SessionEventData,
    message: MessageEventData,
    part: PartEventData,
    snapshot: SnapshotEventData,
    tool: ToolEventData,
    agent: AgentEventData,
    empty: void,
};

pub const SessionEventData = struct {
    session_id: []const u8,
    title: ?[]const u8 = null,
    directory: ?[]const u8 = null,
};

pub const MessageEventData = struct {
    session_id: []const u8,
    message_id: []const u8,
    role: ?models.MessageRole = null,
    status: ?models.MessageStatus = null,
};

pub const PartEventData = struct {
    session_id: []const u8,
    message_id: []const u8,
    part_id: []const u8,
    part_type: ?models.PartType = null,
};

pub const SnapshotEventData = struct {
    session_id: []const u8,
    change_id: []const u8,
    description: ?[]const u8 = null,
};

pub const ToolEventData = struct {
    session_id: []const u8,
    tool_name: []const u8,
    tool_id: ?[]const u8 = null,
    output: ?[]const u8 = null,
    error_msg: ?[]const u8 = null,
};

pub const AgentEventData = struct {
    session_id: []const u8,
    agent_name: []const u8,
    error_msg: ?[]const u8 = null,
};

/// Event structure
pub const Event = struct {
    event_type: EventType,
    timestamp: i64,
    payload: EventPayload,

    pub fn init(event_type: EventType, payload: EventPayload) Event {
        return .{
            .event_type = event_type,
            .timestamp = std.time.milliTimestamp(),
            .payload = payload,
        };
    }
};

/// Event handler function type
pub const EventHandler = *const fn (Event, ?*anyopaque) void;

/// Subscriber entry
const Subscriber = struct {
    handler: EventHandler,
    context: ?*anyopaque,
};

/// Event bus interface
pub const EventBus = struct {
    allocator: std.mem.Allocator,
    subscribers: std.AutoHashMap(EventType, std.ArrayList(Subscriber)),
    global_subscribers: std.ArrayList(Subscriber),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) EventBus {
        return .{
            .allocator = allocator,
            .subscribers = std.AutoHashMap(EventType, std.ArrayList(Subscriber)).init(allocator),
            .global_subscribers = .{},
            .mutex = .{},
        };
    }

    pub fn deinit(self: *EventBus) void {
        var iter = self.subscribers.valueIterator();
        while (iter.next()) |list| {
            list.deinit(self.allocator);
        }
        self.subscribers.deinit();
        self.global_subscribers.deinit(self.allocator);
    }

    /// Subscribe to a specific event type
    pub fn subscribe(self: *EventBus, event_type: EventType, handler: EventHandler, context: ?*anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.subscribers.getPtr(event_type);
        if (entry) |list| {
            try list.append(self.allocator, .{ .handler = handler, .context = context });
        } else {
            var list: std.ArrayList(Subscriber) = .{};
            try list.append(self.allocator, .{ .handler = handler, .context = context });
            try self.subscribers.put(event_type, list);
        }
    }

    /// Subscribe to all events
    pub fn subscribeAll(self: *EventBus, handler: EventHandler, context: ?*anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.global_subscribers.append(self.allocator, .{ .handler = handler, .context = context });
    }

    /// Publish an event
    pub fn publish(self: *EventBus, event: Event) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Notify type-specific subscribers
        if (self.subscribers.get(event.event_type)) |list| {
            for (list.items) |sub| {
                sub.handler(event, sub.context);
            }
        }

        // Notify global subscribers
        for (self.global_subscribers.items) |sub| {
            sub.handler(event, sub.context);
        }
    }

    /// Emit a convenience method
    pub fn emit(self: *EventBus, event_type: EventType, payload: EventPayload) void {
        self.publish(Event.init(event_type, payload));
    }
};

/// Null event bus (no-op implementation)
pub const NullEventBus = struct {
    pub fn subscribe(_: *NullEventBus, _: EventType, _: EventHandler, _: ?*anyopaque) !void {}
    pub fn subscribeAll(_: *NullEventBus, _: EventHandler, _: ?*anyopaque) !void {}
    pub fn publish(_: *NullEventBus, _: Event) void {}
    pub fn emit(_: *NullEventBus, _: EventType, _: EventPayload) void {}
};

/// Global event bus instance
var global_event_bus: ?*EventBus = null;
var global_mutex: std.Thread.Mutex = .{};

/// Get the global event bus
pub fn getEventBus() ?*EventBus {
    global_mutex.lock();
    defer global_mutex.unlock();
    return global_event_bus;
}

/// Set the global event bus
pub fn setEventBus(bus: ?*EventBus) void {
    global_mutex.lock();
    defer global_mutex.unlock();
    global_event_bus = bus;
}

test "EventBus subscribe and publish" {
    const allocator = std.testing.allocator;
    var bus = EventBus.init(allocator);
    defer bus.deinit();

    var received = false;
    const handler = struct {
        fn handle(_: Event, ctx: ?*anyopaque) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.handle;

    try bus.subscribe(.session_created, handler, &received);

    bus.emit(.session_created, .{ .session = .{ .session_id = "test" } });

    try std.testing.expect(received);
}
