const std = @import("std");
const types = @import("types.zig");

/// Simple Anthropic API client using direct HTTP
pub const AnthropicClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    base_url: []const u8 = "https://api.anthropic.com",

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) AnthropicClient {
        return .{
            .allocator = allocator,
            .api_key = api_key,
        };
    }

    /// Send a messages request to Anthropic API
    pub fn sendMessages(
        self: *const AnthropicClient,
        model_id: []const u8,
        messages: []const Message,
        system: ?[]const u8,
        tools: ?[]const Tool,
        temperature: f32,
        max_tokens: u32,
    ) !Response {
        // Build request JSON
        var json_buf = std.ArrayList(u8){};
        defer json_buf.deinit(self.allocator);

        var writer = json_buf.writer(self.allocator);
        try writer.writeAll("{");
        try writer.print("\"model\":\"{s}\",", .{model_id});
        try writer.print("\"max_tokens\":{d},", .{max_tokens});
        try writer.print("\"temperature\":{d},", .{temperature});

        // System prompt
        if (system) |sys| {
            try writer.print("\"system\":\"{s}\",", .{escapeJson(self.allocator, sys) catch sys});
        }

        // Messages
        try writer.writeAll("\"messages\":[");
        for (messages, 0..) |msg, i| {
            if (i > 0) try writer.writeAll(",");
            try writeMessage(writer, msg, self.allocator);
        }
        try writer.writeAll("]");

        // Tools
        if (tools) |t| {
            if (t.len > 0) {
                try writer.writeAll(",\"tools\":[");
                for (t, 0..) |tool, i| {
                    if (i > 0) try writer.writeAll(",");
                    try writeTool(writer, tool);
                }
                try writer.writeAll("]");
            }
        }

        try writer.writeAll("}");

        // Make HTTP request using fetch API (Zig 0.15+)
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/messages", .{self.base_url});
        defer self.allocator.free(url);

        // Use fixed buffer for response
        var response_buf: [1024 * 1024]u8 = undefined; // 1MB buffer
        var response_writer = std.Io.Writer.fixed(&response_buf);

        const result = try client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .headers = .{
                .content_type = .{ .override = "application/json" },
            },
            .extra_headers = &.{
                .{ .name = "x-api-key", .value = self.api_key },
                .{ .name = "anthropic-version", .value = "2023-06-01" },
            },
            .payload = json_buf.items,
            .response_writer = &response_writer,
        });

        if (result.status != .ok) {
            return error.HttpRequestFailed;
        }

        const response_body = response_buf[0..response_writer.end];

        // Parse response
        return try parseResponse(self.allocator, response_body);
    }
};

/// Message type for Anthropic API
pub const Message = struct {
    role: Role,
    content: Content,

    pub const Role = enum {
        user,
        assistant,
    };

    pub const Content = union(enum) {
        text: []const u8,
        parts: []const ContentPart,
    };
};

/// Content part for complex messages
pub const ContentPart = union(enum) {
    text: TextPart,
    tool_use: ToolUsePart,
    tool_result: ToolResultPart,

    pub const TextPart = struct {
        text: []const u8,
    };

    pub const ToolUsePart = struct {
        id: []const u8,
        name: []const u8,
        input: []const u8, // JSON string
    };

    pub const ToolResultPart = struct {
        tool_use_id: []const u8,
        content: []const u8,
    };
};

/// Tool definition
pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    input_schema: []const u8, // JSON schema as string
};

/// Response from Anthropic API
pub const Response = struct {
    id: []const u8,
    content: []ContentBlock,
    stop_reason: ?[]const u8,
    usage: Usage,

    pub const ContentBlock = union(enum) {
        text: []const u8,
        tool_use: ToolUse,
    };

    pub const ToolUse = struct {
        id: []const u8,
        name: []const u8,
        input: []const u8, // JSON string
    };

    pub const Usage = struct {
        input_tokens: u64,
        output_tokens: u64,
    };
};

