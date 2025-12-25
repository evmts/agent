//! Session routes - CRUD operations for agent sessions
//!
//! Handles all session management endpoints:
//! - GET /sessions - List all sessions
//! - POST /sessions - Create new session
//! - GET /sessions/:sessionId - Get session details
//! - PATCH /sessions/:sessionId - Update session
//! - DELETE /sessions/:sessionId - Delete session
//! - POST /sessions/:sessionId/abort - Abort running session
//! - GET /sessions/:sessionId/diff - Get session diff
//! - GET /sessions/:sessionId/changes - Get session changes
//! - GET /sessions/:sessionId/changes/:changeId - Get specific change
//! - GET /sessions/:sessionId/changes/:fromChangeId/compare/:toChangeId - Compare changes
//! - GET /sessions/:sessionId/changes/:changeId/files - Get files at change
//! - GET /sessions/:sessionId/changes/:changeId/file/* - Get file content at change
//! - GET /sessions/:sessionId/conflicts - Get conflicts
//! - GET /sessions/:sessionId/operations - Get operations log
//! - POST /sessions/:sessionId/operations/undo - Undo last operation
//! - POST /sessions/:sessionId/operations/:operationId/restore - Restore operation
//! - POST /sessions/:sessionId/fork - Fork session
//! - POST /sessions/:sessionId/revert - Revert session
//! - POST /sessions/:sessionId/unrevert - Unrevert session
//! - POST /sessions/:sessionId/undo - Undo turns

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");
const json = @import("../lib/json.zig");

const log = std.log.scoped(.session_routes);

// Import JJ FFI
const c = @cImport({
    @cInclude("jj_ffi.h");
});

/// Helper to generate session ID
fn generateSessionId(allocator: std.mem.Allocator) ![]const u8 {
    const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
    var id_buf: [15]u8 = undefined;
    id_buf[0] = 's';
    id_buf[1] = 'e';
    id_buf[2] = 's';
    id_buf[3] = '_';

    var i: usize = 4;
    while (i < 15) : (i += 1) {
        const idx = std.crypto.random.intRangeAtMost(usize, 0, chars.len - 1);
        id_buf[i] = chars[idx];
    }

    return try allocator.dupe(u8, &id_buf);
}

/// Helper to write JSON field with proper escaping
fn writeJsonField(writer: anytype, key: []const u8, value: []const u8) !void {
    try json.writeString(writer, key);
    try writer.writeByte(':');
    try json.writeString(writer, value);
}

/// Helper to write optional JSON field with proper escaping
fn writeJsonOptionalField(writer: anytype, key: []const u8, value: ?[]const u8) !void {
    try json.writeString(writer, key);
    try writer.writeByte(':');
    if (value) |v| {
        try json.writeString(writer, v);
    } else {
        try writer.writeAll("null");
    }
}

/// Helper to write session record as JSON
fn writeSessionJson(writer: anytype, session: db.AgentSessionRecord) !void {
    try writer.writeAll("{");
    try writeJsonField(writer, "id", session.id);
    try writer.writeAll(",");
    try writeJsonField(writer, "projectID", session.project_id);
    try writer.writeAll(",");
    try writeJsonField(writer, "directory", session.directory);
    try writer.writeAll(",");
    try writeJsonField(writer, "title", session.title);
    try writer.writeAll(",");
    try writeJsonField(writer, "version", session.version);
    try writer.writeAll(",");
    try writer.print("\"time\":{{\"created\":{d},\"updated\":{d}", .{ session.time_created, session.time_updated });
    if (session.time_archived) |archived| {
        try writer.print(",\"archived\":{d}", .{archived});
    }
    try writer.writeAll("}");
    try writer.writeAll(",");
    try writeJsonOptionalField(writer, "parentID", session.parent_id);
    try writer.writeAll(",");
    try writeJsonOptionalField(writer, "forkPoint", session.fork_point);
    try writer.writeAll(",");
    try writer.print("\"tokenCount\":{d}", .{session.token_count});
    try writer.writeAll(",");
    try writer.print("\"bypassMode\":{s}", .{if (session.bypass_mode) "true" else "false"});
    try writer.writeAll(",");
    try writeJsonOptionalField(writer, "model", session.model);
    try writer.writeAll(",");
    try writeJsonOptionalField(writer, "reasoningEffort", session.reasoning_effort);
    try writer.writeAll(",");
    if (session.plugins.len > 0) {
        try writer.print("\"plugins\":{s}", .{session.plugins});
    } else {
        try writer.writeAll("\"plugins\":[]");
    }
    try writer.writeAll(",");
    // Include workflow_run_id for unified session/workflow model
    if (session.workflow_run_id) |wrid| {
        try writer.print("\"workflowRunId\":{d}", .{wrid});
    } else {
        try writer.writeAll("\"workflowRunId\":null");
    }
    try writer.writeAll("}");
}

