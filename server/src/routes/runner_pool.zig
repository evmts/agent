//! Runner Pool API Routes
//!
//! Internal API endpoints for runner pool management:
//! - POST /internal/runners/register - Register a new runner in the pool
//! - POST /internal/runners/:runnerId/heartbeat - Update runner heartbeat
//! - GET /internal/runners/available - Get count of available runners
//! - GET /internal/runners - List all runners with optional status filter
//! - POST /internal/runners/:runnerId/terminate - Mark runner as terminated
//!
//! These endpoints are used by:
//! - Runner pods to register and send heartbeats
//! - Zig server internally to manage pool state
//! - Monitoring systems to track pool capacity

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const workflows = @import("../workflows/mod.zig");

const log = std.log.scoped(.runner_pool_routes);

/// POST /internal/runners/register
/// Register a new runner in the pool
pub fn register(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        pod_name: []const u8,
        pod_ip: []const u8,
        node_name: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.pod_name.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"pod_name is required\"}");
        return;
    }

    if (v.pod_ip.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"pod_ip is required\"}");
        return;
    }

    // Create runner pool instance
    var pool = workflows.RunnerPool.init(ctx.allocator, ctx.pool);

    // Register runner
    const runner_id = pool.registerRunner(v.pod_name, v.pod_ip, v.node_name) catch |err| {
        log.err("Failed to register runner {s}: {}", .{ v.pod_name, err });
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to register runner\"}");
        return;
    };

    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"runner_id":{d},"pod_name":"{s}","pod_ip":"{s}","status":"available"}}
    , .{ runner_id, v.pod_name, v.pod_ip });

    log.info("Runner registered: {s} (id={d}, ip={s})", .{ v.pod_name, runner_id, v.pod_ip });
}

/// POST /internal/runners/:runnerId/heartbeat
/// Update runner heartbeat timestamp
pub fn heartbeat(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const runner_id_str = req.param("runnerId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing runnerId parameter\"}");
        return;
    };

    const runner_id = std.fmt.parseInt(i32, runner_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid runnerId\"}");
        return;
    };

    // Create runner pool instance
    var pool = workflows.RunnerPool.init(ctx.allocator, ctx.pool);

    // Update heartbeat
    pool.updateHeartbeat(runner_id) catch |err| {
        if (err == error.RunnerNotFound) {
            res.status = 404;
            try res.writer().writeAll("{\"error\":\"Runner not found\"}");
            return;
        }

        log.err("Failed to update heartbeat for runner {d}: {}", .{ runner_id, err });
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update heartbeat\"}");
        return;
    };

    try res.writer().writeAll("{\"ok\":true}");
}

/// GET /internal/runners/available
/// Get count of available (healthy and unclaimed) runners
pub fn getAvailableCount(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Create runner pool instance
    var pool = workflows.RunnerPool.init(ctx.allocator, ctx.pool);

    const count = pool.getAvailableCount() catch |err| {
        log.err("Failed to count available runners: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to count available runners\"}");
        return;
    };

    var writer = res.writer();
    try writer.print(
        \\{{"available":{d}}}
    , .{count});
}

/// GET /internal/runners
/// List all runners with optional status filter
/// Query params: ?status=available|claimed|terminated
pub fn list(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const status_filter = req.query("status");

    // Create runner pool instance
    var pool = workflows.RunnerPool.init(ctx.allocator, ctx.pool);

    const runners = pool.listRunners(status_filter) catch |err| {
        log.err("Failed to list runners: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to list runners\"}");
        return;
    };
    defer ctx.allocator.free(runners);

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"runners\":[");

    for (runners, 0..) |runner, i| {
        if (i > 0) try writer.writeAll(",");

        try writer.print(
            \\{{"id":{d},"pod_name":"{s}","pod_ip":"{s}","status":"{s}","registered_at":{d},"last_heartbeat":{d}
        , .{ runner.id, runner.pod_name, runner.pod_ip, runner.status, runner.registered_at, runner.last_heartbeat });

        if (runner.node_name) |node| {
            try writer.print(",\"node_name\":\"{s}\"", .{node});
        } else {
            try writer.writeAll(",\"node_name\":null");
        }

        if (runner.claimed_at) |claimed| {
            try writer.print(",\"claimed_at\":{d}", .{claimed});
        } else {
            try writer.writeAll(",\"claimed_at\":null");
        }

        if (runner.claimed_by_task_id) |task_id| {
            try writer.print(",\"claimed_by_task_id\":{d}", .{task_id});
        } else {
            try writer.writeAll(",\"claimed_by_task_id\":null");
        }

        try writer.writeAll("}");
    }

    try writer.writeAll("]}");
}

/// POST /internal/runners/:runnerId/terminate
/// Mark a runner as terminated (removed from pool)
pub fn terminate(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const runner_id_str = req.param("runnerId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing runnerId parameter\"}");
        return;
    };

    const runner_id = std.fmt.parseInt(i32, runner_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid runnerId\"}");
        return;
    };

    // Create runner pool instance
    var pool = workflows.RunnerPool.init(ctx.allocator, ctx.pool);

    // Terminate runner
    pool.terminateRunner(runner_id) catch |err| {
        log.err("Failed to terminate runner {d}: {}", .{ runner_id, err });
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to terminate runner\"}");
        return;
    };

    log.info("Runner {d} marked as terminated", .{runner_id});
    try res.writer().writeAll("{\"ok\":true}");
}

/// POST /internal/runners/cleanup
/// Clean up stale runners (no heartbeat for > 60 seconds)
/// Returns count of runners marked as terminated
pub fn cleanup(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Create runner pool instance
    var pool = workflows.RunnerPool.init(ctx.allocator, ctx.pool);

    const count = pool.cleanupStaleRunners() catch |err| {
        log.err("Failed to cleanup stale runners: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to cleanup stale runners\"}");
        return;
    };

    log.info("Cleaned up {d} stale runners", .{count});

    var writer = res.writer();
    try writer.print(
        \\{{"cleaned_up":{d}}}
    , .{count});
}
