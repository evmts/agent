//! Internal API Routes
//!
//! Endpoints for runner registration and task streaming.
//! These are called by K8s runner pods, not external clients.

const std = @import("std");
const httpz = @import("httpz");
const db = @import("../lib/db.zig");
const queue = @import("../dispatch/queue.zig");
const agent_handler = @import("../websocket/agent_handler.zig");

const log = std.log.scoped(.internal);

const Context = @import("../main.zig").Context;

// =============================================================================
// POST /internal/runners/register - Register a standby runner
// =============================================================================

pub fn registerRunner(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    const pod_name = if (root.get("pod_name")) |v| v.string else {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing pod_name\"}");
        return;
    };

    const pod_ip = if (root.get("pod_ip")) |v| v.string else {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing pod_ip\"}");
        return;
    };

    log.info("Registering runner: {s} ({s})", .{ pod_name, pod_ip });

    // Register runner and check for pending tasks
    const runner_id = queue.registerRunner(ctx.pool, pod_name, pod_ip) catch |err| {
        log.err("Failed to register runner: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to register runner\"}");
        return;
    };

    // Check if there's a pending task assigned
    const maybe_task = queue.getPendingTaskForRunner(allocator, ctx.pool, runner_id) catch null;
    if (maybe_task) |task| {
        // Return task assignment
        var writer = res.writer();
        try writer.writeAll("{\"runner_id\":");
        try writer.print("{d}", .{runner_id});
        try writer.writeAll(",\"task\":{\"id\":");
        try writer.print("{d}", .{task.task_id});
        try writer.writeAll(",\"type\":\"");
        try writer.writeAll(task.workload_type);
        try writer.writeAll("\"");
        if (task.config_json) |config| {
            try writer.writeAll(",\"config\":");
            try writer.writeAll(config);
        }
        if (task.session_id) |sid| {
            try writer.writeAll(",\"session_id\":\"");
            try writer.writeAll(sid);
            try writer.writeAll("\"");
        }
        try writer.writeAll("},\"callback_url\":\"");
        try writer.writeAll("https://api.plue.dev/internal/tasks/");
        try writer.print("{d}", .{task.task_id});
        try writer.writeAll("/stream\"}");
    } else {
        // No pending task, just acknowledge registration
        var writer = res.writer();
        try writer.writeAll("{\"runner_id\":");
        try writer.print("{d}", .{runner_id});
        try writer.writeAll(",\"task\":null}");
    }
}

// =============================================================================
// POST /internal/runners/:pod_name/heartbeat - Update runner heartbeat
// =============================================================================

pub fn runnerHeartbeat(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const pod_name = req.param("pod_name") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing pod_name\"}");
        return;
    };

    queue.updateHeartbeat(ctx.pool, pod_name) catch |err| {
        log.err("Failed to update heartbeat: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update heartbeat\"}");
        return;
    };

    try res.writer().writeAll("{\"ok\":true}");
}

// =============================================================================
// POST /internal/tasks/:task_id/stream - Receive streaming events from runner
// =============================================================================

