//! Issues Data Access Object
//!
//! SQL operations for issues, comments, issue_assignees, issue_events, issue_dependencies, and pinned_issues tables.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;
pub const Conn = pg.Conn;

// =============================================================================
// Types
// =============================================================================

pub const IssueRecord = struct {
    id: i64,
    repository_id: i64,
    author_id: i64,
    issue_number: i64,
    title: []const u8,
    body: ?[]const u8,
    state: []const u8,
    milestone_id: ?i64,
    created_at: i64, // Unix timestamp
    updated_at: i64,
    closed_at: ?i64,
};

pub const CommentRecord = struct {
    id: i64,
    issue_id: i64,
    author_id: i64,
    body: []const u8,
    created_at: i64,
    updated_at: i64,
    edited: bool,
};

pub const DependencyRecord = struct {
    id: i64,
    blocker_issue_id: i64,
    blocked_issue_id: i64,
    blocker_number: i64,
    blocked_number: i64,
};

// =============================================================================
// Issue Operations
// =============================================================================

pub fn list(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64, state: ?[]const u8) ![]IssueRecord {
    var conn = try pool.acquire();
    defer conn.release();

    const query = if (state) |s|
        if (std.mem.eql(u8, s, "all"))
            \\SELECT id, repository_id, author_id, issue_number, title, body, state, milestone_id,
            \\       EXTRACT(EPOCH FROM created_at)::bigint, EXTRACT(EPOCH FROM updated_at)::bigint,
            \\       EXTRACT(EPOCH FROM closed_at)::bigint
            \\FROM issues WHERE repository_id = $1 ORDER BY issue_number DESC
        else
            \\SELECT id, repository_id, author_id, issue_number, title, body, state, milestone_id,
            \\       EXTRACT(EPOCH FROM created_at)::bigint, EXTRACT(EPOCH FROM updated_at)::bigint,
            \\       EXTRACT(EPOCH FROM closed_at)::bigint
            \\FROM issues WHERE repository_id = $1 AND state = $2 ORDER BY issue_number DESC
    else
        \\SELECT id, repository_id, author_id, issue_number, title, body, state, milestone_id,
        \\       EXTRACT(EPOCH FROM created_at)::bigint, EXTRACT(EPOCH FROM updated_at)::bigint,
        \\       EXTRACT(EPOCH FROM closed_at)::bigint
        \\FROM issues WHERE repository_id = $1 AND state = 'open' ORDER BY issue_number DESC
    ;

    var result = if (state) |s|
        if (std.mem.eql(u8, s, "all"))
            try conn.query(query, .{repo_id})
        else
            try conn.query(query, .{ repo_id, s })
    else
        try conn.query(query, .{repo_id});
    defer result.deinit();

    var issues: std.ArrayList(IssueRecord) = .{};
    while (try result.next()) |row| {
        try issues.append(allocator, IssueRecord{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .author_id = row.get(i64, 2),
            .issue_number = row.get(i64, 3),
            .title = row.get([]const u8, 4),
            .body = row.get(?[]const u8, 5),
            .state = row.get([]const u8, 6),
            .milestone_id = row.get(?i64, 7),
            .created_at = row.get(i64, 8),
            .updated_at = row.get(i64, 9),
            .closed_at = row.get(?i64, 10),
        });
    }

    return try issues.toOwnedSlice(allocator);
}

