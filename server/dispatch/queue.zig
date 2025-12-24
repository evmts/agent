//! Task Queue Management
//!
//! Manages workload queue with warm pool runner assignment.
//! Provides <500ms assignment for interactive agents when runners are available.

const std = @import("std");
const db = @import("db");
const workflows = @import("../workflows/mod.zig");

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
    log.info("Submitting workload: type={s}, priority={d}", .{
        @tagName(request.type),
        @intFromEnum(request.priority),
    });

    // TODO(workflows): Implement proper task queue with workflow_tasks table
    // For MVP, we just update the workflow_run status to indicate it's queued
    // In production, this would:
    // 1. Create workflow_tasks records for each step in the workflow plan
    // 2. Assign to warm pool runners or create K8s Jobs
    // 3. Return the task_id for tracking

    const run_id = request.workflow_run_id orelse return error.MissingWorkflowRunId;

    // Update workflow_run to "running" status
    const query =
        \\UPDATE workflow_runs
        \\SET status = 'running', started_at = NOW()
        \\WHERE id = $1
        \\RETURNING id
    ;

    const result = try pool.query(query, .{run_id});
    defer result.deinit();

    if (try result.next()) |row| {
        const task_id = row.get(i32, 0);
        log.info("Queued workflow run {d} (simulated task_id={d})", .{ run_id, task_id });

        // For MVP local development: execute synchronously in the request thread.
        // This avoids connection pool exhaustion that occurs when a detached thread
        // competes with HTTP request handlers for the limited connection pool.
        // In production, this would use: tryAssignRunner(pool, task_id)
        //
        // Note: Synchronous execution blocks the HTTP response until the workflow
        // completes, but for local dev this is acceptable and more reliable.
        executeWorkflowAsync(allocator, pool, run_id);

        return task_id; // Return run_id as task_id for now
    }

    return error.FailedToCreateTask;
}

/// Execute a workflow asynchronously (for local development)
fn executeWorkflowAsync(parent_allocator: std.mem.Allocator, pool: *db.Pool, run_id: i32) void {
    // Create a thread-local arena allocator for this execution
    // This ensures thread safety and makes cleanup easier
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    executeWorkflow(allocator, pool, run_id) catch |err| {
        log.err("Workflow execution failed for run_id={d}: {}", .{ run_id, err });

        // Mark workflow as failed
        const fail_query =
            \\UPDATE workflow_runs
            \\SET status = 'failed', completed_at = NOW(), error_message = $1
            \\WHERE id = $2
        ;
        const err_msg = @errorName(err);
        _ = pool.query(fail_query, .{ err_msg, run_id }) catch |query_err| {
            log.err("Failed to update workflow status: {}", .{query_err});
        };
    };
    // Arena allocator automatically frees all memory when this function returns
}

/// Execute a workflow (synchronous)
fn executeWorkflow(allocator: std.mem.Allocator, pool: *db.Pool, run_id: i32) !void {
    log.info("Starting workflow execution for run_id={d}", .{run_id});

    // 1. Get the workflow run to find the workflow_definition_id
    const run_query =
        \\SELECT workflow_definition_id
        \\FROM workflow_runs
        \\WHERE id = $1
    ;

    const run_result = try pool.query(run_query, .{run_id});
    defer run_result.deinit();

    const workflow_def_id = if (try run_result.next()) |row|
        row.get(i32, 0)
    else
        return error.WorkflowRunNotFound;

    log.info("Found workflow_definition_id={d}", .{workflow_def_id});

    // 2. Get the workflow definition (includes the plan JSON)
    const workflow_def_opt = try db.workflows.getWorkflowDefinition(pool, workflow_def_id);
    const workflow_def = workflow_def_opt orelse return error.WorkflowDefinitionNotFound;

    log.info("Loaded workflow definition: {s}", .{workflow_def.name});
    log.info("Plan JSON length: {d} bytes", .{workflow_def.plan.len});
    log.info("Plan JSON: {s}", .{workflow_def.plan});

    // 3. Parse the plan JSON
    const parsed = std.json.parseFromSlice(
        workflows.plan.WorkflowDefinition,
        allocator,
        workflow_def.plan,
        .{ .ignore_unknown_fields = true }, // Ignore unknown fields for now
    ) catch |err| {
        log.err("Failed to parse plan JSON: {}", .{err});
        log.err("Plan JSON was: {s}", .{workflow_def.plan});
        return err;
    };
    defer parsed.deinit();

    const workflow_plan = parsed.value;

    log.info("Parsed workflow plan: {s}, steps={d}", .{ workflow_plan.name, workflow_plan.steps.len });

    // 4. Initialize executor
    var exec = workflows.Executor.init(allocator, pool, run_id);

    // 5. Execute workflow
    const results = try exec.execute(&workflow_plan, run_id);
    defer {
        for (results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(results);
    }

    // 6. Determine overall success
    var all_succeeded = true;
    for (results) |result| {
        if (result.status != .succeeded and result.status != .skipped) {
            all_succeeded = false;
            break;
        }
    }

    // 7. Update workflow_run status
    const status = if (all_succeeded) "completed" else "failed";
    const complete_query =
        \\UPDATE workflow_runs
        \\SET status = $1, completed_at = NOW()
        \\WHERE id = $2
    ;
    _ = try pool.query(complete_query, .{ status, run_id });

    log.info("Workflow execution completed: run_id={d}, status={s}", .{ run_id, status });
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
        return runner_id;
    }

    return error.FailedToRegisterRunner;
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
        \\UPDATE workflow_runs
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
    _ = pool;
    _ = runner_id;
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
