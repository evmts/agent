//! Runner routes
//!
//! Handles workflow runner operations:
//! - POST /runners/register - Register a new runner
//! - POST /runners/heartbeat - Update runner heartbeat
//! - GET /runners/tasks/fetch - Fetch available task for execution
//! - POST /runners/tasks/:taskId/status - Update task status
//! - POST /runners/tasks/:taskId/logs - Append logs to task

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");
const workflows = @import("workflows.zig");

const log = std.log.scoped(.runner_routes);

/// Hash a token using SHA256
fn hashToken(allocator: std.mem.Allocator, token: []const u8) ![]const u8 {
    var hash_buf: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(token, &hash_buf, .{});
    const hex = std.fmt.bytesToHex(hash_buf, .lower);
    return try allocator.dupe(u8, &hex);
}

/// Extract bearer token from Authorization header
fn getRunnerToken(req: *httpz.Request) ?[]const u8 {
    const auth_header = req.header("authorization") orelse return null;
    if (!std.mem.startsWith(u8, auth_header, "Bearer ")) return null;
    return auth_header[7..];
}

/// Extract task token from X-Task-Token header
fn getTaskToken(req: *httpz.Request) ?[]const u8 {
    return req.header("x-task-token");
}

/// POST /runners/register
/// Register a new runner with the server
pub fn register(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        name: []const u8,
        version: ?[]const u8 = null,
        labels: ?[]const []const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.name.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Runner name is required\"}");
        return;
    }

    // Generate runner token
    var token_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&token_bytes);
    const hex = std.fmt.bytesToHex(token_bytes, .lower);
    const token = try ctx.allocator.dupe(u8, &hex);
    defer ctx.allocator.free(token);

    // Hash the token for storage
    const token_hash = try hashToken(ctx.allocator, token);
    defer ctx.allocator.free(token_hash);

    // Create runner in database
    const runner_id = try db.createRunner(
        ctx.pool,
        v.name,
        v.version,
        v.labels,
        token_hash,
    );

    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"runner":{{"id":{d},"name":"{s}","labels":[]}},"token":"{s}"}}
    , .{ runner_id, v.name, token });
}

/// POST /runners/heartbeat
/// Update runner status and last seen timestamp
pub fn heartbeat(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const token = getRunnerToken(req) orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Runner token required\"}");
        return;
    };

    // Hash token for lookup
    const token_hash = try hashToken(ctx.allocator, token);
    defer ctx.allocator.free(token_hash);

    // Verify runner exists
    const runner = try db.getRunnerByToken(ctx.pool, token_hash);
    if (runner == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Invalid runner token\"}");
        return;
    }

    // Update heartbeat
    try db.updateRunnerHeartbeat(ctx.pool, token_hash);

    try res.writer().writeAll("{\"ok\":true}");
}

/// GET /runners/tasks/fetch
/// Long-poll for an available task to execute
pub fn fetchTask(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const token = getRunnerToken(req) orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Runner token required\"}");
        return;
    };

    // Hash token for lookup
    const token_hash = try hashToken(ctx.allocator, token);
    defer ctx.allocator.free(token_hash);

    // Verify runner exists
    const runner = try db.getRunnerByToken(ctx.pool, token_hash);
    if (runner == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Invalid runner token\"}");
        return;
    }

    // Update heartbeat
    try db.updateRunnerHeartbeat(ctx.pool, token_hash);

    // Find available task
    const task = try db.findAvailableTask(ctx.pool, ctx.allocator, runner.?.id);
    if (task == null) {
        try res.writer().writeAll("{\"task\":null}");
        return;
    }
    defer if (task) |t| {
        ctx.allocator.free(t.workflow_content);
        ctx.allocator.free(t.workflow_path);
    };

    const t = task.?;

    // Generate task token
    var task_token_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&task_token_bytes);
    const task_hex = std.fmt.bytesToHex(task_token_bytes, .lower);
    const task_token = try ctx.allocator.dupe(u8, &task_hex);
    defer ctx.allocator.free(task_token);

    const task_token_hash = try hashToken(ctx.allocator, task_token);
    defer ctx.allocator.free(task_token_hash);

    // Update task with token and assign to runner
    try db.assignTaskToRunner(ctx.pool, t.id, runner.?.id, task_token_hash);

    // Build response
    var writer = res.writer();
    try writer.print(
        \\{{"task":{{"id":{d},"jobId":{d},"attempt":{d},"repositoryId":{d},"commitSha":
    , .{ t.id, t.job_id, t.attempt, t.repository_id });

    if (t.commit_sha) |sha| {
        try writer.print("\"{s}\"", .{sha});
    } else {
        try writer.writeAll("null");
    }

    const escaped_content = escapeJson(ctx.allocator, t.workflow_content) catch t.workflow_content;
    const escaped_path = escapeJson(ctx.allocator, t.workflow_path) catch t.workflow_path;

    try writer.print(
        \\,"workflowContent":"{s}","workflowPath":"{s}","token":"{s}"}}}}
    , .{ escaped_content, escaped_path, task_token });
}

/// POST /runners/tasks/:taskId/status
/// Update task execution status
pub fn updateTaskStatus(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const task_id_str = req.param("taskId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing taskId parameter\"}");
        return;
    };

    const task_id = std.fmt.parseInt(i64, task_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid taskId\"}");
        return;
    };

    const task_token = getTaskToken(req) orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Task token required\"}");
        return;
    };

    // Hash token for verification
    const token_hash = try hashToken(ctx.allocator, task_token);
    defer ctx.allocator.free(token_hash);

    // Verify task token
    var task = try db.getTaskByToken(ctx.pool, ctx.allocator, token_hash) orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Invalid task token\"}");
        return;
    };
    defer db.freeWorkflowTask(ctx.allocator, &task);

    if (task.id != task_id) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Invalid task token\"}");
        return;
    }

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        status: []const u8,
        stoppedAt: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const status = workflows.WorkflowStatus.fromString(parsed.value.status) orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid status\"}");
        return;
    };

    // Update task status (convert enum to i32)
    const status_int: i32 = @intFromEnum(status);
    try db.updateTaskStatus(ctx.pool, task_id, status_int);

    // If task is done, update job status too
    if (status == .success or status == .failure or status == .cancelled) {
        try db.updateJobStatusFromTask(ctx.pool, task.job_id, status_int);
    }

    try res.writer().writeAll("{\"ok\":true}");
}

/// POST /runners/tasks/:taskId/logs
/// Append log lines to a task step
pub fn appendLogs(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const task_id_str = req.param("taskId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing taskId parameter\"}");
        return;
    };

    const task_id = std.fmt.parseInt(i64, task_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid taskId\"}");
        return;
    };

    const task_token = getTaskToken(req) orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Task token required\"}");
        return;
    };

    // Hash token for verification
    const token_hash = try hashToken(ctx.allocator, task_token);
    defer ctx.allocator.free(token_hash);

    // Verify task token
    var task = try db.getTaskByToken(ctx.pool, ctx.allocator, token_hash) orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Invalid task token\"}");
        return;
    };
    defer db.freeWorkflowTask(ctx.allocator, &task);

    if (task.id != task_id) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Invalid task token\"}");
        return;
    }

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        stepIndex: i32,
        lines: []const []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    // Append logs to database
    try db.appendWorkflowLogs(ctx.pool, task_id, parsed.value.stepIndex, parsed.value.lines);

    try res.writer().writeAll("{\"ok\":true}");
}

/// Escape JSON strings (simple implementation)
fn escapeJson(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (s) |c| {
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