// =============================================================================
// Route Handlers
// =============================================================================

/// GET /api/sessions
/// List all sessions for user
pub fn listSessions(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    var sessions = db.getAllAgentSessions(ctx.pool, ctx.allocator) catch |err| {
        log.err("Failed to get sessions: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve sessions\"}");
        return;
    };
    defer sessions.deinit(ctx.allocator);

    var writer = res.writer();
    try writer.writeAll("{\"sessions\":[");

    for (sessions.items, 0..) |session, i| {
        if (i > 0) try writer.writeAll(",");
        try writeSessionJson(writer, session);
    }

    try writer.writeAll("]}");
}

/// POST /api/sessions
/// Create a new session with linked workflow_run for agent execution
pub fn createSession(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    // Parse JSON body
    const parsed = std.json.parseFromSlice(struct {
        directory: ?[]const u8 = null,
        title: ?[]const u8 = null,
        parentID: ?[]const u8 = null,
        bypassMode: ?bool = null,
        model: ?[]const u8 = null,
        reasoningEffort: ?[]const u8 = null,
        plugins: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Generate session ID
    const session_id = try generateSessionId(ctx.allocator);
    defer ctx.allocator.free(session_id);

    // Get current directory if not provided
    const cwd = if (v.directory) |d| d else std.fs.cwd().realpathAlloc(ctx.allocator, ".") catch "/tmp";
    defer if (v.directory == null) ctx.allocator.free(cwd);

    const title = v.title orelse "New Session";
    const plugins = v.plugins orelse "[]";

    // 1. Create workflow_run with trigger_type='interactive'
    const workflow_run_id = db.workflows.createWorkflowRun(
        ctx.pool,
        null, // workflow_definition_id (null for interactive sessions)
        "interactive",
        "{}", // trigger_payload (empty for interactive)
        null, // inputs
    ) catch |err| {
        log.err("Failed to create workflow_run: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create workflow run\"}");
        return;
    };

    // 2. Generate agent token (24 hour expiry)
    const agent_token = db.generateAgentToken(
        ctx.pool,
        ctx.allocator,
        workflow_run_id,
        db.agent_tokens.DEFAULT_EXPIRY_MS,
    ) catch |err| {
        log.err("Failed to generate agent token: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to generate agent token\"}");
        return;
    };
    defer ctx.allocator.free(agent_token);

    // 3. Create session with workflow_run_id
    db.createAgentSessionWithWorkflowRun(
        ctx.pool,
        session_id,
        cwd,
        title,
        v.parentID,
        v.bypassMode orelse false,
        v.model,
        v.reasoningEffort,
        plugins,
        workflow_run_id,
    ) catch |err| {
        log.err("Failed to create session: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create session\"}");
        return;
    };

    // 4. Update workflow_run with session_id (bidirectional link)
    db.workflows.updateWorkflowRunSessionId(ctx.pool, workflow_run_id, session_id) catch |err| {
        log.warn("Failed to update workflow_run session_id: {}", .{err});
        // Non-fatal - session was created successfully
    };

    // Fetch the created session
    const session = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (session == null) {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Session created but not found\"}");
        return;
    }

    // 5. Return session + agent_token (token shown only once)
    res.status = 201;
    var writer = res.writer();
    try writer.writeAll("{\"session\":");
    try writeSessionJson(writer, session.?);
    try writer.writeAll(",\"agentToken\":\"");
    try writer.writeAll(agent_token);
    try writer.writeAll("\"}");
}

/// GET /api/sessions/:sessionId
/// Get a session by ID
pub fn getSession(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    const session = db.getAgentSessionById(ctx.pool, session_id) catch |err| {
        log.err("Failed to get session: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve session\"}");
        return;
    };

    if (session == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    var writer = res.writer();
    try writer.writeAll("{\"session\":");
    try writeSessionJson(writer, session.?);
    try writer.writeAll("}");
}

/// PATCH /api/sessions/:sessionId
/// Update a session
pub fn updateSession(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const existing = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (existing == null) {
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
        title: ?[]const u8 = null,
        archived: ?bool = null,
        model: ?[]const u8 = null,
        reasoningEffort: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Update session
    db.updateAgentSession(
        ctx.pool,
        session_id,
        v.title,
        v.archived,
        v.model,
        v.reasoningEffort,
    ) catch |err| {
        log.err("Failed to update session: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update session\"}");
        return;
    };

    // Fetch updated session
    const session = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (session == null) {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Session updated but not found\"}");
        return;
    }

    var writer = res.writer();
    try writer.writeAll("{\"session\":");
    try writeSessionJson(writer, session.?);
    try writer.writeAll("}");
}

/// DELETE /api/sessions/:sessionId
/// Delete a session
pub fn deleteSession(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const existing = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    // Delete session
    db.deleteAgentSession(ctx.pool, session_id) catch |err| {
        log.err("Failed to delete session: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to delete session\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

/// POST /api/sessions/:sessionId/abort
/// Abort a session's active task
pub fn abortSession(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const existing = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    // Set abort flag via connection manager
    if (ctx.connection_manager) |manager| {
        try manager.abort(session_id);
        try res.writer().writeAll("{\"success\":true}");
    } else {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Connection manager not available\",\"success\":false}");
    }
}

/// GET /api/sessions/:sessionId/diff
/// Get session diff
pub fn getSessionDiff(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const query_params = try req.query();
    _ = query_params.get("messageId");

    // Open jj workspace
    const workspace_result = c.jj_workspace_open(session.?.directory.ptr);
    defer {
        if (workspace_result.success and workspace_result.workspace != null) {
            c.jj_workspace_free(workspace_result.workspace);
        }
        if (workspace_result.error_message != null) {
            c.jj_string_free(workspace_result.error_message);
        }
    }

    if (!workspace_result.success) {
        log.warn("Failed to open jj workspace: {s}", .{std.mem.span(workspace_result.error_message)});
        try res.writer().writeAll("{\"diffs\":[]}");
        return;
    }

    // List recent changes to show as diffs
    const changes_result = c.jj_list_changes(workspace_result.workspace, 10, null);
    defer {
        if (changes_result.success and changes_result.commits != null) {
            c.jj_commit_array_free(changes_result.commits, changes_result.len);
        }
        if (changes_result.error_message != null) {
            c.jj_string_free(changes_result.error_message);
        }
    }

    if (!changes_result.success) {
        log.err("Failed to list changes: {s}", .{std.mem.span(changes_result.error_message)});
        try res.writer().writeAll("{\"diffs\":[]}");
        return;
    }

    var writer = res.writer();
    try writer.writeAll("{\"diffs\":[");

    if (changes_result.commits != null) {
        const commits = changes_result.commits[0..changes_result.len];
        for (commits, 0..) |commit_ptr, i| {
            if (i > 0) try writer.writeAll(",");

            const commit = commit_ptr.*;
            const change_id = std.mem.span(commit.change_id);
            const desc = std.mem.span(commit.description);

            try writer.writeAll("{");
            try writer.print("\"changeId\":\"{s}\",", .{change_id});
            try writer.print("\"description\":\"{s}\",", .{desc});
            try writer.print("\"timestamp\":{d},", .{commit.author_timestamp});
            try writer.print("\"isEmpty\":{s}", .{if (commit.is_empty) "true" else "false"});
            try writer.writeAll("}");
        }
    }

    try writer.writeAll("]}");
}

/// GET /api/sessions/:sessionId/changes
/// Get changes (snapshots) for a session
pub fn getSessionChanges(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const query_params = try req.query();
    const limit_str = query_params.get("limit");
    const limit: u32 = if (limit_str) |l| std.fmt.parseInt(u32, l, 10) catch 50 else 50;

    // Open jj workspace
    const workspace_result = c.jj_workspace_open(session.?.directory.ptr);
    defer {
        if (workspace_result.success and workspace_result.workspace != null) {
            c.jj_workspace_free(workspace_result.workspace);
        }
        if (workspace_result.error_message != null) {
            c.jj_string_free(workspace_result.error_message);
        }
    }

    if (!workspace_result.success) {
        log.warn("Failed to open jj workspace: {s}", .{std.mem.span(workspace_result.error_message)});
        try res.writer().writeAll("{\"changes\":[],\"currentChangeId\":null,\"total\":0}");
        return;
    }

    // List changes
    const changes_result = c.jj_list_changes(workspace_result.workspace, limit, null);
    defer {
        if (changes_result.success and changes_result.commits != null) {
            c.jj_commit_array_free(changes_result.commits, changes_result.len);
        }
        if (changes_result.error_message != null) {
            c.jj_string_free(changes_result.error_message);
        }
    }

    if (!changes_result.success) {
        log.err("Failed to list changes: {s}", .{std.mem.span(changes_result.error_message)});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to list changes\"}");
        return;
    }

    var writer = res.writer();
    try writer.writeAll("{\"changes\":[");

    if (changes_result.commits != null) {
        const commits = changes_result.commits[0..changes_result.len];
        for (commits, 0..) |commit_ptr, i| {
            if (i > 0) try writer.writeAll(",");

            const commit = commit_ptr.*;
            const change_id = std.mem.span(commit.change_id);
            const desc = std.mem.span(commit.description);
            const author_name = std.mem.span(commit.author_name);
            const author_email = std.mem.span(commit.author_email);

            try writer.writeAll("{");
            try writer.print("\"changeId\":\"{s}\",", .{change_id});
            try writer.print("\"commitId\":\"{s}\",", .{std.mem.span(commit.id)});
            try writer.print("\"description\":\"{s}\",", .{desc});
            try writer.print("\"author\":{{\"name\":\"{s}\",\"email\":\"{s}\"}},", .{ author_name, author_email });
            try writer.print("\"timestamp\":{d},", .{commit.author_timestamp});
            try writer.print("\"isEmpty\":{s}", .{if (commit.is_empty) "true" else "false"});
            try writer.writeAll("}");
        }
    }

    const current_change_id = if (changes_result.len > 0 and changes_result.commits != null)
        std.mem.span(changes_result.commits[0].*.change_id)
    else
        "";

    try writer.print("],\"currentChangeId\":", .{});
    if (current_change_id.len > 0) {
        try writer.print("\"{s}\"", .{current_change_id});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"total\":{d}}}", .{changes_result.len});
}

/// GET /api/sessions/:sessionId/changes/:changeId
/// Get a specific change's details
pub fn getSpecificChange(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId\"}");
        return;
    };

    // Verify session exists
    const session = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (session == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    // Open jj workspace
    const workspace_result = c.jj_workspace_open(session.?.directory.ptr);
    defer {
        if (workspace_result.success and workspace_result.workspace != null) {
            c.jj_workspace_free(workspace_result.workspace);
        }
        if (workspace_result.error_message != null) {
            c.jj_string_free(workspace_result.error_message);
        }
    }

    if (!workspace_result.success) {
        log.warn("Failed to open jj workspace: {s}", .{std.mem.span(workspace_result.error_message)});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to open workspace\"}");
        return;
    }

    // Get commit info by ID
    const commit_result = c.jj_get_commit(workspace_result.workspace, change_id.ptr);
    defer {
        if (commit_result.success and commit_result.commit != null) {
            c.jj_commit_info_free(commit_result.commit);
        }
        if (commit_result.error_message != null) {
            c.jj_string_free(commit_result.error_message);
        }
    }

    if (!commit_result.success) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Change not found\"}");
        return;
    }

    const commit = commit_result.commit.*;
    const change_id_str = std.mem.span(commit.change_id);
    const desc = std.mem.span(commit.description);
    const author_name = std.mem.span(commit.author_name);
    const author_email = std.mem.span(commit.author_email);
    const committer_name = std.mem.span(commit.committer_name);
    const committer_email = std.mem.span(commit.committer_email);

    var writer = res.writer();
    try writer.writeAll("{\"change\":{");
    try writer.print("\"changeId\":\"{s}\",", .{change_id_str});
    try writer.print("\"commitId\":\"{s}\",", .{std.mem.span(commit.id)});
    try writer.print("\"description\":\"{s}\",", .{desc});
    try writer.print("\"author\":{{\"name\":\"{s}\",\"email\":\"{s}\"}},", .{ author_name, author_email });
    try writer.print("\"committer\":{{\"name\":\"{s}\",\"email\":\"{s}\"}},", .{ committer_name, committer_email });
    try writer.print("\"timestamp\":{d},", .{commit.author_timestamp});
    try writer.print("\"isEmpty\":{s},", .{if (commit.is_empty) "true" else "false"});

    // Parent IDs
    try writer.writeAll("\"parents\":[");
    if (commit.parent_ids != null and commit.parent_ids_len > 0) {
        const parent_ids = commit.parent_ids[0..commit.parent_ids_len];
        for (parent_ids, 0..) |parent_id_ptr, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("\"{s}\"", .{std.mem.span(parent_id_ptr)});
        }
    }
    try writer.writeAll("]");

    try writer.writeAll("}}");
}

