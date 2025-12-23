//! Milestones Data Access Object
//!
//! SQL operations for the milestones table.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const MilestoneRecord = struct {
    id: i64,
    repository_id: i64,
    title: []const u8,
    description: ?[]const u8,
    due_date: ?i64,
    state: []const u8,
    open_issues: i64,
    closed_issues: i64,
    created_at: i64,
    updated_at: i64,
    closed_at: ?i64,
};

// =============================================================================
// Operations
// =============================================================================

pub fn list(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64, state: ?[]const u8) ![]MilestoneRecord {
    var conn = try pool.acquire();
    defer conn.release();

    const query = if (state) |s|
        if (std.mem.eql(u8, s, "all"))
            \\SELECT m.id, m.repository_id, m.title, m.description,
            \\       EXTRACT(EPOCH FROM m.due_date)::bigint,
            \\       m.state,
            \\       (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'open') as open_issues,
            \\       (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'closed') as closed_issues,
            \\       EXTRACT(EPOCH FROM m.created_at)::bigint,
            \\       EXTRACT(EPOCH FROM m.updated_at)::bigint,
            \\       EXTRACT(EPOCH FROM m.closed_at)::bigint
            \\FROM milestones m
            \\WHERE m.repository_id = $1
            \\ORDER BY m.due_date ASC NULLS LAST, m.created_at DESC
        else
            \\SELECT m.id, m.repository_id, m.title, m.description,
            \\       EXTRACT(EPOCH FROM m.due_date)::bigint,
            \\       m.state,
            \\       (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'open') as open_issues,
            \\       (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'closed') as closed_issues,
            \\       EXTRACT(EPOCH FROM m.created_at)::bigint,
            \\       EXTRACT(EPOCH FROM m.updated_at)::bigint,
            \\       EXTRACT(EPOCH FROM m.closed_at)::bigint
            \\FROM milestones m
            \\WHERE m.repository_id = $1 AND m.state = $2
            \\ORDER BY m.due_date ASC NULLS LAST, m.created_at DESC
    else
        \\SELECT m.id, m.repository_id, m.title, m.description,
        \\       EXTRACT(EPOCH FROM m.due_date)::bigint,
        \\       m.state,
        \\       (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'open') as open_issues,
        \\       (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'closed') as closed_issues,
        \\       EXTRACT(EPOCH FROM m.created_at)::bigint,
        \\       EXTRACT(EPOCH FROM m.updated_at)::bigint,
        \\       EXTRACT(EPOCH FROM m.closed_at)::bigint
        \\FROM milestones m
        \\WHERE m.repository_id = $1 AND m.state = 'open'
        \\ORDER BY m.due_date ASC NULLS LAST, m.created_at DESC
    ;

    var result = if (state) |s|
        if (std.mem.eql(u8, s, "all"))
            try conn.query(query, .{repo_id})
        else
            try conn.query(query, .{ repo_id, s })
    else
        try conn.query(query, .{repo_id});
    defer result.deinit();

    var milestones: std.ArrayList(MilestoneRecord) = .{};
    while (try result.next()) |row| {
        try milestones.append(allocator, MilestoneRecord{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .title = row.get([]const u8, 2),
            .description = row.get(?[]const u8, 3),
            .due_date = row.get(?i64, 4),
            .state = row.get([]const u8, 5),
            .open_issues = row.get(i64, 6),
            .closed_issues = row.get(i64, 7),
            .created_at = row.get(i64, 8),
            .updated_at = row.get(i64, 9),
            .closed_at = row.get(?i64, 10),
        });
    }

    return try milestones.toOwnedSlice(allocator);
}

pub fn get(pool: *Pool, repo_id: i64, milestone_id: i64) !?MilestoneRecord {
    const row = try pool.row(
        \\SELECT m.id, m.repository_id, m.title, m.description,
        \\       EXTRACT(EPOCH FROM m.due_date)::bigint,
        \\       m.state,
        \\       (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'open') as open_issues,
        \\       (SELECT COUNT(*) FROM issues WHERE milestone_id = m.id AND state = 'closed') as closed_issues,
        \\       EXTRACT(EPOCH FROM m.created_at)::bigint,
        \\       EXTRACT(EPOCH FROM m.updated_at)::bigint,
        \\       EXTRACT(EPOCH FROM m.closed_at)::bigint
        \\FROM milestones m
        \\WHERE m.repository_id = $1 AND m.id = $2
    , .{ repo_id, milestone_id });

    if (row) |r| {
        return MilestoneRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .title = r.get([]const u8, 2),
            .description = r.get(?[]const u8, 3),
            .due_date = r.get(?i64, 4),
            .state = r.get([]const u8, 5),
            .open_issues = r.get(i64, 6),
            .closed_issues = r.get(i64, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
            .closed_at = r.get(?i64, 10),
        };
    }
    return null;
}

