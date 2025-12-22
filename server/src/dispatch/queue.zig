//! Task Queue Management
//!
//! Manages workload queue with warm pool runner assignment.
//! Provides <500ms assignment for interactive agents when runners are available.

const std = @import("std");
const db = @import("../lib/db.zig");

const log = std.log.scoped(.queue);

/// Workload type
pub const WorkloadType = enum {
    agent, // AI agent execution
    workflow, // Traditional CI workflow
};

/// Workload status
pub const WorkloadStatus = enum {
    pending, // Waiting for runner
    assigned, // Runner assigned, waiting to start
    running, // Executing
    completed, // Finished successfully
    failed, // Execution failed
    cancelled, // Cancelled by user
};

/// Priority levels
pub const Priority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
    critical = 3,
};

/// Workload submission request
pub const WorkloadRequest = struct {
    type: WorkloadType,
    workflow_run_id: ?i32,
    session_id: ?[]const u8,
    priority: Priority,
    config_json: ?[]const u8,
};

/// Runner information
pub const Runner = struct {
    id: i32,
    pod_name: []const u8,
    pod_ip: []const u8,
    status: RunnerStatus,
    registered_at: i64,
    last_heartbeat: i64,
};

pub const RunnerStatus = enum {
    available,
    claimed,
    terminated,
};

/// Submit a workload to the queue
pub fn submitWorkload(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    request: WorkloadRequest,
) !i32 {
    _ = allocator;

    log.info("Submitting workload: type={s}, priority={d}", .{
        @tagName(request.type),
        @intFromEnum(request.priority),
    });

    // Insert into workflow_tasks table
    const query =
        \\INSERT INTO workflow_tasks (
        \\    job_id, status, priority, workload_type,
        \\    session_id, config_json, created_at
        \\) VALUES (
        \\    (SELECT id FROM workflow_jobs WHERE run_id = $1 LIMIT 1),
        \\    'waiting', $2, $3, $4, $5, NOW()
        \\)
        \\RETURNING id
    ;

    const result = try pool.query(query, .{
        request.workflow_run_id,
        @intFromEnum(request.priority),
        @tagName(request.type),
        request.session_id,
        request.config_json,
    });
    defer result.deinit();

    if (try result.next()) |row| {
        const task_id = row.get(i32, 0);
        log.info("Created task {d}", .{task_id});

        // Try to immediately assign a warm runner
        tryAssignRunner(pool, task_id) catch |err| {
            log.debug("No warm runner available, task queued: {}", .{err});
        };

        return task_id;
    }

    return error.FailedToCreateTask;
}

/// Try to assign a warm runner to a task
pub fn tryAssignRunner(pool: *db.Pool, task_id: i32) !void {
    // Atomically claim an available runner
    const claim_query =
        \\WITH claimed AS (
        \\    SELECT id, pod_name, pod_ip
        \\    FROM runner_pool
        \\    WHERE status = 'available'
        \\    ORDER BY registered_at
        \\    FOR UPDATE SKIP LOCKED
        \\    LIMIT 1
        \\)
        \\UPDATE runner_pool r
        \\SET status = 'claimed',
        \\    claimed_at = NOW(),
        \\    claimed_by_task_id = $1
        \\FROM claimed c
        \\WHERE r.id = c.id
        \\RETURNING r.id, r.pod_name, r.pod_ip
    ;

    const result = try pool.query(claim_query, .{task_id});
    defer result.deinit();

    if (try result.next()) |row| {
        const runner_id = row.get(i32, 0);
        const pod_name = row.get([]const u8, 1);
        const pod_ip = row.get([]const u8, 2);

        log.info("Claimed runner {d} ({s}) for task {d}", .{
            runner_id,
            pod_name,
            task_id,
        });

        // Update task with runner assignment
        const update_query =
            \\UPDATE workflow_tasks
            \\SET runner_id = $1, status = 'assigned', assigned_at = NOW()
            \\WHERE id = $2
        ;
        _ = try pool.query(update_query, .{ runner_id, task_id });

        // Notify the runner to start (via HTTP callback)
        notifyRunner(pod_ip, task_id) catch |err| {
            log.err("Failed to notify runner: {}", .{err});
        };
    } else {
        return error.NoAvailableRunner;
    }
}

/// Notify a runner to start a task
fn notifyRunner(pod_ip: []const u8, task_id: i32) !void {
    // Make HTTP request to runner's assignment endpoint
    const allocator = std.heap.page_allocator;
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = try std.fmt.allocPrint(allocator, "http://{s}:8080/assign", .{pod_ip});
    defer allocator.free(url);

    const body = try std.fmt.allocPrint(allocator, "{{\"task_id\":{d}}}", .{task_id});
    defer allocator.free(body);

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = body,
        .headers = .{
            .content_type = .{ .override = "application/json" },
        },
    }) catch {
        return error.RunnerNotificationFailed;
    };

    if (result.status != .ok) {
        return error.RunnerNotificationFailed;
    }
}