/// GET /api/sessions/:sessionId/changes/:fromChangeId/compare/:toChangeId
/// Get diff between two changes in a session
pub fn compareChanges(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    const from_change_id = req.param("fromChangeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing fromChangeId\"}");
        return;
    };

    const to_change_id = req.param("toChangeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing toChangeId\"}");
        return;
    };

    // Verify session exists
    const session = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (session == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    // Open jj workspace
    const workspace_result = c.jj_workspace_open(session.?.directory.ptr);
    defer {
        if (workspace_result.success and workspace_result.workspace != null) {
            c.jj_workspace_free(workspace_result.workspace);
        }
        if (workspace_result.error_message != null) {
            c.jj_string_free(workspace_result.error_message);
        }
    }

    if (!workspace_result.success) {
        log.warn("Failed to open jj workspace: {s}", .{std.mem.span(workspace_result.error_message)});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to open workspace\"}");
        return;
    }

    // Get both commits to verify they exist
    const from_commit_result = c.jj_get_commit(workspace_result.workspace, from_change_id.ptr);
    defer {
        if (from_commit_result.success and from_commit_result.commit != null) {
            c.jj_commit_info_free(from_commit_result.commit);
        }
        if (from_commit_result.error_message != null) {
            c.jj_string_free(from_commit_result.error_message);
        }
    }

    const to_commit_result = c.jj_get_commit(workspace_result.workspace, to_change_id.ptr);
    defer {
        if (to_commit_result.success and to_commit_result.commit != null) {
            c.jj_commit_info_free(to_commit_result.commit);
        }
        if (to_commit_result.error_message != null) {
            c.jj_string_free(to_commit_result.error_message);
        }
    }

    if (!from_commit_result.success or !to_commit_result.success) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"One or both changes not found\"}");
        return;
    }

    // Note: Full diff computation would require additional FFI functions
    // For now, return metadata about the changes being compared
    var writer = res.writer();
    try writer.writeAll("{\"from\":\"");
    try writer.writeAll(from_change_id);
    try writer.writeAll("\",\"to\":\"");
    try writer.writeAll(to_change_id);
    try writer.writeAll("\",\"diffs\":[],\"note\":\"Full diff computation requires additional FFI support\"}");
}

