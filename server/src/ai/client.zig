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
        var json_buf = std.ArrayList(u8).init(self.allocator);
        defer json_buf.deinit();

        var writer = json_buf.writer();
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

        // Make HTTP request
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = try std.Uri.parse(self.base_url ++ "/v1/messages");

        var buf: [16384]u8 = undefined;
        var req = try client.open(.POST, uri, .{
            .server_header_buffer = &buf,
            .extra_headers = &.{
                .{ .name = "x-api-key", .value = self.api_key },
                .{ .name = "anthropic-version", .value = "2023-06-01" },
                .{ .name = "content-type", .value = "application/json" },
            },
        });
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = json_buf.items.len };
        try req.send();
        try req.writeAll(json_buf.items);
        try req.finish();
        try req.wait();

        // Read response
        const response_body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(response_body);

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

fn parseResponse(allocator: std.mem.Allocator, body: []const u8) !Response {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;

    // Extract content blocks
    var content_list = std.ArrayList(Response.ContentBlock).init(allocator);
    if (root.get("content")) |content_array| {
        for (content_array.array.items) |item| {
            const obj = item.object;
            const content_type = obj.get("type").?.string;

            if (std.mem.eql(u8, content_type, "text")) {
                const text = try allocator.dupe(u8, obj.get("text").?.string);
                try content_list.append(.{ .text = text });
            } else if (std.mem.eql(u8, content_type, "tool_use")) {
                const id = try allocator.dupe(u8, obj.get("id").?.string);
                const name = try allocator.dupe(u8, obj.get("name").?.string);

                // Serialize input back to JSON string
                var input_buf = std.ArrayList(u8).init(allocator);
                try std.json.stringify(obj.get("input").?, .{}, input_buf.writer());

                try content_list.append(.{
                    .tool_use = .{
                        .id = id,
                        .name = name,
                        .input = try input_buf.toOwnedSlice(),
                    },
                });
            }
        }
    }

    return .{
        .id = try allocator.dupe(u8, root.get("id").?.string),
        .content = try content_list.toOwnedSlice(),
        .stop_reason = if (root.get("stop_reason")) |sr| try allocator.dupe(u8, sr.string) else null,
        .usage = .{
            .input_tokens = @intCast(root.get("usage").?.object.get("input_tokens").?.integer),
            .output_tokens = @intCast(root.get("usage").?.object.get("output_tokens").?.integer),
        },
    };
}

fn escapeJson(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    for (str) |c| {
        switch (c) {
            '"' => try result.appendSlice("\\\""),
            '\\' => try result.appendSlice("\\\\"),
            '\n' => try result.appendSlice("\\n"),
            '\r' => try result.appendSlice("\\r"),
            '\t' => try result.appendSlice("\\t"),
            else => try result.append(c),
        }
    }
    return result.toOwnedSlice();
}

test "escapeJson" {
    const allocator = std.testing.allocator;
    const result = try escapeJson(allocator, "hello\nworld");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello\\nworld", result);
}
