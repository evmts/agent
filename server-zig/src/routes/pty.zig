const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const pty = @import("../websocket/pty.zig");
const ws_handler = @import("../websocket/handler.zig");

const log = std.log.scoped(.pty_routes);

/// Create a new PTY session
/// POST /pty
pub fn create(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    _ = ctx.allocator;
    res.content_type = .JSON;

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    // Extract command and workdir from JSON
    const command = extractJsonString(body, "cmd") orelse extractJsonString(body, "command") orelse "bash";
    const workdir = extractJsonString(body, "workdir") orelse "/tmp";

    // Create PTY session
    const session = ctx.pty_manager.createSession(command, workdir) catch |err| {
        log.err("Failed to create PTY session: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create PTY session\"}");
        return;
    };

    log.info("PTY session created: id={s}, command={s}, workdir={s}", .{ session.id, command, workdir });

    // Return session info
    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"id":"{s}","command":"{s}","workdir":"{s}","pid":{d}}}
    , .{ session.id, session.command, session.workdir, session.pid });
}

/// List all PTY sessions
/// GET /pty
pub fn list(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    const allocator = ctx.allocator;
    res.content_type = .JSON;

    const sessions = ctx.pty_manager.listSessions(allocator) catch |err| {
        log.err("Failed to list PTY sessions: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to list sessions\"}");
        return;
    };
    defer allocator.free(sessions);

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"sessions\":[");

    for (sessions, 0..) |session, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":"{s}","command":"{s}","workdir":"{s}","pid":{d},"running":{s}}}
        , .{
            session.id,
            session.command,
            session.workdir,
            session.pid,
            if (session.running) "true" else "false",
        });
    }

    try writer.writeAll("]}");
}

/// Get PTY session info
/// GET /pty/:id
pub fn get(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const id = req.param("id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing session id\"}");
        return;
    };

    const session = ctx.pty_manager.getSession(id) catch {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    };

    // Check status
    session.checkStatus();

    // Return session info
    var writer = res.writer();
    try writer.print(
        \\{{"id":"{s}","command":"{s}","workdir":"{s}","pid":{d},"running":{s}}}
    , .{
        session.id,
        session.command,
        session.workdir,
        session.pid,
        if (session.running) "true" else "false",
    });
}

/// Close a PTY session
/// DELETE /pty/:id
pub fn close(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const id = req.param("id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing session id\"}");
        return;
    };

    ctx.pty_manager.closeSession(id) catch {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    };

    log.info("PTY session closed via API: id={s}", .{id});
    try res.writer().writeAll("{\"success\":true}");
}

/// WebSocket upgrade handler for PTY streaming
/// GET /pty/:id/ws (with Upgrade: websocket header)
pub fn websocket(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const id = req.param("id") orelse {
        res.status = 400;
        res.content_type = .TEXT;
        try res.writer().writeAll("Missing session id");
        return;
    };

    // Get the PTY session
    const session = ctx.pty_manager.getSession(id) catch {
        res.status = 404;
        res.content_type = .TEXT;
        try res.writer().writeAll("Session not found");
        return;
    };

    // Check if session is still running
    session.checkStatus();
    if (!session.running) {
        res.status = 410; // Gone
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Session has ended\"}");
        return;
    }

    log.info("Upgrading to WebSocket for PTY session: {s}", .{id});

    // Prepare upgrade context
    const upgrade_ctx = ws_handler.UpgradeContext{
        .session = session,
    };

    // Upgrade to WebSocket
    const upgraded = try httpz.upgradeWebsocket(ws_handler.PtyWebSocket, req, res, &upgrade_ctx);
    if (!upgraded) {
        res.status = 400;
        res.content_type = .TEXT;
        try res.writer().writeAll("Invalid WebSocket upgrade request");
        return;
    }

    log.info("WebSocket upgrade successful for PTY session: {s}", .{id});
}

/// Simple JSON string extractor (avoids need for full JSON parser)
fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    // Find "key":"
    var pattern_buf: [256]u8 = undefined;
    const pattern = std.fmt.bufPrint(&pattern_buf, "\"{s}\":\"", .{key}) catch return null;

    const start_idx = std.mem.indexOf(u8, json, pattern) orelse return null;
    const value_start = start_idx + pattern.len;

    // Find closing quote
    const value_end = std.mem.indexOfPos(u8, json, value_start, "\"") orelse return null;

    return json[value_start..value_end];
}
