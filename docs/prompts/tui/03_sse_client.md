# 03: SSE Client & Protocol

## Goal

Implement an SSE (Server-Sent Events) client in Zig for streaming responses from the Plue API server.

## Context

- The Plue server streams responses via SSE at `POST /api/sessions/:sessionId/run`
- Events are sent as `data: {json}\n\n` lines
- Reference: `/Users/williamcory/plue/tui/src/client.ts` (TypeScript implementation)
- Reference: `/Users/williamcory/plue/server/src/routes/agent.zig` (server-side)

## Event Types

The server sends these event types:

```zig
pub const StreamEvent = union(enum) {
    text: TextEvent,
    tool_call: ToolCallEvent,
    tool_result: ToolResultEvent,
    usage: UsageEvent,
    message_completed: void,
    error_event: ErrorEvent,
    done: void,
};

pub const TextEvent = struct {
    data: ?[]const u8,
};

pub const ToolCallEvent = struct {
    tool_name: []const u8,
    tool_id: []const u8,
    args: []const u8, // JSON string
};

pub const ToolResultEvent = struct {
    tool_id: []const u8,
    output: []const u8,
    duration_ms: ?u64 = null,
};

pub const UsageEvent = struct {
    input_tokens: u64,
    output_tokens: u64,
    cached_tokens: u64 = 0,
};

pub const ErrorEvent = struct {
    message: []const u8,
};
```

## Tasks

### 1. Create Protocol Types (src/client/protocol.zig)

```zig
const std = @import("std");

pub const StreamEvent = union(enum) {
    text: TextEvent,
    tool_call: ToolCallEvent,
    tool_result: ToolResultEvent,
    usage: UsageEvent,
    message_completed,
    error_event: ErrorEvent,
    done,

    pub fn parse(allocator: std.mem.Allocator, json_str: []const u8) !StreamEvent {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json_str,
            .{},
        );
        defer parsed.deinit();

        const obj = parsed.value.object;
        const event_type = obj.get("type") orelse return error.MissingType;
        const type_str = event_type.string;

        if (std.mem.eql(u8, type_str, "text")) {
            const data = if (obj.get("data")) |d| d.string else null;
            return .{ .text = .{ .data = if (data) |d| try allocator.dupe(u8, d) else null } };
        } else if (std.mem.eql(u8, type_str, "tool.call")) {
            return .{ .tool_call = .{
                .tool_name = try allocator.dupe(u8, obj.get("tool_name").?.string),
                .tool_id = try allocator.dupe(u8, obj.get("tool_id").?.string),
                .args = try allocator.dupe(u8, obj.get("args").?.string),
            } };
        } else if (std.mem.eql(u8, type_str, "tool.result")) {
            return .{ .tool_result = .{
                .tool_id = try allocator.dupe(u8, obj.get("tool_id").?.string),
                .output = try allocator.dupe(u8, obj.get("output").?.string),
                .duration_ms = if (obj.get("duration_ms")) |d| @intCast(d.integer) else null,
            } };
        } else if (std.mem.eql(u8, type_str, "usage")) {
            return .{ .usage = .{
                .input_tokens = @intCast(obj.get("input_tokens").?.integer),
                .output_tokens = @intCast(obj.get("output_tokens").?.integer),
                .cached_tokens = if (obj.get("cached_tokens")) |c| @intCast(c.integer) else 0,
            } };
        } else if (std.mem.eql(u8, type_str, "message.completed")) {
            return .message_completed;
        } else if (std.mem.eql(u8, type_str, "error")) {
            return .{ .error_event = .{
                .message = try allocator.dupe(u8, obj.get("message").?.string),
            } };
        } else if (std.mem.eql(u8, type_str, "done")) {
            return .done;
        }

        return error.UnknownEventType;
    }
};

pub const TextEvent = struct {
    data: ?[]const u8,
};

pub const ToolCallEvent = struct {
    tool_name: []const u8,
    tool_id: []const u8,
    args: []const u8,
};

pub const ToolResultEvent = struct {
    tool_id: []const u8,
    output: []const u8,
    duration_ms: ?u64,
};

pub const UsageEvent = struct {
    input_tokens: u64,
    output_tokens: u64,
    cached_tokens: u64,
};

pub const ErrorEvent = struct {
    message: []const u8,
};

// Request types
pub const SendMessageRequest = struct {
    message: []const u8,
    model: ?[]const u8 = null,
    agent_name: ?[]const u8 = null,

    pub fn toJson(self: SendMessageRequest, allocator: std.mem.Allocator) ![]const u8 {
        var obj = std.json.ObjectMap.init(allocator);
        try obj.put("message", .{ .string = self.message });
        if (self.model) |m| try obj.put("model", .{ .string = m });
        if (self.agent_name) |a| try obj.put("agent_name", .{ .string = a });

        var buf = std.ArrayList(u8).init(allocator);
        try std.json.stringify(.{ .object = obj }, .{}, buf.writer());
        return buf.toOwnedSlice();
    }
};

pub const Session = struct {
    id: []const u8,
    title: ?[]const u8,
    model: []const u8,
    reasoning_effort: []const u8,
    directory: []const u8,
    created_at: i64,

    pub fn parse(allocator: std.mem.Allocator, json_str: []const u8) !Session {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json_str,
            .{},
        );
        defer parsed.deinit();

        const obj = parsed.value.object;
        return .{
            .id = try allocator.dupe(u8, obj.get("id").?.string),
            .title = if (obj.get("title")) |t| try allocator.dupe(u8, t.string) else null,
            .model = try allocator.dupe(u8, obj.get("model").?.string),
            .reasoning_effort = try allocator.dupe(u8, obj.get("reasoning_effort").?.string),
            .directory = try allocator.dupe(u8, obj.get("directory").?.string),
            .created_at = obj.get("created_at").?.integer,
        };
    }
};
```