fn writeMessage(writer: anytype, msg: Message, allocator: std.mem.Allocator) !void {
    try writer.writeAll("{\"role\":\"");
    try writer.writeAll(switch (msg.role) {
        .user => "user",
        .assistant => "assistant",
    });
    try writer.writeAll("\",\"content\":");

    switch (msg.content) {
        .text => |text| {
            try writer.writeAll("\"");
            try writer.writeAll(escapeJson(allocator, text) catch text);
            try writer.writeAll("\"");
        },
        .parts => |parts| {
            try writer.writeAll("[");
            for (parts, 0..) |part, i| {
                if (i > 0) try writer.writeAll(",");
                switch (part) {
                    .text => |t| {
                        try writer.writeAll("{\"type\":\"text\",\"text\":\"");
                        try writer.writeAll(escapeJson(allocator, t.text) catch t.text);
                        try writer.writeAll("\"}");
                    },
                    .tool_use => |tu| {
                        try writer.print("{{\"type\":\"tool_use\",\"id\":\"{s}\",\"name\":\"{s}\",\"input\":{s}}}", .{ tu.id, tu.name, tu.input });
                    },
                    .tool_result => |tr| {
                        try writer.print("{{\"type\":\"tool_result\",\"tool_use_id\":\"{s}\",\"content\":\"{s}\"}}", .{ tr.tool_use_id, escapeJson(allocator, tr.content) catch tr.content });
                    },
                }
            }
            try writer.writeAll("]");
        },
    }
    try writer.writeAll("}");
}

fn writeTool(writer: anytype, tool: Tool) !void {
    try writer.writeAll("{\"name\":\"");
    try writer.writeAll(tool.name);
    try writer.writeAll("\",\"description\":\"");
    try writer.writeAll(tool.description);
    try writer.writeAll("\",\"input_schema\":");
    try writer.writeAll(tool.input_schema);
    try writer.writeAll("}");
}

// =============================================================================
// Streaming API Support
// =============================================================================

/// Callback for streaming events
pub const StreamCallback = *const fn (event: StreamingEvent, context: ?*anyopaque) void;

/// Streaming event types from Anthropic API
pub const StreamingEvent = union(enum) {
    message_start: MessageStartEvent,
    content_block_start: ContentBlockStartEvent,
    content_block_delta: ContentBlockDeltaEvent,
    content_block_stop: ContentBlockStopEvent,
    message_delta: MessageDeltaEvent,
    message_stop: void,
    ping: void,
    error_event: ErrorEvent,

    pub const MessageStartEvent = struct {
        message_id: []const u8,
        input_tokens: ?u32 = null,
    };

    pub const ContentBlockStartEvent = struct {
        index: usize,
        content_type: ContentType,
        // For tool_use blocks
        tool_id: ?[]const u8 = null,
        tool_name: ?[]const u8 = null,
    };

    pub const ContentType = enum {
        text,
        tool_use,
    };

    pub const ContentBlockDeltaEvent = struct {
        index: usize,
        delta_type: DeltaType,
        text: ?[]const u8 = null,
        partial_json: ?[]const u8 = null,
    };

    pub const DeltaType = enum {
        text_delta,
        input_json_delta,
    };

    pub const ContentBlockStopEvent = struct {
        index: usize,
    };

    pub const MessageDeltaEvent = struct {
        stop_reason: ?[]const u8,
        output_tokens: ?u32 = null,
    };

    pub const ErrorEvent = struct {
        error_type: []const u8,
        message: []const u8,
    };
};

