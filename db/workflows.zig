//! Workflows Data Access Object
//!
//! SQL operations for workflow_definitions, workflow_runs, workflow_jobs,
//! workflow_tasks, workflow_steps, workflow_logs, workflow_artifacts, and commit_statuses tables.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// Status codes matching Gitea's ActionStatus
pub const Status = struct {
    pub const unknown: i32 = 0;
    pub const success: i32 = 1;
    pub const failure: i32 = 2;
    pub const cancelled: i32 = 3;
    pub const skipped: i32 = 4;
    pub const waiting: i32 = 5;
    pub const running: i32 = 6;
    pub const blocked: i32 = 7;
};

// =============================================================================
// Types
// =============================================================================

pub const WorkflowRun = struct {
    id: i64,
    repository_id: i64,
    workflow_definition_id: ?i64,
    run_number: i64,
    title: []const u8,
    trigger_event: []const u8,
    trigger_user_id: ?i64,
    ref: ?[]const u8,
    commit_sha: ?[]const u8,
    status: i32,
    started_at: ?i64,
    stopped_at: ?i64,
    created_at: i64,
};

pub const WorkflowJob = struct {
    id: i64,
    run_id: i64,
    repository_id: i64,
    name: []const u8,
    job_id: []const u8,
    status: i32,
    attempt: i32,
    started_at: ?i64,
    stopped_at: ?i64,
};

pub const WorkflowTask = struct {
    id: i64,
    job_id: i64,
    runner_id: ?i64,
    attempt: i32,
    status: i32,
    repository_id: i64,
    commit_sha: ?[]const u8,
    started_at: ?i64,
    stopped_at: ?i64,
};

// =============================================================================
// Workflow Run Operations
// =============================================================================

pub fn createRun(
    pool: *Pool,
    repo_id: i64,
    workflow_def_id: ?i64,
    title: []const u8,
    trigger_event: []const u8,
    trigger_user_id: ?i64,
    ref: ?[]const u8,
    commit_sha: ?[]const u8,
) !i64 {
    // Get next run number
    const num_row = try pool.row(
        \\SELECT COALESCE(MAX(run_number), 0) + 1 FROM workflow_runs WHERE repository_id = $1
    , .{repo_id});

    const run_number = if (num_row) |r| r.get(i64, 0) else 1;

    const row = try pool.row(
        \\INSERT INTO workflow_runs (
        \\  repository_id, workflow_definition_id, run_number, title,
        \\  trigger_event, trigger_user_id, ref, commit_sha, status, created_at, updated_at
        \\) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())
        \\RETURNING id
    , .{ repo_id, workflow_def_id, run_number, title, trigger_event, trigger_user_id, ref, commit_sha, Status.waiting });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn getRun(pool: *Pool, run_id: i64) !?WorkflowRun {
    const row = try pool.row(
        \\SELECT id, repository_id, workflow_definition_id, run_number, title,
        \\       trigger_event, trigger_user_id, ref, commit_sha, status,
        \\       EXTRACT(EPOCH FROM started_at)::bigint,
        \\       EXTRACT(EPOCH FROM stopped_at)::bigint,
        \\       EXTRACT(EPOCH FROM created_at)::bigint
        \\FROM workflow_runs WHERE id = $1
    , .{run_id});

    if (row) |r| {
        return WorkflowRun{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .workflow_definition_id = r.get(?i64, 2),
            .run_number = r.get(i64, 3),
            .title = r.get([]const u8, 4),
            .trigger_event = r.get([]const u8, 5),
            .trigger_user_id = r.get(?i64, 6),
            .ref = r.get(?[]const u8, 7),
            .commit_sha = r.get(?[]const u8, 8),
            .status = r.get(i32, 9),
            .started_at = r.get(?i64, 10),
            .stopped_at = r.get(?i64, 11),
            .created_at = r.get(i64, 12),
        };
    }
    return null;
}

pub fn updateRunStatus(pool: *Pool, run_id: i64, status: i32) !void {
    if (status == Status.running) {
        _ = try pool.exec(
            \\UPDATE workflow_runs SET status = $2, started_at = NOW(), updated_at = NOW() WHERE id = $1
        , .{ run_id, status });
    } else if (status == Status.success or status == Status.failure or status == Status.cancelled) {
        _ = try pool.exec(
            \\UPDATE workflow_runs SET status = $2, stopped_at = NOW(), updated_at = NOW() WHERE id = $1
        , .{ run_id, status });
    } else {
        _ = try pool.exec(
            \\UPDATE workflow_runs SET status = $2, updated_at = NOW() WHERE id = $1
        , .{ run_id, status });
    }
}

