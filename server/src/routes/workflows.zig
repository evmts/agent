//! Workflow routes
//!
//! Handles workflow run operations:
//! - GET /:user/:repo/workflows/runs - List workflow runs
//! - GET /:user/:repo/workflows/runs/:runId - Get workflow run
//! - POST /:user/:repo/workflows/runs - Create workflow run
//! - PATCH /:user/:repo/workflows/runs/:runId - Update workflow run
//! - POST /:user/:repo/workflows/runs/:runId/cancel - Cancel workflow run
//! - GET /:user/:repo/workflows/runs/:runId/jobs - Get workflow jobs
//! - GET /:user/:repo/workflows/runs/:runId/logs - Get workflow logs

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("../lib/db.zig");

const log = std.log.scoped(.workflow_routes);

/// Workflow status enum (matches Gitea's ActionStatus)
pub const WorkflowStatus = enum(i32) {
    unknown = 0,
    success = 1,
    failure = 2,
    cancelled = 3,
    skipped = 4,
    waiting = 5,
    running = 6,
    blocked = 7,

    pub fn toString(self: WorkflowStatus) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .success => "success",
            .failure => "failure",
            .cancelled => "cancelled",
            .skipped => "skipped",
            .waiting => "waiting",
            .running => "running",
            .blocked => "blocked",
        };
    }

    pub fn fromString(s: []const u8) ?WorkflowStatus {
        if (std.mem.eql(u8, s, "unknown")) return .unknown;
        if (std.mem.eql(u8, s, "success")) return .success;
        if (std.mem.eql(u8, s, "failure")) return .failure;
        if (std.mem.eql(u8, s, "cancelled")) return .cancelled;
        if (std.mem.eql(u8, s, "skipped")) return .skipped;
        if (std.mem.eql(u8, s, "waiting")) return .waiting;
        if (std.mem.eql(u8, s, "running")) return .running;
        if (std.mem.eql(u8, s, "blocked")) return .blocked;
        return null;
    }
};

/// GET /:user/:repo/workflows/runs
/// List workflow runs for a repository
pub fn listRuns(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Parse query parameters (simple parsing - in production use a proper query parser)
    const query = req.url.query;
    var status_str: ?[]const u8 = null;
    var page_str: []const u8 = "1";
    var per_page_str: []const u8 = "20";

    // Simple query parameter extraction
    if (std.mem.indexOf(u8, query, "status=")) |idx| {
        const start = idx + 7;
        const end = std.mem.indexOfPos(u8, query, start, "&") orelse query.len;
        status_str = query[start..end];
    }
    if (std.mem.indexOf(u8, query, "page=")) |idx| {
        const start = idx + 5;
        const end = std.mem.indexOfPos(u8, query, start, "&") orelse query.len;
        page_str = query[start..end];
    }
    if (std.mem.indexOf(u8, query, "per_page=")) |idx| {
        const start = idx + 9;
        const end = std.mem.indexOfPos(u8, query, start, "&") orelse query.len;
        per_page_str = query[start..end];
    }

    const page = std.fmt.parseInt(i32, page_str, 10) catch 1;
    const per_page = std.fmt.parseInt(i32, per_page_str, 10) catch 20;
    const offset = (page - 1) * per_page;

    // Get repository ID
    const repo_id = try db.getRepositoryId(ctx.pool, username, repo_name);
    if (repo_id == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Parse status filter if provided
    var status_filter: ?WorkflowStatus = null;
    if (status_str) |s| {
        status_filter = WorkflowStatus.fromString(s);
    }

    // Get runs from database (convert WorkflowStatus enum to i32)
    const status_int: ?i32 = if (status_filter) |s| @intFromEnum(s) else null;
    const runs = try db.listWorkflowRuns(ctx.pool, ctx.allocator, repo_id.?, status_int, per_page, offset);
    defer ctx.allocator.free(runs);

    // Build JSON response
    var writer = res.writer();
    try writer.print("{{\"runs\":[", .{});

    for (runs, 0..) |run, i| {
        if (i > 0) try writer.writeAll(",");
        const status = (WorkflowStatus.fromString(run.status) orelse WorkflowStatus.unknown).toString();
        try writer.print(
            \\{{"id":{d},"runNumber":{d},"title":"{s}","status":"{s}","triggerEvent":"{s}","createdAt":"{s}"}}
        , .{
            run.id,
            run.run_number,
            run.title,
            status,
            run.trigger_event,
            run.created_at,
        });
    }

    try writer.print("]],\"page\":{d},\"perPage\":{d}}}", .{ page, per_page });
}

/// GET /:user/:repo/workflows/runs/:runId
/// Get a specific workflow run with its jobs
pub fn getRun(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const run_id_str = req.param("runId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing runId parameter\"}");
        return;
    };

    const run_id = std.fmt.parseInt(i64, run_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid runId\"}");
        return;
    };

    // Get run
    const run = try db.getWorkflowRun(ctx.pool, ctx.allocator, run_id);
    if (run == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Workflow run not found\"}");
        return;
    }
    defer if (run) |r| ctx.allocator.free(r.title);

    // Get jobs for this run
    const jobs = try db.getWorkflowJobs(ctx.pool, ctx.allocator, run_id);
    defer ctx.allocator.free(jobs);

    // Build JSON response
    var writer = res.writer();
    const r = run.?;
    try writer.print(
        \\{{"run":{{"id":{d},"runNumber":{d},"title":"{s}","status":"{s}","triggerEvent":"{s}","createdAt":"{s}"}},"jobs":[
    , .{
        r.id,
        r.run_number,
        r.title,
        r.status,
        r.trigger_event,
        r.created_at,
    });

    for (jobs, 0..) |job, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":{d},"name":"{s}","jobId":"{s}","status":"{s}"}}
        , .{
            job.id,
            job.name,
            job.job_id,
            job.status,
        });
    }

    try writer.writeAll("]}}");
}