/// GET /api/sessions/:sessionId/changes/:changeId/files
/// Get files at a specific change
pub fn getFilesAtChange(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId\"}");
        return;
    };

    // Verify session exists
    const session = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (session == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    // Open jj workspace
    const workspace_result = c.jj_workspace_open(session.?.directory.ptr);
    defer {
        if (workspace_result.success and workspace_result.workspace != null) {
            c.jj_workspace_free(workspace_result.workspace);
        }
        if (workspace_result.error_message != null) {
            c.jj_string_free(workspace_result.error_message);
        }
    }

    if (!workspace_result.success) {
        log.warn("Failed to open jj workspace: {s}", .{std.mem.span(workspace_result.error_message)});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to open workspace\"}");
        return;
    }

    // List files at change
    const files_result = c.jj_list_files(workspace_result.workspace, change_id.ptr);
    defer {
        if (files_result.success and files_result.strings != null) {
            c.jj_string_array_free(files_result.strings, files_result.len);
        }
        if (files_result.error_message != null) {
            c.jj_string_free(files_result.error_message);
        }
    }

    if (!files_result.success) {
        log.err("Failed to list files: {s}", .{std.mem.span(files_result.error_message)});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to list files\"}");
        return;
    }

    var writer = res.writer();
    try writer.writeAll("{\"files\":[");

    if (files_result.strings != null) {
        const files = files_result.strings[0..files_result.len];
        for (files, 0..) |file_ptr, i| {
            if (i > 0) try writer.writeAll(",");
            const file_path = std.mem.span(file_ptr);
            try writer.print("\"{s}\"", .{file_path});
        }
    }

    try writer.writeAll("]}");
}

