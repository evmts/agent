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
const db = @import("db");
const queue = @import("../dispatch/queue.zig");
const json = @import("../lib/json.zig");

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

fn mapRunStatusToLegacy(status: []const u8) []const u8 {
    if (std.mem.eql(u8, status, "completed")) return "success";
    if (std.mem.eql(u8, status, "failed")) return "failure";
    if (std.mem.eql(u8, status, "cancelled")) return "cancelled";
    if (std.mem.eql(u8, status, "running")) return "running";
    if (std.mem.eql(u8, status, "pending")) return "waiting";
    return "unknown";
}

fn mapLegacyStatusToRun(status: WorkflowStatus) []const u8 {
    return switch (status) {
        .success => "completed",
        .failure => "failed",
        .cancelled => "cancelled",
        .running => "running",
        .waiting => "pending",
        .skipped => "cancelled",
        .blocked => "pending",
        else => "pending",
    };
}

fn mapStepStatusToLegacy(status: []const u8) []const u8 {
    if (std.mem.eql(u8, status, "succeeded")) return "success";
    if (std.mem.eql(u8, status, "failed")) return "failure";
    if (std.mem.eql(u8, status, "cancelled")) return "cancelled";
    if (std.mem.eql(u8, status, "running")) return "running";
    if (std.mem.eql(u8, status, "pending")) return "waiting";
    if (std.mem.eql(u8, status, "skipped")) return "skipped";
    return "unknown";
}

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

    var status_filter: ?[]const u8 = null;
    if (status_str) |s| {
        if (WorkflowStatus.fromString(s)) |parsed| {
            status_filter = mapLegacyStatusToRun(parsed);
        }
    }

    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT r.id, r.status, r.trigger_type, w.name,
        \\       to_char(r.created_at, 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') as created_at
        \\FROM workflow_runs r
        \\JOIN workflow_definitions w ON r.workflow_definition_id = w.id
        \\WHERE w.repository_id = $1
        \\  AND ($2::text IS NULL OR r.status = $2)
        \\ORDER BY r.created_at DESC
        \\LIMIT $3 OFFSET $4
    , .{ repo_id.?, status_filter, per_page, offset });
    defer result.deinit();

    const Row = struct {
        id: i32,
        status: []const u8,
        trigger_type: []const u8,
        name: []const u8,
        created_at: []const u8,
    };

    var runs = std.ArrayList(Row){};
    defer runs.deinit(ctx.allocator);

    while (try result.next()) |row| {
        try runs.append(ctx.allocator, .{
            .id = row.get(i32, 0),
            .status = row.get([]const u8, 1),
            .trigger_type = row.get([]const u8, 2),
            .name = row.get([]const u8, 3),
            .created_at = row.get([]const u8, 4),
        });
    }

    var writer = res.writer();
    try writer.writeAll("{\"runs\":[");

    for (runs.items, 0..) |run, i| {
        if (i > 0) try writer.writeAll(",");
        const status = mapRunStatusToLegacy(run.status);
        try writer.print(
            \\{{"id":{d},"runNumber":{d},"title":"{s}","status":"{s}","triggerEvent":"{s}","createdAt":"{s}"}}
        , .{
            run.id,
            run.id,
            run.name,
            status,
            run.trigger_type,
            run.created_at,
        });
    }

    try writer.print("],\"page\":{d},\"perPage\":{d}}}", .{ page, per_page });
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

    const run_id = std.fmt.parseInt(i32, run_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid runId\"}");
        return;
    };

    // Get repository ID
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

    const repo_id = try db.getRepositoryId(ctx.pool, username, repo_name);
    if (repo_id == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    var conn = try ctx.pool.acquire();
    defer conn.release();

    const row = try conn.row(
        \\SELECT r.id, r.status, r.trigger_type, w.name,
        \\       to_char(r.created_at, 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') as created_at
        \\FROM workflow_runs r
        \\JOIN workflow_definitions w ON r.workflow_definition_id = w.id
        \\WHERE r.id = $1 AND w.repository_id = $2
    , .{ run_id, repo_id.? });

    if (row == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Workflow run not found\"}");
        return;
    }

    const run_status = row.?.get([]const u8, 1);
    const run_title = row.?.get([]const u8, 3);
    const trigger_event = row.?.get([]const u8, 2);
    const created_at = row.?.get([]const u8, 4);

    const jobs = try db.workflows.listWorkflowSteps(ctx.pool, ctx.allocator, @intCast(run_id));
    defer ctx.allocator.free(jobs);

    var writer = res.writer();
    try writer.print(
        \\{{"run":{{"id":{d},"runNumber":{d},"title":"{s}","status":"{s}","triggerEvent":"{s}","createdAt":"{s}"}},"jobs":[
    , .{
        row.?.get(i32, 0),
        row.?.get(i32, 0),
        run_title,
        mapRunStatusToLegacy(run_status),
        trigger_event,
        created_at,
    });

    for (jobs, 0..) |job, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":{d},"name":"{s}","jobId":"{s}","status":"{s}"}}
        , .{
            job.id,
            job.name,
            job.step_id,
            mapStepStatusToLegacy(job.status),
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

    const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    var workflow_def_id: ?i32 = null;
    if (root.get("workflow_definition_id")) |val| {
        workflow_def_id = @intCast(val.integer);
    } else if (root.get("workflowDefinitionId")) |val| {
        workflow_def_id = @intCast(val.integer);
    }

    if (workflow_def_id == null) {
        if (root.get("workflow_name")) |name_val| {
            const workflow_def = try db.workflows.getWorkflowDefinitionByName(ctx.pool, @as(?i32, @intCast(repo_id.?)), name_val.string);
            if (workflow_def) |def| {
                workflow_def_id = def.id;
            }
        }
    }

    if (workflow_def_id == null) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing workflow_definition_id\"}");
        return;
    }

    const trigger_type = if (root.get("trigger_type")) |val|
        val.string
    else if (root.get("triggerEvent")) |val|
        val.string
    else
        "manual";

    var trigger_payload_json: []const u8 = "{}";
    var owns_trigger_payload = false;
    if (root.get("trigger_payload")) |val| {
        trigger_payload_json = json.valueToString(ctx.allocator, val) catch {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Invalid trigger_payload\"}");
            return;
        };
        owns_trigger_payload = true;
    } else if (root.get("triggerPayload")) |val| {
        trigger_payload_json = json.valueToString(ctx.allocator, val) catch {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Invalid trigger_payload\"}");
            return;
        };
        owns_trigger_payload = true;
    }
    defer if (owns_trigger_payload) ctx.allocator.free(trigger_payload_json);

    var inputs_json: ?[]const u8 = null;
    if (root.get("inputs")) |inputs_value| {
        inputs_json = json.valueToString(ctx.allocator, inputs_value) catch {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Invalid inputs\"}");
            return;
        };
    }
    defer if (inputs_json) |val| ctx.allocator.free(val);

    const run_id = try db.workflows.createWorkflowRun(
        ctx.pool,
        workflow_def_id,
        trigger_type,
        trigger_payload_json,
        inputs_json,
    );

    _ = queue.submitWorkload(ctx.allocator, ctx.pool, .{
        .type = .workflow,
        .workflow_run_id = run_id,
        .session_id = null,
        .priority = .normal,
        .config_json = null,
    }) catch |err| {
        log.err("Failed to queue workflow run {d}: {}", .{ run_id, err });
    };

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

    const run_id = std.fmt.parseInt(i32, run_id_str, 10) catch {
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
    try db.workflows.updateWorkflowRunStatus(ctx.pool, run_id, mapLegacyStatusToRun(status));

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

    const run_id = std.fmt.parseInt(i32, run_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid runId\"}");
        return;
    };

    // Get run to check current status
    const run = try db.workflows.getWorkflowRun(ctx.pool, run_id);
    if (run == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Workflow run not found\"}");
        return;
    }

    const r = run.?;
    const current_status = r.status;

    // Can only cancel running or waiting workflows
    if (!std.mem.eql(u8, current_status, "running") and !std.mem.eql(u8, current_status, "pending")) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Cannot cancel completed workflow\"}");
        return;
    }

    // Update to cancelled
    try db.workflows.updateWorkflowRunStatus(ctx.pool, run_id, "cancelled");

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

    const run_id = std.fmt.parseInt(i32, run_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid runId\"}");
        return;
    };

    // Get steps as jobs
    const jobs = try db.workflows.listWorkflowSteps(ctx.pool, ctx.allocator, run_id);
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
            job.step_id,
            mapStepStatusToLegacy(job.status),
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

    const run_id = std.fmt.parseInt(i32, run_id_str, 10) catch {
        res.status = 400;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Invalid runId\"}");
        return;
    };

    // Parse optional step filter
    const query = req.url.query;
    var step_filter: ?[]const u8 = null;
    if (std.mem.indexOf(u8, query, "step=")) |idx| {
        const start = idx + 5;
        const end = std.mem.indexOfPos(u8, query, start, "&") orelse query.len;
        const step_str = query[start..end];
        step_filter = step_str;
    }

    var step_db_id: ?i32 = null;
    if (step_filter) |step_str| {
        if (std.fmt.parseInt(i32, step_str, 10) catch null) |step_index| {
            const row = try ctx.pool.row(
                \\SELECT id FROM workflow_steps
                \\WHERE run_id = $1
                \\ORDER BY id
                \\OFFSET $2 LIMIT 1
            , .{ run_id, step_index });
            if (row) |r| {
                step_db_id = r.get(i32, 0);
            }
        } else {
            const row = try ctx.pool.row(
                \\SELECT id FROM workflow_steps
                \\WHERE run_id = $1 AND step_id = $2
            , .{ run_id, step_str });
            if (row) |r| {
                step_db_id = r.get(i32, 0);
            }
        }
    }

    if (step_filter != null and step_db_id == null) {
        res.content_type = .TEXT;
        return;
    }

    const logs = if (step_db_id) |step_id|
        try db.workflows.listWorkflowLogs(ctx.pool, ctx.allocator, step_id)
    else
        try db.workflows.listWorkflowLogsForRunSince(ctx.pool, ctx.allocator, run_id, 0);
    defer ctx.allocator.free(logs);

    // Return as plain text
    res.content_type = .TEXT;
    var writer = res.writer();

    for (logs) |log_entry| {
        try writer.writeAll(log_entry.content);
        try writer.writeAll("\n");
    }
}