pub fn get(pool: *Pool, repo_id: i64, issue_number: i64) !?IssueRecord {
    const row = try pool.row(
        \\SELECT id, repository_id, author_id, issue_number, title, body, state, milestone_id,
        \\       EXTRACT(EPOCH FROM created_at)::bigint, EXTRACT(EPOCH FROM updated_at)::bigint,
        \\       EXTRACT(EPOCH FROM closed_at)::bigint
        \\FROM issues WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });

    if (row) |r| {
        return IssueRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .issue_number = r.get(i64, 3),
            .title = r.get([]const u8, 4),
            .body = r.get(?[]const u8, 5),
            .state = r.get([]const u8, 6),
            .milestone_id = r.get(?i64, 7),
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
    author_id: i64,
    title: []const u8,
    body: ?[]const u8,
) !IssueRecord {
    // Get next issue number atomically using database function
    const num_row = try pool.row(
        \\SELECT get_next_issue_number($1)
    , .{repo_id});

    const issue_number = if (num_row) |r| r.get(i64, 0) else return error.FailedToGetIssueNumber;

    const row = try pool.row(
        \\INSERT INTO issues (repository_id, author_id, issue_number, title, body, created_at, updated_at)
        \\VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
        \\RETURNING id, repository_id, author_id, issue_number, title, body, state, milestone_id,
        \\          EXTRACT(EPOCH FROM created_at)::bigint, EXTRACT(EPOCH FROM updated_at)::bigint,
        \\          EXTRACT(EPOCH FROM closed_at)::bigint
    , .{ repo_id, author_id, issue_number, title, body orelse "" });

    if (row) |r| {
        return IssueRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .issue_number = r.get(i64, 3),
            .title = r.get([]const u8, 4),
            .body = r.get(?[]const u8, 5),
            .state = r.get([]const u8, 6),
            .milestone_id = r.get(?i64, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
            .closed_at = r.get(?i64, 10),
        };
    }
    return error.InsertFailed;
}

pub fn update(
    pool: *Pool,
    repo_id: i64,
    issue_number: i64,
    title: ?[]const u8,
    body: ?[]const u8,
) !IssueRecord {
    const row = if (title != null and body != null)
        try pool.row(
            \\UPDATE issues SET title = $3, body = $4, updated_at = NOW()
            \\WHERE repository_id = $1 AND issue_number = $2
            \\RETURNING id, repository_id, author_id, issue_number, title, body, state, milestone_id,
            \\          EXTRACT(EPOCH FROM created_at)::bigint, EXTRACT(EPOCH FROM updated_at)::bigint,
            \\          EXTRACT(EPOCH FROM closed_at)::bigint
        , .{ repo_id, issue_number, title.?, body.? })
    else if (title != null)
        try pool.row(
            \\UPDATE issues SET title = $3, updated_at = NOW()
            \\WHERE repository_id = $1 AND issue_number = $2
            \\RETURNING id, repository_id, author_id, issue_number, title, body, state, milestone_id,
            \\          EXTRACT(EPOCH FROM created_at)::bigint, EXTRACT(EPOCH FROM updated_at)::bigint,
            \\          EXTRACT(EPOCH FROM closed_at)::bigint
        , .{ repo_id, issue_number, title.? })
    else if (body != null)
        try pool.row(
            \\UPDATE issues SET body = $3, updated_at = NOW()
            \\WHERE repository_id = $1 AND issue_number = $2
            \\RETURNING id, repository_id, author_id, issue_number, title, body, state, milestone_id,
            \\          EXTRACT(EPOCH FROM created_at)::bigint, EXTRACT(EPOCH FROM updated_at)::bigint,
            \\          EXTRACT(EPOCH FROM closed_at)::bigint
        , .{ repo_id, issue_number, body.? })
    else
        return error.NoFieldsToUpdate;

    if (row) |r| {
        return IssueRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .issue_number = r.get(i64, 3),
            .title = r.get([]const u8, 4),
            .body = r.get(?[]const u8, 5),
            .state = r.get([]const u8, 6),
            .milestone_id = r.get(?i64, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
            .closed_at = r.get(?i64, 10),
        };
    }
    return error.UpdateFailed;
}

pub fn close(pool: *Pool, repo_id: i64, issue_number: i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET state = 'closed', closed_at = NOW(), updated_at = NOW()
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });
}

pub fn reopen(pool: *Pool, repo_id: i64, issue_number: i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET state = 'open', closed_at = NULL, updated_at = NOW()
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });
}