/// Register a runner in the warm pool
pub fn registerRunner(
    pool: *db.Pool,
    pod_name: []const u8,
    pod_ip: []const u8,
) !i32 {
    log.info("Registering runner: {s} ({s})", .{ pod_name, pod_ip });

    // Upsert runner into pool
    const query =
        \\INSERT INTO runner_pool (pod_name, pod_ip, status, registered_at, last_heartbeat)
        \\VALUES ($1, $2, 'available', NOW(), NOW())
        \\ON CONFLICT (pod_name) DO UPDATE
        \\SET pod_ip = $2, status = 'available', last_heartbeat = NOW()
        \\RETURNING id
    ;

    const result = try pool.query(query, .{ pod_name, pod_ip });
    defer result.deinit();

    if (try result.next()) |row| {
        const runner_id = row.get(i32, 0);

        // Check if there are pending tasks
        tryAssignPendingTask(pool, runner_id) catch |err| {
            log.debug("No pending tasks for new runner: {}", .{err});
        };

        return runner_id;
    }

    return error.FailedToRegisterRunner;
}

/// Try to assign a pending task to a newly registered runner
fn tryAssignPendingTask(pool: *db.Pool, runner_id: i32) !void {
    const query =
        \\WITH pending AS (
        \\    SELECT id
        \\    FROM workflow_tasks
        \\    WHERE status = 'waiting' AND runner_id IS NULL
        \\    ORDER BY priority DESC, created_at
        \\    FOR UPDATE SKIP LOCKED
        \\    LIMIT 1
        \\)
        \\UPDATE workflow_tasks t
        \\SET runner_id = $1, status = 'assigned', assigned_at = NOW()
        \\FROM pending p
        \\WHERE t.id = p.id
        \\RETURNING t.id
    ;

    const result = try pool.query(query, .{runner_id});
    defer result.deinit();

    if (try result.next()) |row| {
        const task_id = row.get(i32, 0);
        log.info("Assigned pending task {d} to runner {d}", .{ task_id, runner_id });

        // Get runner IP and notify
        const ip_query = "SELECT pod_ip FROM runner_pool WHERE id = $1";
        const ip_result = try pool.query(ip_query, .{runner_id});
        defer ip_result.deinit();

        if (try ip_result.next()) |ip_row| {
            const pod_ip = ip_row.get([]const u8, 0);
            notifyRunner(pod_ip, task_id) catch |err| {
                log.err("Failed to notify runner: {}", .{err});
            };
        }
    }
}

/// Update runner heartbeat
pub fn updateHeartbeat(pool: *db.Pool, pod_name: []const u8) !void {
    const query =
        \\UPDATE runner_pool
        \\SET last_heartbeat = NOW()
        \\WHERE pod_name = $1
    ;
    _ = try pool.query(query, .{pod_name});
}

/// Mark task as completed
pub fn completeTask(pool: *db.Pool, task_id: i32, success: bool) !void {
    const status = if (success) "completed" else "failed";

    const query =
        \\UPDATE workflow_tasks
        \\SET status = $1, completed_at = NOW()
        \\WHERE id = $2
    ;
    _ = try pool.query(query, .{ status, task_id });

    // Release the runner back to the pool
    const release_query =
        \\UPDATE runner_pool
        \\SET status = 'available', claimed_at = NULL, claimed_by_task_id = NULL
        \\WHERE claimed_by_task_id = $1
    ;
    _ = try pool.query(release_query, .{task_id});

    log.info("Task {d} completed with status: {s}", .{ task_id, status });
}

/// Get pending task for runner (used in standby mode)
pub fn getPendingTaskForRunner(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    runner_id: i32,
) !?TaskAssignment {
    _ = allocator;

    const query =
        \\SELECT t.id, t.config_json, t.workload_type, t.session_id,
        \\       w.name as workflow_name
        \\FROM workflow_tasks t
        \\LEFT JOIN workflow_jobs j ON t.job_id = j.id
        \\LEFT JOIN workflow_runs r ON j.run_id = r.id
        \\LEFT JOIN workflow_definitions w ON r.workflow_definition_id = w.id
        \\WHERE t.runner_id = $1 AND t.status = 'assigned'
        \\LIMIT 1
    ;

    const result = try pool.query(query, .{runner_id});
    defer result.deinit();

    if (try result.next()) |row| {
        return .{
            .task_id = row.get(i32, 0),
            .config_json = row.get(?[]const u8, 1),
            .workload_type = row.get([]const u8, 2),
            .session_id = row.get(?[]const u8, 3),
            .workflow_name = row.get(?[]const u8, 4),
        };
    }

    return null;
}

pub const TaskAssignment = struct {
    task_id: i32,
    config_json: ?[]const u8,
    workload_type: []const u8,
    session_id: ?[]const u8,
    workflow_name: ?[]const u8,
};

// =============================================================================
// Tests
// =============================================================================

test "Priority ordering" {
    try std.testing.expect(@intFromEnum(Priority.high) > @intFromEnum(Priority.normal));
    try std.testing.expect(@intFromEnum(Priority.critical) > @intFromEnum(Priority.high));
}

test "WorkloadStatus enum" {
    const status: WorkloadStatus = .pending;
    try std.testing.expectEqual(WorkloadStatus.pending, status);
}
