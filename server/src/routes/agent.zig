const std = @import("std");
const httpz = @import("httpz");
const ai_mod = @import("../ai/mod.zig");
const db = @import("db");
const Context = @import("../main.zig").Context;

/// POST /api/sessions/:sessionId/run
/// Run agent on session with streaming SSE response
pub fn runAgentHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Parse request body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(RunAgentRequest, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const request = parsed.value;

    // Get session from database
    const session = db.getAgentSessionById(ctx.pool, session_id) catch {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    };

    // Set up SSE headers
    res.content_type = .EVENTS;
    res.headers.add("Cache-Control", "no-cache");
    res.headers.add("Connection", "keep-alive");
    res.headers.add("X-Accel-Buffering", "no");

    // Create tool context
    var file_tracker = ai_mod.FileTimeTracker.init(ctx.allocator);
    defer file_tracker.deinit();

    const tool_ctx = ai_mod.ToolContext{
        .session_id = session_id,
        .working_dir = session.directory,
        .allocator = ctx.allocator,
        .file_tracker = &file_tracker,
    };

    // Build messages array
    var messages = std.ArrayList(ai_mod.Message){};
    defer messages.deinit(ctx.allocator);

    // Add user message
    try messages.append(ctx.allocator, .{
        .role = .user,
        .content = .{ .text = request.message },
    });

    // Set up streaming response
    const writer = res.writer();

    // Create SSE callback context
    var sse_ctx = SSEContext{
        .writer = writer,
        .allocator = ctx.allocator,
    };

    // Run agent with streaming
    ai_mod.streamAgent(
        ctx.allocator,
        messages.items,
        .{
            .model_id = request.model orelse "claude-sonnet-4-20250514",
            .agent_name = request.agent_name orelse "build",
            .working_dir = session.directory,
            .session_id = session_id,
        },
        tool_ctx,
        .{
            .on_event = sseEventHandler,
            .context = &sse_ctx,
        },
    ) catch |err| {
        // Send error event
        const error_json = try std.fmt.allocPrint(ctx.allocator, "{{\"type\":\"error\",\"error\":\"{s}\"}}", .{@errorName(err)});
        defer ctx.allocator.free(error_json);

        try writer.print("data: {s}\n\n", .{error_json});
    };

    // Send final done event
    try writer.writeAll("data: {\"type\":\"done\"}\n\n");
}

const RunAgentRequest = struct {
    message: []const u8,
    model: ?[]const u8 = null,
    agent_name: ?[]const u8 = null,
};

const SSEContext = struct {
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
};

fn sseEventHandler(event: ai_mod.StreamEvent, context: ?*anyopaque) void {
    const sse_ctx = @as(*SSEContext, @ptrCast(@alignCast(context.?)));

    const json = event.toJson(sse_ctx.allocator) catch return;
    defer sse_ctx.allocator.free(json);

    sse_ctx.writer.print("data: {s}\n\n", .{json}) catch {};
}

/// GET /api/agents
/// List available agents
pub fn listAgentsHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    const response =
        \\{
        \\  "agents": [
        \\    {"name": "build", "description": "Primary agent with full tool access for development tasks", "mode": "primary"},
        \\    {"name": "explore", "description": "Read-only agent for fast codebase exploration", "mode": "subagent"},
        \\    {"name": "plan", "description": "Analysis and planning agent (read-only)", "mode": "subagent"},
        \\    {"name": "general", "description": "General-purpose subagent with full tool access", "mode": "subagent"}
        \\  ]
        \\}
    ;

    res.content_type = .JSON;
    try res.writer().writeAll(response);
}

/// GET /api/agents/:name
/// Get agent configuration
pub fn getAgentHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const name = req.param("name") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing agent name\"}");
        return;
    };

    const config = ai_mod.getAgentConfig(name);

    // Build JSON response
    var json = std.ArrayList(u8){};
    defer json.deinit(ctx.allocator);

    try json.appendSlice(ctx.allocator, "{\"name\":\"");
    try json.appendSlice(ctx.allocator, config.name);
    try json.appendSlice(ctx.allocator, "\",\"description\":\"");
    try json.appendSlice(ctx.allocator, config.description);
    try json.appendSlice(ctx.allocator, "\",\"mode\":\"");
    try json.appendSlice(ctx.allocator, if (config.mode == .primary) "primary" else "subagent");
    try json.appendSlice(ctx.allocator, "\",\"temperature\":");
    try json.writer(ctx.allocator).print("{d}", .{config.temperature});
    try json.appendSlice(ctx.allocator, ",\"top_p\":");
    try json.writer(ctx.allocator).print("{d}", .{config.top_p});
    try json.appendSlice(ctx.allocator, ",\"tools_enabled\":{");
    try json.appendSlice(ctx.allocator, "\"grep\":");
    try json.appendSlice(ctx.allocator, if (config.tools_enabled.grep) "true" else "false");
    try json.appendSlice(ctx.allocator, ",\"read_file\":");
    try json.appendSlice(ctx.allocator, if (config.tools_enabled.read_file) "true" else "false");
    try json.appendSlice(ctx.allocator, ",\"write_file\":");
    try json.appendSlice(ctx.allocator, if (config.tools_enabled.write_file) "true" else "false");
    try json.appendSlice(ctx.allocator, ",\"multiedit\":");
    try json.appendSlice(ctx.allocator, if (config.tools_enabled.multiedit) "true" else "false");
    try json.appendSlice(ctx.allocator, ",\"web_fetch\":");
    try json.appendSlice(ctx.allocator, if (config.tools_enabled.web_fetch) "true" else "false");
    try json.appendSlice(ctx.allocator, ",\"github\":");
    try json.appendSlice(ctx.allocator, if (config.tools_enabled.github) "true" else "false");
    try json.appendSlice(ctx.allocator, ",\"unified_exec\":");
    try json.appendSlice(ctx.allocator, if (config.tools_enabled.unified_exec) "true" else "false");
    try json.appendSlice(ctx.allocator, ",\"write_stdin\":");
    try json.appendSlice(ctx.allocator, if (config.tools_enabled.write_stdin) "true" else "false");
    try json.appendSlice(ctx.allocator, ",\"close_pty_session\":");
    try json.appendSlice(ctx.allocator, if (config.tools_enabled.close_pty_session) "true" else "false");
    try json.appendSlice(ctx.allocator, ",\"list_pty_sessions\":");
    try json.appendSlice(ctx.allocator, if (config.tools_enabled.list_pty_sessions) "true" else "false");
    try json.appendSlice(ctx.allocator, "}}");

    res.content_type = .JSON;
    try res.writer().writeAll(json.items);
}

/// GET /api/tools
/// List available tools
pub fn listToolsHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    const response =
        \\{
        \\  "tools": [
        \\    {"name": "grep", "description": "Search for patterns in files using ripgrep"},
        \\    {"name": "readFile", "description": "Read a file with line numbers"},
        \\    {"name": "writeFile", "description": "Write content to a file"},
        \\    {"name": "multiedit", "description": "Apply multiple find-replace edits to a file"},
        \\    {"name": "webFetch", "description": "Fetch content from a URL"},
        \\    {"name": "github", "description": "Execute GitHub CLI commands"},
        \\    {"name": "unifiedExec", "description": "Execute a command in a PTY session"},
        \\    {"name": "writeStdin", "description": "Send input to a running PTY session"},
        \\    {"name": "closePtySession", "description": "Close a PTY session"},
        \\    {"name": "listPtySessions", "description": "List active PTY sessions"}
        \\  ]
        \\}
    ;

    res.content_type = .JSON;
    try res.writer().writeAll(response);
}