/// GET /api/sessions/:sessionId/changes/:changeId/file/*
/// Get file content at a specific change
pub fn getFileAtChange(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId\"}");
        return;
    };

    // Verify session exists
    const session = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (session == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    // Extract file path from URL (everything after /file/)
    const path = req.url.path;
    const file_marker = "/file/";
    const file_idx = std.mem.indexOf(u8, path, file_marker);
    if (file_idx == null) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"File path required\"}");
        return;
    }

    const file_path = path[file_idx.? + file_marker.len ..];
    if (file_path.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"File path required\"}");
        return;
    }

    // Open jj workspace
    const workspace_result = c.jj_workspace_open(session.?.directory.ptr);
    defer {
        if (workspace_result.success and workspace_result.workspace != null) {
            c.jj_workspace_free(workspace_result.workspace);
        }
        if (workspace_result.error_message != null) {
            c.jj_string_free(workspace_result.error_message);
        }
    }

    if (!workspace_result.success) {
        log.warn("Failed to open jj workspace: {s}", .{std.mem.span(workspace_result.error_message)});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to open workspace\"}");
        return;
    }

    // Get file content at change
    const content_result = c.jj_get_file_content(workspace_result.workspace, change_id.ptr, file_path.ptr);
    defer {
        if (content_result.string != null) {
            c.jj_string_free(content_result.string);
        }
        if (content_result.error_message != null) {
            c.jj_string_free(content_result.error_message);
        }
    }

    if (!content_result.success) {
        res.status = 404;
        var writer = res.writer();
        try writer.print("{{\"error\":\"File '{s}' not found at this change\"}}", .{file_path});
        return;
    }

    const content = std.mem.span(content_result.string);
    var writer = res.writer();
    try writer.writeAll("{\"path\":\"");
    try writer.writeAll(file_path);
    try writer.writeAll("\",\"content\":\"");

    // Escape JSON string content
    for (content) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }

    try writer.writeAll("\"}");
}