pub fn streamTaskEvent(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const task_id_str = req.param("task_id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing task_id\"}");
        return;
    };

    const task_id = std.fmt.parseInt(i32, task_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid task_id\"}");
        return;
    };

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;
    const event_type = if (root.get("type")) |v| v.string else {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing event type\"}");
        return;
    };

    // Get session_id for this task to broadcast to WebSocket subscribers
    const session_id = getSessionIdForTask(ctx.pool, task_id) catch null;

    // Process event type and broadcast to WebSocket subscribers
    if (std.mem.eql(u8, event_type, "token")) {
        const text = if (root.get("text")) |v| v.string else "";
        const token_index = if (root.get("token_index")) |v| @as(usize, @intCast(v.integer)) else 0;
        const message_id = if (root.get("message_id")) |v| v.string else "";

        if (session_id) |sid| {
            if (ctx.connection_manager) |cm| {
                cm.broadcastToken(sid, message_id, text, token_index);
            }
        }

        // Persist to database (batch, not every token)
        // TODO: Implement batching
    } else if (std.mem.eql(u8, event_type, "tool_start")) {
        const tool_id = if (root.get("tool_id")) |v| v.string else "";
        const tool_name = if (root.get("tool_name")) |v| v.string else "";
        const message_id = if (root.get("message_id")) |v| v.string else "";

        if (session_id) |sid| {
            if (ctx.connection_manager) |cm| {
                cm.broadcastToolStart(sid, message_id, tool_id, tool_name);
            }
        }
    } else if (std.mem.eql(u8, event_type, "tool_end")) {
        const tool_id = if (root.get("tool_id")) |v| v.string else "";
        const tool_state = if (root.get("tool_state")) |v| v.string else "success";
        const output = if (root.get("output")) |v| v.string else null;

        if (session_id) |sid| {
            if (ctx.connection_manager) |cm| {
                cm.broadcastToolEnd(sid, tool_id, tool_state, output);
            }
        }
    } else if (std.mem.eql(u8, event_type, "done")) {
        // Mark task as completed
        queue.completeTask(ctx.pool, task_id, true) catch |err| {
            log.err("Failed to complete task: {}", .{err});
        };

        if (session_id) |sid| {
            if (ctx.connection_manager) |cm| {
                cm.broadcastDone(sid);
            }
        }
    } else if (std.mem.eql(u8, event_type, "error")) {
        const message = if (root.get("message")) |v| v.string else "Unknown error";

        // Mark task as failed
        queue.completeTask(ctx.pool, task_id, false) catch |err| {
            log.err("Failed to mark task as failed: {}", .{err});
        };

        if (session_id) |sid| {
            if (ctx.connection_manager) |cm| {
                cm.broadcastError(sid, message);
            }
        }
    } else if (std.mem.eql(u8, event_type, "log")) {
        // Store workflow log
        const level = if (root.get("level")) |v| v.string else "info";
        const message = if (root.get("message")) |v| v.string else "";

        storeWorkflowLog(ctx.pool, task_id, level, message) catch |err| {
            log.err("Failed to store log: {}", .{err});
        };
    }

    try res.writer().writeAll("{\"ok\":true}");
}

/// Get session_id for a task
fn getSessionIdForTask(pool: *db.Pool, task_id: i32) !?[]const u8 {
    const query = "SELECT session_id FROM workflow_tasks WHERE id = $1";
    const result = try pool.query(query, .{task_id});
    defer result.deinit();

    if (try result.next()) |row| {
        return row.get(?[]const u8, 0);
    }
    return null;
}

/// Store a workflow log entry
fn storeWorkflowLog(pool: *db.Pool, task_id: i32, level: []const u8, message: []const u8) !void {
    const query =
        \\INSERT INTO workflow_logs (task_id, level, message, created_at)
        \\VALUES ($1, $2, $3, NOW())
    ;
    _ = try pool.query(query, .{ task_id, level, message });
}

// =============================================================================
// POST /internal/tasks/:task_id/complete - Mark task as completed
// =============================================================================

pub fn completeTask(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const task_id_str = req.param("task_id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing task_id\"}");
        return;
    };

    const task_id = std.fmt.parseInt(i32, task_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid task_id\"}");
        return;
    };

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;
    const success = if (root.get("success")) |v| v.bool else false;

    queue.completeTask(ctx.pool, task_id, success) catch |err| {
        log.err("Failed to complete task: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to complete task\"}");
        return;
    };

    try res.writer().writeAll("{\"ok\":true}");
}

// =============================================================================
// Tests
// =============================================================================

test "internal routes compile" {
    _ = registerRunner;
    _ = runnerHeartbeat;
    _ = streamTaskEvent;
    _ = completeTask;
}