pub fn getCounts(pool: *Pool, repo_id: i64) !struct { open: i64, closed: i64 } {
    const row = try pool.row(
        \\SELECT
        \\  COUNT(*) FILTER (WHERE state = 'open') as open_count,
        \\  COUNT(*) FILTER (WHERE state = 'closed') as closed_count
        \\FROM issues WHERE repository_id = $1
    , .{repo_id});

    if (row) |r| {
        return .{
            .open = r.get(i64, 0),
            .closed = r.get(i64, 1),
        };
    }
    return .{ .open = 0, .closed = 0 };
}

// =============================================================================
// Comment Operations
// =============================================================================

pub fn getComments(pool: *Pool, allocator: std.mem.Allocator, issue_id: i64) ![]CommentRecord {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, issue_id, author_id, body,
        \\       EXTRACT(EPOCH FROM created_at)::bigint,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint,
        \\       edited
        \\FROM comments WHERE issue_id = $1 ORDER BY created_at ASC
    , .{issue_id});
    defer result.deinit();

    var comments: std.ArrayList(CommentRecord) = .{};
    while (try result.next()) |row| {
        try comments.append(allocator, CommentRecord{
            .id = row.get(i64, 0),
            .issue_id = row.get(i64, 1),
            .author_id = row.get(i64, 2),
            .body = row.get([]const u8, 3),
            .created_at = row.get(i64, 4),
            .updated_at = row.get(i64, 5),
            .edited = row.get(bool, 6),
        });
    }

    return try comments.toOwnedSlice(allocator);
}

pub fn addComment(pool: *Pool, issue_id: i64, author_id: i64, body: []const u8) !CommentRecord {
    const row = try pool.row(
        \\INSERT INTO comments (issue_id, author_id, body, created_at, updated_at)
        \\VALUES ($1, $2, $3, NOW(), NOW())
        \\RETURNING id, issue_id, author_id, body,
        \\          EXTRACT(EPOCH FROM created_at)::bigint,
        \\          EXTRACT(EPOCH FROM updated_at)::bigint,
        \\          edited
    , .{ issue_id, author_id, body });

    if (row) |r| {
        return CommentRecord{
            .id = r.get(i64, 0),
            .issue_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .body = r.get([]const u8, 3),
            .created_at = r.get(i64, 4),
            .updated_at = r.get(i64, 5),
            .edited = r.get(bool, 6),
        };
    }
    return error.InsertFailed;
}

pub fn updateComment(pool: *Pool, comment_id: i64, body: []const u8) !CommentRecord {
    const row = try pool.row(
        \\UPDATE comments SET body = $2, edited = true, updated_at = NOW()
        \\WHERE id = $1
        \\RETURNING id, issue_id, author_id, body,
        \\          EXTRACT(EPOCH FROM created_at)::bigint,
        \\          EXTRACT(EPOCH FROM updated_at)::bigint,
        \\          edited
    , .{ comment_id, body });

    if (row) |r| {
        return CommentRecord{
            .id = r.get(i64, 0),
            .issue_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .body = r.get([]const u8, 3),
            .created_at = r.get(i64, 4),
            .updated_at = r.get(i64, 5),
            .edited = r.get(bool, 6),
        };
    }
    return error.UpdateFailed;
}

pub fn deleteComment(pool: *Pool, comment_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM comments WHERE id = $1
    , .{comment_id});
}

// =============================================================================
// Assignee Operations
// =============================================================================

pub fn addAssignee(pool: *Pool, issue_id: i64, user_id: i64) !void {
    _ = try pool.exec(
        \\INSERT INTO issue_assignees (issue_id, user_id)
        \\VALUES ($1, $2)
        \\ON CONFLICT (issue_id, user_id) DO NOTHING
    , .{ issue_id, user_id });
}

pub fn removeAssignee(pool: *Pool, issue_id: i64, user_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM issue_assignees WHERE issue_id = $1 AND user_id = $2
    , .{ issue_id, user_id });
}

