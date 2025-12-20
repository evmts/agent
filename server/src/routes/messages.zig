//! Message routes - CRUD operations for agent messages
//!
//! Handles all message and part management endpoints:
//! - GET /api/sessions/:sessionId/messages - List messages for session
//! - POST /api/sessions/:sessionId/messages - Create new message
//! - GET /api/sessions/:sessionId/messages/:messageId - Get message details
//! - PATCH /api/sessions/:sessionId/messages/:messageId - Update message
//! - DELETE /api/sessions/:sessionId/messages/:messageId - Delete message
//! - GET /api/sessions/:sessionId/messages/:messageId/parts - Get message parts
//! - POST /api/sessions/:sessionId/messages/:messageId/parts - Create part
//! - PATCH /api/sessions/:sessionId/messages/:messageId/parts/:partId - Update part
//! - DELETE /api/sessions/:sessionId/messages/:messageId/parts/:partId - Delete part

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("../lib/db.zig");

const log = std.log.scoped(.message_routes);

/// Helper to generate message ID
fn generateMessageId(allocator: std.mem.Allocator) ![]const u8 {
    const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
    var id_buf: [15]u8 = undefined;
    id_buf[0] = 'm';
    id_buf[1] = 's';
    id_buf[2] = 'g';
    id_buf[3] = '_';

    var i: usize = 4;
    while (i < 15) : (i += 1) {
        const idx = std.crypto.random.intRangeAtMost(usize, 0, chars.len - 1);
        id_buf[i] = chars[idx];
    }

    return try allocator.dupe(u8, &id_buf);
}

/// Helper to generate part ID
fn generatePartId(allocator: std.mem.Allocator) ![]const u8 {
    const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
    var id_buf: [15]u8 = undefined;
    id_buf[0] = 'p';
    id_buf[1] = 'r';
    id_buf[2] = 't';
    id_buf[3] = '_';

    var i: usize = 4;
    while (i < 15) : (i += 1) {
        const idx = std.crypto.random.intRangeAtMost(usize, 0, chars.len - 1);
        id_buf[i] = chars[idx];
    }

    return try allocator.dupe(u8, &id_buf);
}

/// Helper to write message as JSON
fn writeMessageJson(writer: anytype, msg: db.MessageRecord, allocator: std.mem.Allocator) !void {
    try writer.writeAll("{");
    try writer.print("\"id\":\"{s}\",", .{msg.id});
    try writer.print("\"sessionId\":\"{s}\",", .{msg.session_id});
    try writer.print("\"role\":\"{s}\",", .{msg.role});
    try writer.print("\"timeCreated\":{d},", .{msg.time_created});

    if (msg.time_completed) |tc| {
        try writer.print("\"timeCompleted\":{d},", .{tc});
    } else {
        try writer.writeAll("\"timeCompleted\":null,");
    }

    try writer.print("\"status\":\"{s}\"", .{msg.status});

    if (msg.thinking_text) |tt| {
        const escaped = try escapeJson(allocator, tt);
        defer allocator.free(escaped);
        try writer.print(",\"thinkingText\":\"{s}\"", .{escaped});
    }

    if (msg.error_message) |em| {
        const escaped = try escapeJson(allocator, em);
        defer allocator.free(escaped);
        try writer.print(",\"errorMessage\":\"{s}\"", .{escaped});
    }

    try writer.writeAll("}");
}

/// Helper to write part as JSON
fn writePartJson(writer: anytype, part: db.PartRecord, allocator: std.mem.Allocator) !void {
    try writer.writeAll("{");
    try writer.print("\"id\":\"{s}\",", .{part.id});
    try writer.print("\"messageId\":\"{s}\",", .{part.message_id});
    try writer.print("\"type\":\"{s}\",", .{part.type_});
    try writer.print("\"sortOrder\":{d}", .{part.sort_order});

    if (part.text) |t| {
        const escaped = try escapeJson(allocator, t);
        defer allocator.free(escaped);
        try writer.print(",\"text\":\"{s}\"", .{escaped});
    }

    if (part.tool_name) |tn| {
        try writer.print(",\"toolName\":\"{s}\"", .{tn});
    }

    if (part.tool_state) |ts| {
        try writer.print(",\"toolState\":{s}", .{ts});
    }

    if (part.mime) |m| {
        try writer.print(",\"mime\":\"{s}\"", .{m});
    }

    if (part.url) |u| {
        try writer.print(",\"url\":\"{s}\"", .{u});
    }

    if (part.filename) |f| {
        try writer.print(",\"filename\":\"{s}\"", .{f});
    }

    if (part.time_start) |ts| {
        try writer.print(",\"timeStart\":{d}", .{ts});
    }

    if (part.time_end) |te| {
        try writer.print(",\"timeEnd\":{d}", .{te});
    }

    try writer.writeAll("}");
}