/// Send a streaming messages request to Anthropic API
pub fn sendMessagesStreaming(
    self: *const AnthropicClient,
    model_id: []const u8,
    messages: []const Message,
    system: ?[]const u8,
    tools: ?[]const Tool,
    temperature: f32,
    max_tokens: u32,
    callback: StreamCallback,
    context: ?*anyopaque,
) !void {
    // Build request JSON with stream: true
    var json_buf = std.ArrayList(u8){};
    defer json_buf.deinit(self.allocator);

    var writer = json_buf.writer(self.allocator);
    try writer.writeAll("{");
    try writer.print("\"model\":\"{s}\",", .{model_id});
    try writer.print("\"max_tokens\":{d},", .{max_tokens});
    try writer.print("\"temperature\":{d},", .{temperature});
    try writer.writeAll("\"stream\":true,");

    // System prompt
    if (system) |sys| {
        try writer.print("\"system\":\"{s}\",", .{escapeJson(self.allocator, sys) catch sys});
    }

    // Messages
    try writer.writeAll("\"messages\":[");
    for (messages, 0..) |msg, i| {
        if (i > 0) try writer.writeAll(",");
        try writeMessage(writer, msg, self.allocator);
    }
    try writer.writeAll("]");

    // Tools
    if (tools) |t| {
        if (t.len > 0) {
            try writer.writeAll(",\"tools\":[");
            for (t, 0..) |tool, i| {
                if (i > 0) try writer.writeAll(",");
                try writeTool(writer, tool);
            }
            try writer.writeAll("]");
        }
    }

    try writer.writeAll("}");

    // Make HTTP request
    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/messages", .{self.base_url});
    defer self.allocator.free(url);

    // Parse URL
    const uri = try std.Uri.parse(url);

    // Open connection
    var req = try client.open(.POST, uri, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "x-api-key", .value = self.api_key },
            .{ .name = "anthropic-version", .value = "2023-06-01" },
        },
    });
    defer req.deinit();

    // Send request body
    req.transfer_encoding = .{ .content_length = json_buf.items.len };
    try req.send();
    try req.writeAll(json_buf.items);
    try req.finish();

    // Wait for response
    try req.wait();

    if (req.status != .ok) {
        callback(.{ .error_event = .{
            .error_type = "http_error",
            .message = "Request failed",
        } }, context);
        return;
    }

    // Read and parse SSE stream
    var line_buf: [65536]u8 = undefined;
    var reader = req.reader();

    while (true) {
        const line = reader.readUntilDelimiterOrEof(&line_buf, '\n') catch |err| {
            callback(.{ .error_event = .{
                .error_type = "read_error",
                .message = @errorName(err),
            } }, context);
            return;
        };

        if (line == null) break;
        const trimmed = std.mem.trim(u8, line.?, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        // Parse SSE event
        if (std.mem.startsWith(u8, trimmed, "data: ")) {
            const data = trimmed[6..];
            if (std.mem.eql(u8, data, "[DONE]")) {
                callback(.{ .message_stop = {} }, context);
                break;
            }

            // Parse JSON event
            const event = parseStreamEvent(self.allocator, data) catch |err| {
                callback(.{ .error_event = .{
                    .error_type = "parse_error",
                    .message = @errorName(err),
                } }, context);
                continue;
            };

            callback(event, context);

            // Check for message_stop
            if (event == .message_stop) break;
        }
    }
}