pub fn getAssignees(pool: *Pool, allocator: std.mem.Allocator, issue_id: i64) ![]i64 {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT user_id FROM issue_assignees WHERE issue_id = $1 ORDER BY assigned_at ASC
    , .{issue_id});
    defer result.deinit();

    var assignees: std.ArrayList(i64) = .{};
    while (try result.next()) |row| {
        try assignees.append(allocator, row.get(i64, 0));
    }

    return try assignees.toOwnedSlice(allocator);
}

// =============================================================================
// Dependency Operations
// =============================================================================

pub fn addDependency(pool: *Pool, repo_id: i64, blocker_issue_id: i64, blocked_issue_id: i64) !void {
    _ = try pool.exec(
        \\INSERT INTO issue_dependencies (repository_id, blocker_issue_id, blocked_issue_id)
        \\VALUES ($1, $2, $3)
        \\ON CONFLICT (blocker_issue_id, blocked_issue_id) DO NOTHING
    , .{ repo_id, blocker_issue_id, blocked_issue_id });
}

pub fn removeDependency(pool: *Pool, blocker_issue_id: i64, blocked_issue_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM issue_dependencies
        \\WHERE blocker_issue_id = $1 AND blocked_issue_id = $2
    , .{ blocker_issue_id, blocked_issue_id });
}

pub fn getBlockingIssues(pool: *Pool, allocator: std.mem.Allocator, issue_id: i64) ![]DependencyRecord {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT d.id, d.blocker_issue_id, d.blocked_issue_id,
        \\       i1.issue_number as blocker_number, i2.issue_number as blocked_number
        \\FROM issue_dependencies d
        \\JOIN issues i1 ON d.blocker_issue_id = i1.id
        \\JOIN issues i2 ON d.blocked_issue_id = i2.id
        \\WHERE d.blocker_issue_id = $1
    , .{issue_id});
    defer result.deinit();

    var deps: std.ArrayList(DependencyRecord) = .{};
    while (try result.next()) |row| {
        try deps.append(allocator, DependencyRecord{
            .id = row.get(i64, 0),
            .blocker_issue_id = row.get(i64, 1),
            .blocked_issue_id = row.get(i64, 2),
            .blocker_number = row.get(i64, 3),
            .blocked_number = row.get(i64, 4),
        });
    }

    return try deps.toOwnedSlice(allocator);
}

pub fn getBlockedByIssues(pool: *Pool, allocator: std.mem.Allocator, issue_id: i64) ![]DependencyRecord {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT d.id, d.blocker_issue_id, d.blocked_issue_id,
        \\       i1.issue_number as blocker_number, i2.issue_number as blocked_number
        \\FROM issue_dependencies d
        \\JOIN issues i1 ON d.blocker_issue_id = i1.id
        \\JOIN issues i2 ON d.blocked_issue_id = i2.id
        \\WHERE d.blocked_issue_id = $1
    , .{issue_id});
    defer result.deinit();

    var deps: std.ArrayList(DependencyRecord) = .{};
    while (try result.next()) |row| {
        try deps.append(allocator, DependencyRecord{
            .id = row.get(i64, 0),
            .blocker_issue_id = row.get(i64, 1),
            .blocked_issue_id = row.get(i64, 2),
            .blocker_number = row.get(i64, 3),
            .blocked_number = row.get(i64, 4),
        });
    }

    return try deps.toOwnedSlice(allocator);
}

// =============================================================================
// Pinned Issues Operations
// =============================================================================

pub fn pin(pool: *Pool, repo_id: i64, issue_id: i64, pinned_by_id: i64) !void {
    // Check how many issues are already pinned
    const count_row = try pool.row(
        \\SELECT COUNT(*) FROM pinned_issues WHERE repository_id = $1
    , .{repo_id});

    const count = if (count_row) |r| r.get(i64, 0) else 0;

    if (count >= 3) {
        return error.MaxPinnedIssuesReached;
    }

    // Find the next available pin_order
    const order_row = try pool.row(
        \\SELECT COALESCE(MAX(pin_order), -1) + 1 FROM pinned_issues WHERE repository_id = $1
    , .{repo_id});

    const pin_order = if (order_row) |r| r.get(i64, 0) else 0;

    _ = try pool.exec(
        \\INSERT INTO pinned_issues (repository_id, issue_id, pin_order, pinned_by_id)
        \\VALUES ($1, $2, $3, $4)
        \\ON CONFLICT (repository_id, issue_id) DO NOTHING
    , .{ repo_id, issue_id, pin_order, pinned_by_id });
}