pub fn create(
    pool: *Pool,
    repo_id: i64,
    title: []const u8,
    description: ?[]const u8,
    due_date: ?i64,
) !MilestoneRecord {
    const row = if (due_date) |dd|
        try pool.row(
            \\INSERT INTO milestones (repository_id, title, description, due_date, created_at, updated_at)
            \\VALUES ($1, $2, $3, to_timestamp($4), NOW(), NOW())
            \\RETURNING id, repository_id, title, description,
            \\          EXTRACT(EPOCH FROM due_date)::bigint, state,
            \\          0 as open_issues, 0 as closed_issues,
            \\          EXTRACT(EPOCH FROM created_at)::bigint,
            \\          EXTRACT(EPOCH FROM updated_at)::bigint,
            \\          EXTRACT(EPOCH FROM closed_at)::bigint
        , .{ repo_id, title, description, dd })
    else
        try pool.row(
            \\INSERT INTO milestones (repository_id, title, description, created_at, updated_at)
            \\VALUES ($1, $2, $3, NOW(), NOW())
            \\RETURNING id, repository_id, title, description,
            \\          EXTRACT(EPOCH FROM due_date)::bigint, state,
            \\          0 as open_issues, 0 as closed_issues,
            \\          EXTRACT(EPOCH FROM created_at)::bigint,
            \\          EXTRACT(EPOCH FROM updated_at)::bigint,
            \\          EXTRACT(EPOCH FROM closed_at)::bigint
        , .{ repo_id, title, description });

    if (row) |r| {
        return MilestoneRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .title = r.get([]const u8, 2),
            .description = r.get(?[]const u8, 3),
            .due_date = r.get(?i64, 4),
            .state = r.get([]const u8, 5),
            .open_issues = r.get(i64, 6),
            .closed_issues = r.get(i64, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
            .closed_at = r.get(?i64, 10),
        };
    }
    return error.InsertFailed;
}

pub fn update(
    pool: *Pool,
    milestone_id: i64,
    title: ?[]const u8,
    description: ?[]const u8,
    due_date: ?i64,
) !void {
    if (title) |t| {
        _ = try pool.exec(
            \\UPDATE milestones SET title = $2, updated_at = NOW() WHERE id = $1
        , .{ milestone_id, t });
    }
    if (description) |d| {
        _ = try pool.exec(
            \\UPDATE milestones SET description = $2, updated_at = NOW() WHERE id = $1
        , .{ milestone_id, d });
    }
    if (due_date) |dd| {
        _ = try pool.exec(
            \\UPDATE milestones SET due_date = to_timestamp($2), updated_at = NOW() WHERE id = $1
        , .{ milestone_id, dd });
    }
}

pub fn close(pool: *Pool, milestone_id: i64) !void {
    _ = try pool.exec(
        \\UPDATE milestones SET state = 'closed', closed_at = NOW(), updated_at = NOW() WHERE id = $1
    , .{milestone_id});
}

pub fn reopen(pool: *Pool, milestone_id: i64) !void {
    _ = try pool.exec(
        \\UPDATE milestones SET state = 'open', closed_at = NULL, updated_at = NOW() WHERE id = $1
    , .{milestone_id});
}

pub fn delete(pool: *Pool, milestone_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM milestones WHERE id = $1
    , .{milestone_id});
}

pub fn setIssue(pool: *Pool, issue_id: i64, milestone_id: ?i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET milestone_id = $2, updated_at = NOW() WHERE id = $1
    , .{ issue_id, milestone_id });
}

// =============================================================================
// Backward-compatible functions (matching old db_issues signatures)
// =============================================================================

/// Full update with all fields (backward compatible with old db_issues.updateMilestone)
pub fn updateFull(
    pool: *Pool,
    repo_id: i64,
    milestone_id: i64,
    title: ?[]const u8,
    description: ?[]const u8,
    due_date: ?i64,
    state: ?[]const u8,
) !?MilestoneRecord {
    // Handle state change with closed_at timestamp
    if (state) |s| {
        const should_set_closed = std.mem.eql(u8, s, "closed");
        if (should_set_closed) {
            _ = try pool.exec(
                \\UPDATE milestones SET state = $3, closed_at = NOW(), updated_at = NOW()
                \\WHERE id = $1 AND repository_id = $2
            , .{ milestone_id, repo_id, s });
        } else {
            _ = try pool.exec(
                \\UPDATE milestones SET state = $3, closed_at = NULL, updated_at = NOW()
                \\WHERE id = $1 AND repository_id = $2
            , .{ milestone_id, repo_id, s });
        }
    }

    if (title) |t| {
        _ = try pool.exec(
            \\UPDATE milestones SET title = $3, updated_at = NOW()
            \\WHERE id = $1 AND repository_id = $2
        , .{ milestone_id, repo_id, t });
    }

    if (description) |d| {
        _ = try pool.exec(
            \\UPDATE milestones SET description = $3, updated_at = NOW()
            \\WHERE id = $1 AND repository_id = $2
        , .{ milestone_id, repo_id, d });
    }

    if (due_date) |dd| {
        _ = try pool.exec(
            \\UPDATE milestones SET due_date = to_timestamp($3), updated_at = NOW()
            \\WHERE id = $1 AND repository_id = $2
        , .{ milestone_id, repo_id, dd });
    }

    // Return the updated milestone
    return try get(pool, repo_id, milestone_id);
}

/// Delete by repo_id and milestone_id (backward compatible with old db_issues.deleteMilestone)
pub fn deleteByRepoAndId(pool: *Pool, repo_id: i64, milestone_id: i64) !bool {
    const result = try pool.exec(
        \\DELETE FROM milestones WHERE id = $1 AND repository_id = $2
    , .{ milestone_id, repo_id });
    return if (result) |r| r > 0 else false;
}

/// Assign milestone to issue by issue_number (backward compatible)
pub fn assignToIssue(pool: *Pool, repo_id: i64, issue_number: i64, milestone_id: i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET milestone_id = $3, updated_at = NOW()
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number, milestone_id });
}

/// Remove milestone from issue by issue_number (backward compatible)
pub fn removeFromIssue(pool: *Pool, repo_id: i64, issue_number: i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET milestone_id = NULL, updated_at = NOW()
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });
}