### 2. Create HTTP Client (src/client/http.zig)

```zig
const std = @import("std");

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) HttpClient {
        return .{
            .allocator = allocator,
            .base_url = base_url,
        };
    }

    pub fn get(self: *HttpClient, path: []const u8) !Response {
        return self.request(.GET, path, null);
    }

    pub fn post(self: *HttpClient, path: []const u8, body: ?[]const u8) !Response {
        return self.request(.POST, path, body);
    }

    pub fn patch(self: *HttpClient, path: []const u8, body: ?[]const u8) !Response {
        return self.request(.PATCH, path, body);
    }

    fn request(self: *HttpClient, method: std.http.Method, path: []const u8, body: ?[]const u8) !Response {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, path });
        defer self.allocator.free(url);

        const uri = try std.Uri.parse(url);

        var headers = std.http.Client.Request.Headers{};
        headers.content_type = .{ .override = "application/json" };

        var req = try client.open(method, uri, headers, .{});
        defer req.deinit();

        if (body) |b| {
            req.transfer_encoding = .{ .content_length = b.len };
        }

        try req.send();

        if (body) |b| {
            try req.writer().writeAll(b);
            try req.finish();
        }

        try req.wait();

        const response_body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);

        return .{
            .status = req.status,
            .body = response_body,
            .allocator = self.allocator,
        };
    }

    pub const Response = struct {
        status: std.http.Status,
        body: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Response) void {
            self.allocator.free(self.body);
        }

        pub fn isSuccess(self: Response) bool {
            return @intFromEnum(self.status) >= 200 and @intFromEnum(self.status) < 300;
        }
    };
};
```

### 3. Create SSE Client (src/client/sse.zig)