fn parseStreamEvent(allocator: std.mem.Allocator, data: []const u8) !StreamingEvent {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const event_type = root.get("type").?.string;

    if (std.mem.eql(u8, event_type, "message_start")) {
        const msg = root.get("message").?.object;
        var input_tokens: ?u32 = null;
        if (msg.get("usage")) |usage_value| {
            if (usage_value == .object) {
                if (usage_value.object.get("input_tokens")) |tokens_value| {
                    input_tokens = @intCast(tokens_value.integer);
                }
            }
        }
        return .{ .message_start = .{
            .message_id = try allocator.dupe(u8, msg.get("id").?.string),
            .input_tokens = input_tokens,
        } };
    } else if (std.mem.eql(u8, event_type, "content_block_start")) {
        const index = @as(usize, @intCast(root.get("index").?.integer));
        const content_block = root.get("content_block").?.object;
        const block_type = content_block.get("type").?.string;

        if (std.mem.eql(u8, block_type, "tool_use")) {
            return .{ .content_block_start = .{
                .index = index,
                .content_type = .tool_use,
                .tool_id = try allocator.dupe(u8, content_block.get("id").?.string),
                .tool_name = try allocator.dupe(u8, content_block.get("name").?.string),
            } };
        } else {
            return .{ .content_block_start = .{
                .index = index,
                .content_type = .text,
            } };
        }
    } else if (std.mem.eql(u8, event_type, "content_block_delta")) {
        const index = @as(usize, @intCast(root.get("index").?.integer));
        const delta = root.get("delta").?.object;
        const delta_type = delta.get("type").?.string;

        if (std.mem.eql(u8, delta_type, "text_delta")) {
            return .{ .content_block_delta = .{
                .index = index,
                .delta_type = .text_delta,
                .text = try allocator.dupe(u8, delta.get("text").?.string),
            } };
        } else if (std.mem.eql(u8, delta_type, "input_json_delta")) {
            return .{ .content_block_delta = .{
                .index = index,
                .delta_type = .input_json_delta,
                .partial_json = try allocator.dupe(u8, delta.get("partial_json").?.string),
            } };
        }
    } else if (std.mem.eql(u8, event_type, "content_block_stop")) {
        return .{ .content_block_stop = .{
            .index = @as(usize, @intCast(root.get("index").?.integer)),
        } };
    } else if (std.mem.eql(u8, event_type, "message_delta")) {
        const delta = root.get("delta").?.object;
        const stop_reason = if (delta.get("stop_reason")) |sr|
            if (sr == .string) try allocator.dupe(u8, sr.string) else null
        else
            null;
        var output_tokens: ?u32 = null;
        if (delta.get("usage")) |usage_value| {
            if (usage_value == .object) {
                if (usage_value.object.get("output_tokens")) |tokens_value| {
                    output_tokens = @intCast(tokens_value.integer);
                }
            }
        }
        return .{ .message_delta = .{ .stop_reason = stop_reason, .output_tokens = output_tokens } };
    } else if (std.mem.eql(u8, event_type, "message_stop")) {
        return .{ .message_stop = {} };
    } else if (std.mem.eql(u8, event_type, "ping")) {
        return .{ .ping = {} };
    } else if (std.mem.eql(u8, event_type, "error")) {
        const err_obj = root.get("error").?.object;
        return .{ .error_event = .{
            .error_type = try allocator.dupe(u8, err_obj.get("type").?.string),
            .message = try allocator.dupe(u8, err_obj.get("message").?.string),
        } };
    }

    return .{ .ping = {} }; // Unknown event type, treat as ping
}

fn parseResponse(allocator: std.mem.Allocator, body: []const u8) !Response {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;

    // Extract content blocks
    var content_list = std.ArrayList(Response.ContentBlock){};
    if (root.get("content")) |content_array| {
        for (content_array.array.items) |item| {
            const obj = item.object;
            const content_type = obj.get("type").?.string;

            if (std.mem.eql(u8, content_type, "text")) {
                const text = try allocator.dupe(u8, obj.get("text").?.string);
                try content_list.append(allocator, .{ .text = text });
            } else if (std.mem.eql(u8, content_type, "tool_use")) {
                const id = try allocator.dupe(u8, obj.get("id").?.string);
                const name = try allocator.dupe(u8, obj.get("name").?.string);

                // Serialize input back to JSON string
                const input_json = try std.json.Stringify.valueAlloc(allocator, obj.get("input").?, .{});

                try content_list.append(allocator, .{
                    .tool_use = .{
                        .id = id,
                        .name = name,
                        .input = input_json,
                    },
                });
            }
        }
    }

    return .{
        .id = try allocator.dupe(u8, root.get("id").?.string),
        .content = try content_list.toOwnedSlice(allocator),
        .stop_reason = if (root.get("stop_reason")) |sr| try allocator.dupe(u8, sr.string) else null,
        .usage = .{
            .input_tokens = @intCast(root.get("usage").?.object.get("input_tokens").?.integer),
            .output_tokens = @intCast(root.get("usage").?.object.get("output_tokens").?.integer),
        },
    };
}

fn escapeJson(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    for (str) |c| {
        switch (c) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }
    return result.toOwnedSlice(allocator);
}

test "escapeJson" {
    const allocator = std.testing.allocator;
    const result = try escapeJson(allocator, "hello\nworld");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello\\nworld", result);
}