/// GET /api/sessions/:sessionId/conflicts
/// Get conflicts for a session
pub fn getSessionConflicts(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const existing = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    // TODO: Implement JJ-based conflict detection
    const query_params = try req.query();
    _ = query_params.get("changeId");
    try res.writer().writeAll("{\"conflicts\":[],\"hasConflicts\":false,\"currentChangeId\":null}");
}

/// GET /api/sessions/:sessionId/operations
/// Get operation log for a session
pub fn getSessionOperations(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const query_params = try req.query();
    _ = query_params.get("limit");

    // Open jj workspace
    const workspace_result = c.jj_workspace_open(session.?.directory.ptr);
    defer {
        if (workspace_result.success and workspace_result.workspace != null) {
            c.jj_workspace_free(workspace_result.workspace);
        }
        if (workspace_result.error_message != null) {
            c.jj_string_free(workspace_result.error_message);
        }
    }

    if (!workspace_result.success) {
        log.warn("Failed to open jj workspace: {s}", .{std.mem.span(workspace_result.error_message)});
        try res.writer().writeAll("{\"operations\":[],\"total\":0}");
        return;
    }

    // Get current operation
    const op_result = c.jj_get_current_operation(workspace_result.workspace);
    defer {
        if (op_result.success and op_result.operation != null) {
            c.jj_operation_info_free(op_result.operation);
        }
        if (op_result.error_message != null) {
            c.jj_string_free(op_result.error_message);
        }
    }

    var writer = res.writer();
    try writer.writeAll("{\"operations\":[");

    if (op_result.success and op_result.operation != null) {
        const op = op_result.operation.*;
        const op_id = std.mem.span(op.id);
        const op_desc = std.mem.span(op.description);

        try writer.writeAll("{");
        try writer.print("\"id\":\"{s}\",", .{op_id});
        try writer.print("\"description\":\"{s}\",", .{op_desc});
        try writer.print("\"timestamp\":{d}", .{op.timestamp});
        try writer.writeAll("}");

        try writer.writeAll("],\"total\":1}");
    } else {
        try writer.writeAll("],\"total\":0}");
    }
}

