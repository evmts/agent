//! Commit Statuses Data Access Object
//!
//! SQL operations for commit_statuses table.
//! Tracks CI/workflow check results for commits.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const CommitStatus = struct {
    id: i64,
    repository_id: i64,
    commit_sha: []const u8,
    context: []const u8,
    state: []const u8,
    description: ?[]const u8,
    target_url: ?[]const u8,
    workflow_run_id: ?i64,
    created_at: i64,
    updated_at: i64,
};

// =============================================================================
// Query Operations
// =============================================================================

/// Get all statuses for a specific commit SHA
pub fn getByCommitSha(
    pool: *Pool,
    allocator: std.mem.Allocator,
    repository_id: i64,
    commit_sha: []const u8,
) ![]CommitStatus {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, repository_id, commit_sha, context, state, description, target_url,
        \\       workflow_run_id,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
        \\FROM commit_statuses
        \\WHERE repository_id = $1 AND commit_sha = $2
        \\ORDER BY created_at DESC
    , .{ repository_id, commit_sha });
    defer result.deinit();

    var statuses = std.ArrayList(CommitStatus){};
    errdefer statuses.deinit(allocator);

    while (try result.next()) |row| {
        try statuses.append(allocator, CommitStatus{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .commit_sha = row.get([]const u8, 2),
            .context = row.get([]const u8, 3),
            .state = row.get([]const u8, 4),
            .description = row.get(?[]const u8, 5),
            .target_url = row.get(?[]const u8, 6),
            .workflow_run_id = row.get(?i64, 7),
            .created_at = row.get(i64, 8),
            .updated_at = row.get(i64, 9),
        });
    }

    return try statuses.toOwnedSlice(allocator);
}

/// Get a specific status by repository, commit, and context
pub fn getByContext(
    pool: *Pool,
    repository_id: i64,
    commit_sha: []const u8,
    context: []const u8,
) !?CommitStatus {
    const row = try pool.row(
        \\SELECT id, repository_id, commit_sha, context, state, description, target_url,
        \\       workflow_run_id,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
        \\FROM commit_statuses
        \\WHERE repository_id = $1 AND commit_sha = $2 AND context = $3
    , .{ repository_id, commit_sha, context });

    if (row) |r| {
        return CommitStatus{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .commit_sha = r.get([]const u8, 2),
            .context = r.get([]const u8, 3),
            .state = r.get([]const u8, 4),
            .description = r.get(?[]const u8, 5),
            .target_url = r.get(?[]const u8, 6),
            .workflow_run_id = r.get(?i64, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
        };
    }
    return null;
}

/// Get aggregated status for a commit (returns overall state)
/// Priority: error > failure > pending > success
pub fn getAggregatedState(
    pool: *Pool,
    repository_id: i64,
    commit_sha: []const u8,
) !?[]const u8 {
    const row = try pool.row(
        \\SELECT
        \\  CASE
        \\    WHEN COUNT(*) FILTER (WHERE state = 'error') > 0 THEN 'error'
        \\    WHEN COUNT(*) FILTER (WHERE state = 'failure') > 0 THEN 'failure'
        \\    WHEN COUNT(*) FILTER (WHERE state = 'pending') > 0 THEN 'pending'
        \\    WHEN COUNT(*) > 0 THEN 'success'
        \\    ELSE NULL
        \\  END as state
        \\FROM commit_statuses
        \\WHERE repository_id = $1 AND commit_sha = $2
    , .{ repository_id, commit_sha });

    if (row) |r| {
        return r.get(?[]const u8, 0);
    }
    return null;
}

// =============================================================================
// Write Operations
// =============================================================================

/// Create or update a commit status (upsert by repository_id, commit_sha, context)
pub fn upsert(
    pool: *Pool,
    repository_id: i64,
    commit_sha: []const u8,
    context: []const u8,
    state: []const u8,
    description: ?[]const u8,
    target_url: ?[]const u8,
    workflow_run_id: ?i64,
) !CommitStatus {
    const row = try pool.row(
        \\INSERT INTO commit_statuses (repository_id, commit_sha, context, state, description, target_url, workflow_run_id)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7)
        \\ON CONFLICT (repository_id, commit_sha, context) DO UPDATE SET
        \\  state = EXCLUDED.state,
        \\  description = EXCLUDED.description,
        \\  target_url = EXCLUDED.target_url,
        \\  workflow_run_id = EXCLUDED.workflow_run_id,
        \\  updated_at = NOW()
        \\RETURNING id, repository_id, commit_sha, context, state, description, target_url,
        \\          workflow_run_id,
        \\          EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\          EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
    , .{ repository_id, commit_sha, context, state, description, target_url, workflow_run_id });

    if (row) |r| {
        return CommitStatus{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .commit_sha = r.get([]const u8, 2),
            .context = r.get([]const u8, 3),
            .state = r.get([]const u8, 4),
            .description = r.get(?[]const u8, 5),
            .target_url = r.get(?[]const u8, 6),
            .workflow_run_id = r.get(?i64, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
        };
    }
    return error.InsertFailed;
}

/// Delete a specific status
pub fn delete(
    pool: *Pool,
    repository_id: i64,
    commit_sha: []const u8,
    context: []const u8,
) !void {
    _ = try pool.exec(
        \\DELETE FROM commit_statuses
        \\WHERE repository_id = $1 AND commit_sha = $2 AND context = $3
    , .{ repository_id, commit_sha, context });
}

/// Delete all statuses for a commit
pub fn deleteAllForCommit(
    pool: *Pool,
    repository_id: i64,
    commit_sha: []const u8,
) !void {
    _ = try pool.exec(
        \\DELETE FROM commit_statuses
        \\WHERE repository_id = $1 AND commit_sha = $2
    , .{ repository_id, commit_sha });
}