pub fn unpin(pool: *Pool, issue_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM pinned_issues WHERE issue_id = $1
    , .{issue_id});
}

pub fn getPinned(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64) ![]IssueRecord {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT i.id, i.repository_id, i.author_id, i.issue_number, i.title, i.body, i.state, i.milestone_id,
        \\       EXTRACT(EPOCH FROM i.created_at)::bigint, EXTRACT(EPOCH FROM i.updated_at)::bigint,
        \\       EXTRACT(EPOCH FROM i.closed_at)::bigint
        \\FROM issues i
        \\JOIN pinned_issues p ON i.id = p.issue_id
        \\WHERE p.repository_id = $1
        \\ORDER BY p.pin_order ASC
    , .{repo_id});
    defer result.deinit();

    var issues: std.ArrayList(IssueRecord) = .{};
    while (try result.next()) |row| {
        try issues.append(allocator, IssueRecord{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .author_id = row.get(i64, 2),
            .issue_number = row.get(i64, 3),
            .title = row.get([]const u8, 4),
            .body = row.get(?[]const u8, 5),
            .state = row.get([]const u8, 6),
            .milestone_id = row.get(?i64, 7),
            .created_at = row.get(i64, 8),
            .updated_at = row.get(i64, 9),
            .closed_at = row.get(?i64, 10),
        });
    }

    return try issues.toOwnedSlice(allocator);
}

// =============================================================================
// Delete Operation
// =============================================================================

pub fn delete(pool: *Pool, repo_id: i64, issue_number: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM issues WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });
}

// =============================================================================
// Issue History/Timeline Operations
// =============================================================================

pub const IssueEventRecord = struct {
    id: i64,
    repository_id: i64,
    issue_number: i64,
    actor_id: ?i64,
    event_type: []const u8,
    metadata: []const u8, // JSON string
    created_at: i64,
};

pub fn getHistory(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64, issue_number: i64) ![]IssueEventRecord {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, repository_id, issue_number, actor_id, event_type,
        \\       metadata::text, EXTRACT(EPOCH FROM created_at)::bigint
        \\FROM issue_events
        \\WHERE repository_id = $1 AND issue_number = $2
        \\ORDER BY created_at ASC
    , .{ repo_id, issue_number });
    defer result.deinit();

    var events: std.ArrayList(IssueEventRecord) = .{};
    while (try result.next()) |row| {
        try events.append(allocator, IssueEventRecord{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .issue_number = row.get(i64, 2),
            .actor_id = row.get(?i64, 3),
            .event_type = row.get([]const u8, 4),
            .metadata = row.get([]const u8, 5),
            .created_at = row.get(i64, 6),
        });
    }

    return try events.toOwnedSlice(allocator);
}

// =============================================================================
// Due Date Operations
// =============================================================================

pub fn getDueDate(pool: *Pool, repo_id: i64, issue_number: i64) !?i64 {
    const row = try pool.row(
        \\SELECT EXTRACT(EPOCH FROM due_date)::bigint FROM issues
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });

    if (row) |r| {
        return r.get(?i64, 0);
    }
    return null;
}

pub fn setDueDate(pool: *Pool, repo_id: i64, issue_number: i64, due_date_timestamp: i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET due_date = to_timestamp($3), updated_at = NOW()
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number, due_date_timestamp });
}

pub fn removeDueDate(pool: *Pool, repo_id: i64, issue_number: i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET due_date = NULL, updated_at = NOW()
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });
}