```zig
const std = @import("std");
const protocol = @import("protocol.zig");

pub const SseClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) SseClient {
        return .{
            .allocator = allocator,
            .base_url = base_url,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *SseClient) void {
        self.buffer.deinit();
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
        const req_body = protocol.SendMessageRequest{
            .message = message,
            .model = model,
        };
        const body = try req_body.toJson(self.allocator);
        defer self.allocator.free(body);

        var headers = std.http.Client.Request.Headers{};
        headers.content_type = .{ .override = "application/json" };
        headers.accept_header = .{ .override = "text/event-stream" };

        var req = try client.open(.POST, uri, headers, .{});
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = body.len };

        try req.send();
        try req.writer().writeAll(body);
        try req.finish();
        try req.wait();

        // Read SSE stream
        self.buffer.clearRetainingCapacity();

        while (true) {
            var line_buf: [4096]u8 = undefined;
            const line = req.reader().readUntilDelimiter(&line_buf, '\n') catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };

            if (line.len == 0) {
                // Empty line = end of event, process buffer
                if (self.buffer.items.len > 0) {
                    const event_data = self.extractEventData(self.buffer.items);
                    if (event_data) |data| {
                        const event = protocol.StreamEvent.parse(self.allocator, data) catch continue;
                        callback(event);

                        // Check for terminal events
                        switch (event) {
                            .done, .message_completed => break,
                            .error_event => break,
                            else => {},
                        }
                    }
                    self.buffer.clearRetainingCapacity();
                }
            } else {
                try self.buffer.appendSlice(line);
                try self.buffer.append('\n');
            }
        }
    }

    /// Stream with async event queue (for integration with vxfw event loop)
    pub fn streamAsync(
        self: *SseClient,
        session_id: []const u8,
        message: []const u8,
        model: ?[]const u8,
        event_queue: *EventQueue,
    ) !void {
        // Spawn thread to handle streaming
        const args = StreamArgs{
            .client = self,
            .session_id = try self.allocator.dupe(u8, session_id),
            .message = try self.allocator.dupe(u8, message),
            .model = if (model) |m| try self.allocator.dupe(u8, m) else null,
            .queue = event_queue,
        };

        _ = try std.Thread.spawn(.{}, streamThread, .{args});
    }

    const StreamArgs = struct {
        client: *SseClient,
        session_id: []const u8,
        message: []const u8,
        model: ?[]const u8,
        queue: *EventQueue,
    };

    fn streamThread(args: StreamArgs) void {
        args.client.stream(
            args.session_id,
            args.message,
            args.model,
            struct {
                fn callback(event: protocol.StreamEvent) void {
                    args.queue.push(event);
                }
            }.callback,
        ) catch |err| {
            args.queue.push(.{ .error_event = .{
                .message = @errorName(err),
            } });
        };

        // Cleanup
        args.client.allocator.free(args.session_id);
        args.client.allocator.free(args.message);
        if (args.model) |m| args.client.allocator.free(m);
    }

    fn extractEventData(self: *SseClient, buffer: []const u8) ?[]const u8 {
        _ = self;
        // SSE format: "data: {json}\n"
        var lines = std.mem.split(u8, buffer, "\n");
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
    closed: bool = false,

    pub fn init(allocator: std.mem.Allocator) EventQueue {
        return .{
            .events = std.ArrayList(protocol.StreamEvent).init(allocator),
        };
    }

    pub fn deinit(self: *EventQueue) void {
        self.events.deinit();
    }

    pub fn push(self: *EventQueue, event: protocol.StreamEvent) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.events.append(event) catch {};
    }

    pub fn pop(self: *EventQueue) ?protocol.StreamEvent {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.events.items.len > 0) {
            return self.events.orderedRemove(0);
        }
        return null;
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
};
```

### 4. Create API Client Facade (src/client/client.zig)

```zig
const std = @import("std");
const http = @import("http.zig");
const sse = @import("sse.zig");
const protocol = @import("protocol.zig");

pub const PlueClient = struct {
    allocator: std.mem.Allocator,
    http_client: http.HttpClient,
    sse_client: sse.SseClient,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) PlueClient {
        return .{
            .allocator = allocator,
            .http_client = http.HttpClient.init(allocator, base_url),
            .sse_client = sse.SseClient.init(allocator, base_url),
        };
    }

    pub fn deinit(self: *PlueClient) void {
        self.sse_client.deinit();
    }

    // Health check
    pub fn healthCheck(self: *PlueClient) !bool {
        var response = try self.http_client.get("/health");
        defer response.deinit();
        return response.isSuccess();
    }

    // Session management
    pub fn createSession(self: *PlueClient, directory: []const u8, model: []const u8) !protocol.Session {
        const body = try std.fmt.allocPrint(
            self.allocator,
            "{{\"directory\":\"{s}\",\"model\":\"{s}\"}}",
            .{ directory, model },
        );
        defer self.allocator.free(body);

        var response = try self.http_client.post("/api/sessions", body);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.CreateSessionFailed;
        }

        return protocol.Session.parse(self.allocator, response.body);
    }

    pub fn listSessions(self: *PlueClient) ![]protocol.Session {
        var response = try self.http_client.get("/api/sessions");
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.ListSessionsFailed;
        }

        // Parse JSON array
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response.body,
            .{},
        );
        defer parsed.deinit();

        const arr = parsed.value.array;
        var sessions = try self.allocator.alloc(protocol.Session, arr.items.len);

        for (arr.items, 0..) |item, i| {
            var buf = std.ArrayList(u8).init(self.allocator);
            defer buf.deinit();
            try std.json.stringify(item, .{}, buf.writer());
            sessions[i] = try protocol.Session.parse(self.allocator, buf.items);
        }

        return sessions;
    }

    pub fn getSession(self: *PlueClient, id: []const u8) !protocol.Session {
        const path = try std.fmt.allocPrint(self.allocator, "/api/sessions/{s}", .{id});
        defer self.allocator.free(path);

        var response = try self.http_client.get(path);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.GetSessionFailed;
        }

        return protocol.Session.parse(self.allocator, response.body);
    }

    pub fn updateSession(
        self: *PlueClient,
        id: []const u8,
        model: ?[]const u8,
        reasoning_effort: ?[]const u8,
    ) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/api/sessions/{s}", .{id});
        defer self.allocator.free(path);

        var obj = std.json.ObjectMap.init(self.allocator);
        defer obj.deinit();
        if (model) |m| try obj.put("model", .{ .string = m });
        if (reasoning_effort) |r| try obj.put("reasoning_effort", .{ .string = r });

        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        try std.json.stringify(.{ .object = obj }, .{}, buf.writer());

        var response = try self.http_client.patch(path, buf.items);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.UpdateSessionFailed;
        }
    }

    // Streaming message
    pub fn sendMessage(
        self: *PlueClient,
        session_id: []const u8,
        message: []const u8,
        model: ?[]const u8,
        callback: *const fn (protocol.StreamEvent) void,
    ) !void {
        try self.sse_client.stream(session_id, message, model, callback);
    }

    pub fn sendMessageAsync(
        self: *PlueClient,
        session_id: []const u8,
        message: []const u8,
        model: ?[]const u8,
        queue: *sse.EventQueue,
    ) !void {
        try self.sse_client.streamAsync(session_id, message, model, queue);
    }

    // Undo
    pub fn undo(self: *PlueClient, session_id: []const u8, turns: u32) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/api/sessions/{s}/undo", .{session_id});
        defer self.allocator.free(path);

        const body = try std.fmt.allocPrint(self.allocator, "{{\"turns\":{d}}}", .{turns});
        defer self.allocator.free(body);

        var response = try self.http_client.post(path, body);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.UndoFailed;
        }
    }

    // Abort
    pub fn abort(self: *PlueClient, session_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/api/sessions/{s}/abort", .{session_id});
        defer self.allocator.free(path);

        var response = try self.http_client.post(path, null);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.AbortFailed;
        }
    }
};
```