/// Simple JSON string escaper
fn escapeJson(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, input.len);
    errdefer result.deinit(allocator);

    for (input) |c| {
        switch (c) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }

    return try result.toOwnedSlice(allocator);
}

// =============================================================================
// Message Route Handlers
// =============================================================================

/// GET /api/sessions/:sessionId/messages
/// List all messages for a session
pub fn listMessages(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const session = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (session == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    // Get messages
    var messages = db.getAgentSessionMessages(ctx.pool, ctx.allocator, session_id) catch |err| {
        log.err("Failed to get messages: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve messages\"}");
        return;
    };
    defer messages.deinit(ctx.allocator);

    var writer = res.writer();
    try writer.writeAll("{\"messages\":[");

    for (messages.items, 0..) |message, i| {
        if (i > 0) try writer.writeAll(",");
        try writeMessageJson(writer, message, ctx.allocator);
    }

    try writer.writeAll("]}");
}

/// POST /api/sessions/:sessionId/messages
/// Create a new message
pub fn createMessage(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const session = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (session == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    // Parse JSON body
    const parsed = std.json.parseFromSlice(struct {
        role: []const u8,
        status: ?[]const u8 = null,
        thinkingText: ?[]const u8 = null,
        errorMessage: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Validate role
    if (!std.mem.eql(u8, v.role, "user") and !std.mem.eql(u8, v.role, "assistant")) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid role. Must be 'user' or 'assistant'\"}");
        return;
    }

    // Generate message ID
    const message_id = try generateMessageId(ctx.allocator);
    defer ctx.allocator.free(message_id);

    // Create message
    db.createMessage(
        ctx.pool,
        message_id,
        session_id,
        v.role,
        v.status orelse "pending",
        v.thinkingText,
        v.errorMessage,
    ) catch |err| {
        log.err("Failed to create message: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create message\"}");
        return;
    };

    // Fetch the created message
    const message = db.getMessageById(ctx.pool, message_id) catch null;
    if (message == null) {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Message created but not found\"}");
        return;
    }

    res.status = 201;
    var writer = res.writer();
    try writer.writeAll("{\"message\":");
    try writeMessageJson(writer, message.?, ctx.allocator);
    try writer.writeAll("}");
}

/// GET /api/sessions/:sessionId/messages/:messageId
/// Get a message by ID with its parts
pub fn getMessage(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const message_id = req.param("messageId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing messageId\"}");
        return;
    };

    const message = db.getMessageById(ctx.pool, message_id) catch |err| {
        log.err("Failed to get message: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve message\"}");
        return;
    };

    if (message == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Message not found\"}");
        return;
    }

    // Get parts for this message
    var parts = db.getMessageParts(ctx.pool, ctx.allocator, message_id) catch |err| {
        log.err("Failed to get parts: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve parts\"}");
        return;
    };
    defer parts.deinit(ctx.allocator);

    var writer = res.writer();
    try writer.writeAll("{\"message\":");
    try writeMessageJson(writer, message.?, ctx.allocator);
    try writer.writeAll(",\"parts\":[");

    for (parts.items, 0..) |part, i| {
        if (i > 0) try writer.writeAll(",");
        try writePartJson(writer, part, ctx.allocator);
    }

    try writer.writeAll("]}");
}

/// PATCH /api/sessions/:sessionId/messages/:messageId
/// Update a message
pub fn updateMessage(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const message_id = req.param("messageId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing messageId\"}");
        return;
    };

    // Verify message exists
    const existing = db.getMessageById(ctx.pool, message_id) catch null;
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Message not found\"}");
        return;
    }

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    // Parse JSON body
    const parsed = std.json.parseFromSlice(struct {
        status: ?[]const u8 = null,
        thinkingText: ?[]const u8 = null,
        errorMessage: ?[]const u8 = null,
        timeCompleted: ?i64 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Update message
    db.updateMessage(
        ctx.pool,
        message_id,
        v.status,
        v.thinkingText,
        v.errorMessage,
        v.timeCompleted,
    ) catch |err| {
        log.err("Failed to update message: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update message\"}");
        return;
    };

    // Fetch updated message
    const message = db.getMessageById(ctx.pool, message_id) catch null;
    if (message == null) {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Message updated but not found\"}");
        return;
    }

    var writer = res.writer();
    try writer.writeAll("{\"message\":");
    try writeMessageJson(writer, message.?, ctx.allocator);
    try writer.writeAll("}");
}