pub fn listRuns(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64, limit: i64) ![]WorkflowRun {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, repository_id, workflow_definition_id, run_number, title,
        \\       trigger_event, trigger_user_id, ref, commit_sha, status,
        \\       EXTRACT(EPOCH FROM started_at)::bigint,
        \\       EXTRACT(EPOCH FROM stopped_at)::bigint,
        \\       EXTRACT(EPOCH FROM created_at)::bigint
        \\FROM workflow_runs WHERE repository_id = $1
        \\ORDER BY created_at DESC LIMIT $2
    , .{ repo_id, limit });
    defer result.deinit();

    var runs: std.ArrayList(WorkflowRun) = .{};
    while (try result.next()) |row| {
        try runs.append(allocator, WorkflowRun{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .workflow_definition_id = row.get(?i64, 2),
            .run_number = row.get(i64, 3),
            .title = row.get([]const u8, 4),
            .trigger_event = row.get([]const u8, 5),
            .trigger_user_id = row.get(?i64, 6),
            .ref = row.get(?[]const u8, 7),
            .commit_sha = row.get(?[]const u8, 8),
            .status = row.get(i32, 9),
            .started_at = row.get(?i64, 10),
            .stopped_at = row.get(?i64, 11),
            .created_at = row.get(i64, 12),
        });
    }

    return try runs.toOwnedSlice(allocator);
}

// =============================================================================
// Workflow Job Operations
// =============================================================================

pub fn createJob(
    pool: *Pool,
    run_id: i64,
    repo_id: i64,
    name: []const u8,
    job_id: []const u8,
) !i64 {
    const row = try pool.row(
        \\INSERT INTO workflow_jobs (run_id, repository_id, name, job_id, status, created_at, updated_at)
        \\VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
        \\RETURNING id
    , .{ run_id, repo_id, name, job_id, Status.waiting });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn updateJobStatus(pool: *Pool, job_id: i64, status: i32) !void {
    if (status == Status.running) {
        _ = try pool.exec(
            \\UPDATE workflow_jobs SET status = $2, started_at = NOW(), updated_at = NOW() WHERE id = $1
        , .{ job_id, status });
    } else if (status == Status.success or status == Status.failure or status == Status.cancelled) {
        _ = try pool.exec(
            \\UPDATE workflow_jobs SET status = $2, stopped_at = NOW(), updated_at = NOW() WHERE id = $1
        , .{ job_id, status });
    } else {
        _ = try pool.exec(
            \\UPDATE workflow_jobs SET status = $2, updated_at = NOW() WHERE id = $1
        , .{ job_id, status });
    }
}

// =============================================================================
// Workflow Task Operations
// =============================================================================

pub fn createTask(
    pool: *Pool,
    job_id: i64,
    repo_id: i64,
    commit_sha: ?[]const u8,
) !i64 {
    const row = try pool.row(
        \\INSERT INTO workflow_tasks (job_id, repository_id, commit_sha, status, created_at, updated_at)
        \\VALUES ($1, $2, $3, $4, NOW(), NOW())
        \\RETURNING id
    , .{ job_id, repo_id, commit_sha, Status.waiting });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn assignTaskToRunner(pool: *Pool, task_id: i64, runner_id: i64) !void {
    _ = try pool.exec(
        \\UPDATE workflow_tasks SET runner_id = $2, status = $3, started_at = NOW(), updated_at = NOW()
        \\WHERE id = $1
    , .{ task_id, runner_id, Status.running });
}

pub fn updateTaskStatus(pool: *Pool, task_id: i64, status: i32) !void {
    if (status == Status.success or status == Status.failure or status == Status.cancelled) {
        _ = try pool.exec(
            \\UPDATE workflow_tasks SET status = $2, stopped_at = NOW(), updated_at = NOW() WHERE id = $1
        , .{ task_id, status });
    } else {
        _ = try pool.exec(
            \\UPDATE workflow_tasks SET status = $2, updated_at = NOW() WHERE id = $1
        , .{ task_id, status });
    }
}

// =============================================================================
// Commit Status Operations
// =============================================================================

pub fn upsertCommitStatus(
    pool: *Pool,
    repo_id: i64,
    commit_sha: []const u8,
    context: []const u8,
    state: []const u8,
    description: ?[]const u8,
    target_url: ?[]const u8,
    workflow_run_id: ?i64,
) !void {
    _ = try pool.exec(
        \\INSERT INTO commit_statuses (repository_id, commit_sha, context, state, description, target_url, workflow_run_id, created_at, updated_at)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
        \\ON CONFLICT (repository_id, commit_sha, context) DO UPDATE SET
        \\  state = $4, description = $5, target_url = $6, workflow_run_id = $7, updated_at = NOW()
    , .{ repo_id, commit_sha, context, state, description, target_url, workflow_run_id });
}