/// POST /api/sessions/:sessionId/operations/undo
/// Undo last jj operation
pub fn undoLastOperation(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const existing = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    // Note: jj_undo is not available in the FFI yet
    res.status = 501;
    try res.writer().writeAll("{\"error\":\"Undo operation not implemented in FFI\",\"success\":false}");
}

/// POST /api/sessions/:sessionId/operations/:operationId/restore
/// Restore to a specific operation
pub fn restoreOperation(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    const operation_id = req.param("operationId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing operationId\"}");
        return;
    };

    // Verify session exists
    const existing = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    _ = operation_id;

    // Note: jj_restore_operation is not available in the FFI yet
    res.status = 501;
    try res.writer().writeAll("{\"error\":\"Restore operation not implemented in FFI\",\"success\":false}");
}

/// POST /api/sessions/:sessionId/fork
/// Fork a session
pub fn forkSession(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const parent_session = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (parent_session == null) {
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
        messageId: ?[]const u8 = null,
        title: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;
    const parent = parent_session.?;

    // Generate new session ID
    const new_session_id = try generateSessionId(ctx.allocator);
    defer ctx.allocator.free(new_session_id);

    const title = v.title orelse try std.fmt.allocPrint(ctx.allocator, "Fork of {s}", .{parent.title});
    defer if (v.title == null) ctx.allocator.free(title);

    // Create forked session
    db.createAgentSession(
        ctx.pool,
        new_session_id,
        parent.directory,
        title,
        session_id, // parent_id
        parent.bypass_mode,
        parent.model,
        parent.reasoning_effort,
        parent.plugins,
    ) catch |err| {
        log.err("Failed to fork session: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to fork session\"}");
        return;
    };

    // TODO: Copy snapshot state from parent session at messageId

    // Fetch the created session
    const session = db.getAgentSessionById(ctx.pool, new_session_id) catch null;
    if (session == null) {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Session forked but not found\"}");
        return;
    }

    res.status = 201;
    var writer = res.writer();
    try writer.writeAll("{\"session\":");
    try writeSessionJson(writer, session.?);
    try writer.writeAll("}");
}