/// DELETE /api/sessions/:sessionId/messages/:messageId
/// Delete a message
pub fn deleteMessage(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const message_id = req.param("messageId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing messageId\"}");
        return;
    };

    // Verify message exists
    const existing = db.getMessageById(ctx.pool, message_id) catch null;
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Message not found\"}");
        return;
    }

    // Delete message (CASCADE will delete parts)
    db.deleteMessage(ctx.pool, message_id) catch |err| {
        log.err("Failed to delete message: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to delete message\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

// =============================================================================
// Part Route Handlers
// =============================================================================

/// GET /api/sessions/:sessionId/messages/:messageId/parts
/// Get all parts for a message
pub fn listParts(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const message_id = req.param("messageId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing messageId\"}");
        return;
    };

    // Verify message exists
    const message = db.getMessageById(ctx.pool, message_id) catch null;
    if (message == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Message not found\"}");
        return;
    }

    // Get parts
    var parts = db.getMessageParts(ctx.pool, ctx.allocator, message_id) catch |err| {
        log.err("Failed to get parts: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve parts\"}");
        return;
    };
    defer parts.deinit(ctx.allocator);

    var writer = res.writer();
    try writer.writeAll("{\"parts\":[");

    for (parts.items, 0..) |part, i| {
        if (i > 0) try writer.writeAll(",");
        try writePartJson(writer, part, ctx.allocator);
    }

    try writer.writeAll("]}");
}

/// POST /api/sessions/:sessionId/messages/:messageId/parts
/// Create a new part
pub fn createPart(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    const message_id = req.param("messageId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing messageId\"}");
        return;
    };

    // Verify message exists
    const message = db.getMessageById(ctx.pool, message_id) catch null;
    if (message == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Message not found\"}");
        return;
    }

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    // Parse JSON body
    const parsed = std.json.parseFromSlice(struct {
        type: []const u8,
        text: ?[]const u8 = null,
        toolName: ?[]const u8 = null,
        toolState: ?[]const u8 = null,
        mime: ?[]const u8 = null,
        url: ?[]const u8 = null,
        filename: ?[]const u8 = null,
        sortOrder: ?i32 = null,
        timeStart: ?i64 = null,
        timeEnd: ?i64 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Validate type
    const valid_types = [_][]const u8{ "text", "reasoning", "tool", "file" };
    var valid_type = false;
    for (valid_types) |valid| {
        if (std.mem.eql(u8, v.type, valid)) {
            valid_type = true;
            break;
        }
    }

    if (!valid_type) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid type. Must be 'text', 'reasoning', 'tool', or 'file'\"}");
        return;
    }

    // Generate part ID
    const part_id = try generatePartId(ctx.allocator);
    defer ctx.allocator.free(part_id);

    // Create part
    db.createPart(
        ctx.pool,
        part_id,
        session_id,
        message_id,
        v.type,
        v.text,
        v.toolName,
        v.toolState,
        v.mime,
        v.url,
        v.filename,
        v.sortOrder orelse 0,
        v.timeStart,
        v.timeEnd,
    ) catch |err| {
        log.err("Failed to create part: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create part\"}");
        return;
    };

    // Fetch the created part
    const part = db.getPartById(ctx.pool, part_id) catch null;
    if (part == null) {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Part created but not found\"}");
        return;
    }

    res.status = 201;
    var writer = res.writer();
    try writer.writeAll("{\"part\":");
    try writePartJson(writer, part.?, ctx.allocator);
    try writer.writeAll("}");
}

/// PATCH /api/sessions/:sessionId/messages/:messageId/parts/:partId
/// Update a part
pub fn updatePart(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const part_id = req.param("partId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing partId\"}");
        return;
    };

    // Verify part exists
    const existing = db.getPartById(ctx.pool, part_id) catch null;
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Part not found\"}");
        return;
    }

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    // Parse JSON body
    const parsed = std.json.parseFromSlice(struct {
        text: ?[]const u8 = null,
        toolState: ?[]const u8 = null,
        timeStart: ?i64 = null,
        timeEnd: ?i64 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Update part
    db.updatePart(
        ctx.pool,
        part_id,
        v.text,
        v.toolState,
        v.timeStart,
        v.timeEnd,
    ) catch |err| {
        log.err("Failed to update part: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update part\"}");
        return;
    };

    // Fetch updated part
    const part = db.getPartById(ctx.pool, part_id) catch null;
    if (part == null) {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Part updated but not found\"}");
        return;
    }

    var writer = res.writer();
    try writer.writeAll("{\"part\":");
    try writePartJson(writer, part.?, ctx.allocator);
    try writer.writeAll("}");
}

/// DELETE /api/sessions/:sessionId/messages/:messageId/parts/:partId
/// Delete a part
pub fn deletePart(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const part_id = req.param("partId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing partId\"}");
        return;
    };

    // Verify part exists
    const existing = db.getPartById(ctx.pool, part_id) catch null;
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Part not found\"}");
        return;
    }

    // Delete part
    db.deletePart(ctx.pool, part_id) catch |err| {
        log.err("Failed to delete part: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to delete part\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}
