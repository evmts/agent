const std = @import("std");
const httpz = @import("httpz");
const ai_mod = @import("../ai/mod.zig");
const db = @import("../lib/db.zig");
const Context = @import("../main.zig").Context;

/// POST /api/sessions/:sessionId/run
/// Run agent on session with streaming SSE response
pub fn runAgentHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const session_id = req.param("sessionId") orelse {
        res.status = .bad_request;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Parse request body
    const body = req.body() orelse {
        res.status = .bad_request;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(RunAgentRequest, ctx.allocator, body, .{}) catch {
        res.status = .bad_request;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const request = parsed.value;

    // Get session from database
    const session = db.getAgentSessionById(ctx.pool, ctx.allocator, session_id) catch {
        res.status = .not_found;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    };

    // Set up SSE headers
    res.content_type = .@"text/event-stream";
    try res.headers.append("Cache-Control", "no-cache");
    try res.headers.append("Connection", "keep-alive");
    try res.headers.append("X-Accel-Buffering", "no");

    // Create tool context
    var file_tracker = ai_mod.FileTimeTracker.init(ctx.allocator);
    defer file_tracker.deinit();

    const tool_ctx = ai_mod.ToolContext{
        .session_id = session_id,
        .working_dir = session.directory,
        .allocator = ctx.allocator,
        .pty_manager = ctx.pty_manager,
        .file_tracker = &file_tracker,
    };

    // Build messages array
    var messages = std.ArrayList(ai_mod.Message).init(ctx.allocator);
    defer messages.deinit();

    // Add user message
    try messages.append(.{
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
    writer: httpz.Response.Writer,
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

    res.content_type = .@"application/json";
    try res.writer().writeAll(response);
}

/// GET /api/agents/:name
/// Get agent configuration
pub fn getAgentHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const name = req.param("name") orelse {
        res.status = .bad_request;
        try res.writer().writeAll("{\"error\":\"Missing agent name\"}");
        return;
    };

    const config = ai_mod.getAgentConfig(name);

    // Build JSON response
    var json = std.ArrayList(u8).init(ctx.allocator);
    defer json.deinit();

    try json.appendSlice("{\"name\":\"");
    try json.appendSlice(config.name);
    try json.appendSlice("\",\"description\":\"");
    try json.appendSlice(config.description);
    try json.appendSlice("\",\"mode\":\"");
    try json.appendSlice(if (config.mode == .primary) "primary" else "subagent");
    try json.appendSlice("\",\"temperature\":");
    try json.writer().print("{d}", .{config.temperature});
    try json.appendSlice(",\"top_p\":");
    try json.writer().print("{d}", .{config.top_p});
    try json.appendSlice(",\"tools_enabled\":{");
    try json.appendSlice("\"grep\":");
    try json.appendSlice(if (config.tools_enabled.grep) "true" else "false");
    try json.appendSlice(",\"read_file\":");
    try json.appendSlice(if (config.tools_enabled.read_file) "true" else "false");
    try json.appendSlice(",\"write_file\":");
    try json.appendSlice(if (config.tools_enabled.write_file) "true" else "false");
    try json.appendSlice(",\"multiedit\":");
    try json.appendSlice(if (config.tools_enabled.multiedit) "true" else "false");
    try json.appendSlice(",\"web_fetch\":");
    try json.appendSlice(if (config.tools_enabled.web_fetch) "true" else "false");
    try json.appendSlice(",\"github\":");
    try json.appendSlice(if (config.tools_enabled.github) "true" else "false");
    try json.appendSlice(",\"unified_exec\":");
    try json.appendSlice(if (config.tools_enabled.unified_exec) "true" else "false");
    try json.appendSlice(",\"write_stdin\":");
    try json.appendSlice(if (config.tools_enabled.write_stdin) "true" else "false");
    try json.appendSlice(",\"close_pty_session\":");
    try json.appendSlice(if (config.tools_enabled.close_pty_session) "true" else "false");
    try json.appendSlice(",\"list_pty_sessions\":");
    try json.appendSlice(if (config.tools_enabled.list_pty_sessions) "true" else "false");
    try json.appendSlice("}}");

    res.content_type = .@"application/json";
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

    res.content_type = .@"application/json";
    try res.writer().writeAll(response);
}
