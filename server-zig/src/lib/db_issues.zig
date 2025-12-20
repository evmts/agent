//! Issue database operations
//!
//! This module provides database functions for issues, comments, and labels.
//! These should be integrated into db.zig

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;
pub const Conn = pg.Conn;

// ============================================================================
// Repository operations
// ============================================================================

pub const RepositoryRecord = struct {
    id: i64,
    user_id: i64,
    name: []const u8,
    description: ?[]const u8,
    is_public: bool,
    default_branch: []const u8,
};

pub fn getRepositoryByName(pool: *Pool, username: []const u8, repo_name: []const u8) !?RepositoryRecord {
    const row = try pool.row(
        \\SELECT r.id, r.user_id, r.name, r.description, r.is_public, r.default_branch
        \\FROM repositories r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE u.username = $1 AND r.name = $2
    , .{ username, repo_name });

    if (row) |r| {
        return RepositoryRecord{
            .id = r.get(i64, 0),
            .user_id = r.get(i64, 1),
            .name = r.get([]const u8, 2),
            .description = r.get(?[]const u8, 3),
            .is_public = r.get(bool, 4),
            .default_branch = r.get([]const u8, 5),
        };
    }
    return null;
}

// ============================================================================
// Issue operations
// ============================================================================

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

pub fn listIssues(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64, state: ?[]const u8) ![]IssueRecord {
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

    var issues: std.ArrayList(IssueRecord) = .init(allocator);
    while (try result.next()) |row| {
        try issues.append(IssueRecord{
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

    return issues.toOwnedSlice();
}

pub fn getIssue(pool: *Pool, repo_id: i64, issue_number: i64) !?IssueRecord {
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

pub fn createIssue(
    pool: *Pool,
    repo_id: i64,
    author_id: i64,
    title: []const u8,
    body: ?[]const u8,
) !IssueRecord {
    // Get next issue number
    const num_row = try pool.row(
        \\SELECT COALESCE(MAX(issue_number), 0) + 1 FROM issues WHERE repository_id = $1
    , .{repo_id});

    const issue_number = if (num_row) |r| r.get(i64, 0) else 1;

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

pub fn updateIssue(
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

pub fn closeIssue(pool: *Pool, repo_id: i64, issue_number: i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET state = 'closed', closed_at = NOW(), updated_at = NOW()
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });
}

pub fn reopenIssue(pool: *Pool, repo_id: i64, issue_number: i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET state = 'open', closed_at = NULL, updated_at = NOW()
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });
}

pub fn getIssueCounts(pool: *Pool, repo_id: i64) !struct { open: i64, closed: i64 } {
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

// ============================================================================
// Comment operations
// ============================================================================

pub const CommentRecord = struct {
    id: i64,
    issue_id: i64,
    author_id: i64,
    body: []const u8,
    created_at: i64,
    updated_at: i64,
    edited: bool,
};

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

    var comments: std.ArrayList(CommentRecord) = .init(allocator);
    while (try result.next()) |row| {
        try comments.append(CommentRecord{
            .id = row.get(i64, 0),
            .issue_id = row.get(i64, 1),
            .author_id = row.get(i64, 2),
            .body = row.get([]const u8, 3),
            .created_at = row.get(i64, 4),
            .updated_at = row.get(i64, 5),
            .edited = row.get(bool, 6),
        });
    }

    return comments.toOwnedSlice();
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

// ============================================================================
// Label operations
// ============================================================================

pub const LabelRecord = struct {
    id: i64,
    repository_id: i64,
    name: []const u8,
    color: []const u8,
    description: ?[]const u8,
};

pub fn getLabels(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64) ![]LabelRecord {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, repository_id, name, color, description
        \\FROM labels WHERE repository_id = $1 ORDER BY name
    , .{repo_id});
    defer result.deinit();

    var labels: std.ArrayList(LabelRecord) = .init(allocator);
    while (try result.next()) |row| {
        try labels.append(LabelRecord{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .name = row.get([]const u8, 2),
            .color = row.get([]const u8, 3),
            .description = row.get(?[]const u8, 4),
        });
    }

    return labels.toOwnedSlice();
}

pub fn createLabel(pool: *Pool, repo_id: i64, name: []const u8, color: []const u8, description: ?[]const u8) !LabelRecord {
    const row = try pool.row(
        \\INSERT INTO labels (repository_id, name, color, description)
        \\VALUES ($1, $2, $3, $4)
        \\RETURNING id, repository_id, name, color, description
    , .{ repo_id, name, color, description });

    if (row) |r| {
        return LabelRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .name = r.get([]const u8, 2),
            .color = r.get([]const u8, 3),
            .description = r.get(?[]const u8, 4),
        };
    }
    return error.InsertFailed;
}

pub fn addLabelToIssue(pool: *Pool, issue_id: i64, label_id: i64) !void {
    _ = try pool.exec(
        \\INSERT INTO issue_labels (issue_id, label_id) VALUES ($1, $2)
        \\ON CONFLICT (issue_id, label_id) DO NOTHING
    , .{ issue_id, label_id });
}

pub fn removeLabelFromIssue(pool: *Pool, issue_id: i64, label_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM issue_labels WHERE issue_id = $1 AND label_id = $2
    , .{ issue_id, label_id });
}

pub fn getIssueLabels(pool: *Pool, allocator: std.mem.Allocator, issue_id: i64) ![]LabelRecord {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT l.id, l.repository_id, l.name, l.color, l.description
        \\FROM labels l
        \\JOIN issue_labels il ON l.id = il.label_id
        \\WHERE il.issue_id = $1 ORDER BY l.name
    , .{issue_id});
    defer result.deinit();

    var labels: std.ArrayList(LabelRecord) = .init(allocator);
    while (try result.next()) |row| {
        try labels.append(LabelRecord{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .name = row.get([]const u8, 2),
            .color = row.get([]const u8, 3),
            .description = row.get(?[]const u8, 4),
        });
    }

    return labels.toOwnedSlice();
}

pub fn getLabelByName(pool: *Pool, repo_id: i64, name: []const u8) !?LabelRecord {
    const row = try pool.row(
        \\SELECT id, repository_id, name, color, description
        \\FROM labels WHERE repository_id = $1 AND name = $2
    , .{ repo_id, name });

    if (row) |r| {
        return LabelRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .name = r.get([]const u8, 2),
            .color = r.get([]const u8, 3),
            .description = r.get(?[]const u8, 4),
        };
    }
    return null;
}