## Integration with App

Update `src/app.zig` to use the client:

```zig
const client = @import("client/client.zig");
const sse = @import("client/sse.zig");

pub const App = struct {
    state: *AppState,
    plue_client: client.PlueClient,
    event_queue: sse.EventQueue,

    pub fn init(allocator: std.mem.Allocator, state: *AppState) App {
        return .{
            .state = state,
            .plue_client = client.PlueClient.init(allocator, state.api_url),
            .event_queue = sse.EventQueue.init(allocator),
        };
    }

    // In handleEvent, check for queued events on tick
    fn handleEvent(...) {
        switch (event) {
            .tick => {
                // Process queued SSE events
                while (self.event_queue.pop()) |stream_event| {
                    try self.handleStreamEvent(stream_event);
                }
                if (self.state.is_streaming) {
                    ctx.consumeAndRedraw();
                }
            },
            // ...
        }
    }

    fn handleStreamEvent(self: *App, event: protocol.StreamEvent) !void {
        switch (event) {
            .text => |t| {
                if (t.data) |data| {
                    try self.state.streaming_text.appendSlice(data);
                }
            },
            .tool_call => |tc| {
                try self.state.pending_tool_calls.put(tc.tool_id, .{
                    .id = tc.tool_id,
                    .name = tc.tool_name,
                    .args = tc.args,
                    .status = .running,
                });
            },
            .tool_result => |tr| {
                if (self.state.pending_tool_calls.getPtr(tr.tool_id)) |tc| {
                    tc.result = tr.output;
                    tc.duration_ms = tr.duration_ms;
                    tc.status = .completed;
                }
            },
            .usage => |u| {
                self.state.token_usage = .{
                    .input = u.input_tokens,
                    .output = u.output_tokens,
                    .cached = u.cached_tokens,
                };
            },
            .message_completed, .done => {
                self.state.is_streaming = false;
                // Move streaming text to messages
                if (self.state.streaming_text.items.len > 0) {
                    try self.state.addMessage(.assistant, self.state.streaming_text.items);
                    self.state.streaming_text.clearRetainingCapacity();
                }
            },
            .error_event => |e| {
                self.state.is_streaming = false;
                self.state.error_message = e.message;
            },
        }
    }

    fn submitMessage(self: *App, content: []const u8) !void {
        // ... existing code ...

        // Send message async
        if (self.state.session) |session| {
            try self.plue_client.sendMessageAsync(
                session.id,
                content,
                null,
                &self.event_queue,
            );
        }
    }
};
```

## Acceptance Criteria

- [ ] Protocol types properly parse all event types
- [ ] HTTP client handles GET, POST, PATCH
- [ ] SSE client streams events correctly
- [ ] Event queue allows async processing
- [ ] PlueClient facade provides clean API
- [ ] Integration with App event loop works
- [ ] Error handling for network failures

## Files to Create

1. `tui-zig/src/client/protocol.zig`
2. `tui-zig/src/client/http.zig`
3. `tui-zig/src/client/sse.zig`
4. `tui-zig/src/client/client.zig`

## Next

Proceed to `04_state_management.md` for advanced state management.