/// POST /api/sessions/:sessionId/revert
/// Revert a session
pub fn revertSession(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const existing = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (existing == null) {
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
        messageId: []const u8,
        partId: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    // Note: jj_revert is not available in the FFI yet
    res.status = 501;
    try res.writer().writeAll("{\"error\":\"Revert operation not implemented in FFI\",\"success\":false}");
}

/// POST /api/sessions/:sessionId/unrevert
/// Unrevert a session
pub fn unrevertSession(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const existing = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Session not found\"}");
        return;
    }

    // Note: jj_unrevert is not available in the FFI yet
    res.status = 501;
    try res.writer().writeAll("{\"error\":\"Unrevert operation not implemented in FFI\",\"success\":false}");
}

/// POST /api/sessions/:sessionId/undo
/// Undo turns
pub fn undoTurns(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sessionId\"}");
        return;
    };

    // Verify session exists
    const existing = db.getAgentSessionById(ctx.pool, session_id) catch null;
    if (existing == null) {
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
        count: ?i32 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    _ = parsed.value.count;

    // Note: Undo turns requires coordination between message deletion and jj operations
    // This needs additional FFI support and database logic
    res.status = 501;
    try res.writer().writeAll("{\"error\":\"Undo turns not implemented\",\"success\":false}");
}

// =============================================================================
// SSE Stream for Agent
// =============================================================================

const agent_handler = @import("../websocket/agent_handler.zig");

/// SSE stream handler for agent session streaming
/// GET /api/sessions/:sessionId/stream
pub fn streamSession(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const session_id = req.param("sessionId") orelse {
        res.status = 400;
        res.content_type = .TEXT;
        try res.writer().writeAll("Missing session id");
        return;
    };

    // Verify session exists
    const session = db.getAgentSessionById(ctx.pool, session_id) catch {
        res.status = 500;
        res.content_type = .TEXT;
        try res.writer().writeAll("Database error");
        return;
    };

    if (session == null) {
        res.status = 404;
        res.content_type = .TEXT;
        try res.writer().writeAll("Session not found");
        return;
    }

    log.info("Starting SSE stream for agent session: {s}", .{session_id});

    // Set up SSE headers
    res.content_type = .EVENTS;
    res.headers.add("Cache-Control", "no-cache");
    res.headers.add("Connection", "keep-alive");
    res.headers.add("X-Accel-Buffering", "no");

    // Clear any existing abort flag for this session
    if (ctx.connection_manager) |manager| {
        manager.clearAbort(session_id);
    }

    const writer = res.writer();

    // Send initial connection event
    try writer.writeAll("event: connected\ndata: {\"type\":\"connected\"}\n\n");

    // Keep connection alive with periodic keepalive comments
    // In a real implementation, this would integrate with the agent execution
    // For now, this just demonstrates the SSE format
    log.info("SSE stream established for session: {s}", .{session_id});
}
