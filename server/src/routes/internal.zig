//! Internal API Routes
//!
//! Endpoints for runner registration and task streaming.
//! These are called by K8s runner pods, not external clients.

const std = @import("std");
const httpz = @import("httpz");
const db = @import("db");
const queue = @import("../dispatch/queue.zig");
const json = @import("../lib/json.zig");

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

    const run_id: i32 = task_id;
    const session_id: ?[]const u8 = null;

    // Process event type and broadcast to WebSocket subscribers
    if (std.mem.eql(u8, event_type, "token") or std.mem.eql(u8, event_type, "llm_token")) {
        const text = if (root.get("text")) |v| v.string else if (root.get("token")) |v| v.string else "";
        const token_index = if (root.get("token_index")) |v| @as(usize, @intCast(v.integer)) else 0;
        const message_id = if (root.get("message_id")) |v| v.string else "";

        if (try resolveStepDbId(ctx.pool, run_id, &root)) |step_db_id| {
            appendWorkflowLog(ctx.pool, step_db_id, "token", text) catch |err| {
                log.err("Failed to store token log: {}", .{err});
            };
        }

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
        const args_value = root.get("args");

        if (session_id) |sid| {
            if (ctx.connection_manager) |cm| {
                cm.broadcastToolStart(sid, message_id, tool_id, tool_name);
            }
        }

        if (try resolveStepDbId(ctx.pool, run_id, &root)) |step_db_id| {
            var payload_obj = std.json.ObjectMap.init(ctx.allocator);
            defer payload_obj.deinit();
            try payload_obj.put("tool_id", .{ .string = tool_id });
            try payload_obj.put("tool_name", .{ .string = tool_name });
            if (args_value) |args| {
                try payload_obj.put("args", args);
            }

            const payload = try json.valueToString(ctx.allocator, .{ .object = payload_obj });
            defer ctx.allocator.free(payload);

            appendWorkflowLog(ctx.pool, step_db_id, "tool_call", payload) catch |err| {
                log.err("Failed to store tool_start log: {}", .{err});
            };
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

        if (try resolveStepDbId(ctx.pool, run_id, &root)) |step_db_id| {
            var payload_obj = std.json.ObjectMap.init(ctx.allocator);
            defer payload_obj.deinit();
            try payload_obj.put("tool_id", .{ .string = tool_id });
            try payload_obj.put("tool_state", .{ .string = tool_state });
            if (output) |out| {
                try payload_obj.put("output", .{ .string = out });
            }

            const payload = try json.valueToString(ctx.allocator, .{ .object = payload_obj });
            defer ctx.allocator.free(payload);

            appendWorkflowLog(ctx.pool, step_db_id, "tool_result", payload) catch |err| {
                log.err("Failed to store tool_end log: {}", .{err});
            };
        }
    } else if (std.mem.eql(u8, event_type, "step_start")) {
        if (try resolveStepDbId(ctx.pool, run_id, &root)) |step_db_id| {
            db.workflows.updateWorkflowStepStatus(ctx.pool, step_db_id, "running") catch |err| {
                log.err("Failed to mark step running: {}", .{err});
            };
        }
    } else if (std.mem.eql(u8, event_type, "step_end")) {
        const step_state = if (root.get("step_state")) |v| v.string else "success";
        const output_value = root.get("output");
        var output_json: ?[]const u8 = null;
        if (output_value) |val| {
            output_json = json.valueToString(ctx.allocator, val) catch null;
        }
        defer if (output_json) |val| ctx.allocator.free(val);

        if (try resolveStepDbId(ctx.pool, run_id, &root)) |step_db_id| {
            const failed = std.mem.eql(u8, step_state, "failure") or std.mem.eql(u8, step_state, "error");
            const error_message = if (failed and output_value != null) output_json else null;
            const exit_code: ?i32 = if (failed) 1 else 0;

            db.workflows.completeWorkflowStep(
                ctx.pool,
                step_db_id,
                exit_code,
                output_json,
                error_message,
                null,
                null,
                null,
            ) catch |err| {
                log.err("Failed to complete step: {}", .{err});
            };
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
        if (try resolveStepDbId(ctx.pool, run_id, &root)) |step_db_id| {
            const log_type = if (std.mem.eql(u8, level, "stderr") or std.mem.eql(u8, level, "error"))
                "stderr"
            else
                "stdout";
            appendWorkflowLog(ctx.pool, step_db_id, log_type, message) catch |err| {
                log.err("Failed to store log: {}", .{err});
            };
        }
    }

    try res.writer().writeAll("{\"ok\":true}");
}

fn resolveStepDbId(pool: *db.Pool, run_id: i32, root: *const std.json.ObjectMap) !?i32 {
    if (root.get("step_id")) |value| {
        if (value == .string) {
            const row = try pool.row(
                \\SELECT id FROM workflow_steps
                \\WHERE run_id = $1 AND step_id = $2
            , .{ run_id, value.string });
            if (row) |r| return r.get(i32, 0);
        }
    }

    const step_index_value = root.get("step_index") orelse root.get("stepIndex");
    if (step_index_value) |value| {
        if (value == .integer) {
            const row = try pool.row(
                \\SELECT id FROM workflow_steps
                \\WHERE run_id = $1
                \\ORDER BY id
                \\OFFSET $2 LIMIT 1
            , .{ run_id, @as(i32, @intCast(value.integer)) });
            if (row) |r| return r.get(i32, 0);
        }
    }

    return null;
}

fn appendWorkflowLog(pool: *db.Pool, step_id: i32, log_type: []const u8, content: []const u8) !void {
    const row = try pool.row(
        \\SELECT COALESCE(MAX(sequence), -1) + 1
        \\FROM workflow_logs
        \\WHERE step_id = $1
    , .{step_id});
    const sequence = if (row) |r| r.get(i32, 0) else 0;

    _ = try db.workflows.appendWorkflowLog(pool, step_id, log_type, content, sequence);
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