/// POST /:user/:repo/workflows/runs
/// Create a new workflow run
pub fn createRun(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository ID
    const repo_id = try db.getRepositoryId(ctx.pool, username, repo_name);
    if (repo_id == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        workflowDefinitionId: ?i64 = null,
        title: []const u8,
        triggerEvent: []const u8,
        ref: ?[]const u8 = null,
        commitSha: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Create workflow run
    const run_id = try db.createWorkflowRun(
        ctx.pool,
        repo_id.?,
        v.workflowDefinitionId,
        v.title,
        v.triggerEvent,
        ctx.user.?.id,
        v.ref,
        v.commitSha,
    );

    res.status = 201;
    var writer = res.writer();
    try writer.print("{{\"run\":{{\"id\":{d}}}}}", .{run_id});
}

/// PATCH /:user/:repo/workflows/runs/:runId
/// Update workflow run status
pub fn updateRun(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const run_id_str = req.param("runId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing runId parameter\"}");
        return;
    };

    const run_id = std.fmt.parseInt(i64, run_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid runId\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        status: []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const status = WorkflowStatus.fromString(parsed.value.status) orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid status\"}");
        return;
    };

    // Update run status (convert enum to i32)
    const status_int: i32 = @intFromEnum(status);
    try db.updateWorkflowRunStatus(ctx.pool, run_id, status_int);

    try res.writer().writeAll("{\"ok\":true}");
}

/// POST /:user/:repo/workflows/runs/:runId/cancel
/// Cancel a running workflow
pub fn cancelRun(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const run_id_str = req.param("runId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing runId parameter\"}");
        return;
    };

    const run_id = std.fmt.parseInt(i64, run_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid runId\"}");
        return;
    };

    // Get run to check current status
    const run = try db.getWorkflowRun(ctx.pool, ctx.allocator, run_id);
    if (run == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Workflow run not found\"}");
        return;
    }
    defer if (run) |r| ctx.allocator.free(r.title);

    const r = run.?;
    const current_status = WorkflowStatus.fromString(r.status) orelse WorkflowStatus.unknown;

    // Can only cancel running or waiting workflows
    if (current_status != WorkflowStatus.running and current_status != WorkflowStatus.waiting) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Cannot cancel completed workflow\"}");
        return;
    }

    // Update to cancelled
    const cancelled_int: i32 = @intFromEnum(WorkflowStatus.cancelled);
    try db.updateWorkflowRunStatus(ctx.pool, run_id, cancelled_int);

    try res.writer().writeAll("{\"ok\":true}");
}

/// GET /:user/:repo/workflows/runs/:runId/jobs
/// Get jobs for a workflow run
pub fn getJobs(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const run_id_str = req.param("runId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing runId parameter\"}");
        return;
    };

    const run_id = std.fmt.parseInt(i64, run_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid runId\"}");
        return;
    };

    // Get jobs
    const jobs = try db.getWorkflowJobs(ctx.pool, ctx.allocator, run_id);
    defer ctx.allocator.free(jobs);

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"jobs\":[");

    for (jobs, 0..) |job, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":{d},"name":"{s}","jobId":"{s}","status":"{s}"}}
        , .{
            job.id,
            job.name,
            job.job_id,
            job.status,
        });
    }

    try writer.writeAll("]}");
}

/// GET /:user/:repo/workflows/runs/:runId/logs
/// Get logs for a workflow run
pub fn getLogs(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const run_id_str = req.param("runId") orelse {
        res.status = 400;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Missing runId parameter\"}");
        return;
    };

    const run_id = std.fmt.parseInt(i64, run_id_str, 10) catch {
        res.status = 400;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Invalid runId\"}");
        return;
    };

    // Parse optional step filter
    const query = req.url.query;
    var step_filter: ?i32 = null;
    if (std.mem.indexOf(u8, query, "step=")) |idx| {
        const start = idx + 5;
        const end = std.mem.indexOfPos(u8, query, start, "&") orelse query.len;
        const step_str = query[start..end];
        step_filter = std.fmt.parseInt(i32, step_str, 10) catch null;
    }

    // Get logs from database
    const logs = try db.getWorkflowLogs(ctx.pool, ctx.allocator, run_id, step_filter);
    defer {
        for (logs) |log_entry| {
            ctx.allocator.free(log_entry.content);
        }
        ctx.allocator.free(logs);
    }

    // Return as plain text
    res.content_type = .TEXT;
    var writer = res.writer();

    for (logs) |log_entry| {
        try writer.writeAll(log_entry.content);
        try writer.writeAll("\n");
    }
}
