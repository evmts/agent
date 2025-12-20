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

    var labels: std.ArrayList(LabelRecord) = .{};
    while (try result.next()) |row| {
        try labels.append(allocator, LabelRecord{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .name = row.get([]const u8, 2),
            .color = row.get([]const u8, 3),
            .description = row.get(?[]const u8, 4),
        });
    }

    return try labels.toOwnedSlice(allocator);
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

    var labels: std.ArrayList(LabelRecord) = .{};
    while (try result.next()) |row| {
        try labels.append(allocator, LabelRecord{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .name = row.get([]const u8, 2),
            .color = row.get([]const u8, 3),
            .description = row.get(?[]const u8, 4),
        });
    }

    return try labels.toOwnedSlice(allocator);
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

// ============================================================================
// Assignee operations
// ============================================================================

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

// ============================================================================
// Reaction operations
// ============================================================================

pub const ReactionRecord = struct {
    id: i64,
    user_id: i64,
    username: []const u8,
    emoji: []const u8,
    created_at: i64,
};

pub fn addReaction(pool: *Pool, user_id: i64, target_type: []const u8, target_id: i64, emoji: []const u8) !?ReactionRecord {
    const row = try pool.row(
        \\INSERT INTO reactions (user_id, target_type, target_id, emoji)
        \\VALUES ($1, $2, $3, $4)
        \\ON CONFLICT (user_id, target_type, target_id, emoji) DO NOTHING
        \\RETURNING id, user_id, target_type, target_id, emoji, EXTRACT(EPOCH FROM created_at)::bigint
    , .{ user_id, target_type, target_id, emoji });

    if (row) |r| {
        // Get username
        const user_row = try pool.row(
            \\SELECT username FROM users WHERE id = $1
        , .{user_id});

        if (user_row) |ur| {
            return ReactionRecord{
                .id = r.get(i64, 0),
                .user_id = r.get(i64, 1),
                .username = ur.get([]const u8, 0),
                .emoji = r.get([]const u8, 4),
                .created_at = r.get(i64, 5),
            };
        }
    }
    return null;
}

pub fn removeReaction(pool: *Pool, user_id: i64, target_type: []const u8, target_id: i64, emoji: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM reactions
        \\WHERE user_id = $1 AND target_type = $2 AND target_id = $3 AND emoji = $4
    , .{ user_id, target_type, target_id, emoji });
}

pub fn getReactions(pool: *Pool, allocator: std.mem.Allocator, target_type: []const u8, target_id: i64) ![]ReactionRecord {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT r.id, r.user_id, u.username, r.emoji, EXTRACT(EPOCH FROM r.created_at)::bigint
        \\FROM reactions r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE r.target_type = $1 AND r.target_id = $2
        \\ORDER BY r.created_at ASC
    , .{ target_type, target_id });
    defer result.deinit();

    var reactions: std.ArrayList(ReactionRecord) = .{};
    while (try result.next()) |row| {
        try reactions.append(allocator, ReactionRecord{
            .id = row.get(i64, 0),
            .user_id = row.get(i64, 1),
            .username = row.get([]const u8, 2),
            .emoji = row.get([]const u8, 3),
            .created_at = row.get(i64, 4),
        });
    }

    return try reactions.toOwnedSlice(allocator);
}

// ============================================================================
// Dependency operations
// ============================================================================

pub const DependencyRecord = struct {
    id: i64,
    blocker_issue_id: i64,
    blocked_issue_id: i64,
    blocker_number: i64,
    blocked_number: i64,
};

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

// ============================================================================
// Pinned issues operations
// ============================================================================

pub fn pinIssue(pool: *Pool, repo_id: i64, issue_id: i64, pinned_by_id: i64) !void {
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

pub fn unpinIssue(pool: *Pool, issue_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM pinned_issues WHERE issue_id = $1
    , .{issue_id});
}

pub fn getPinnedIssues(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64) ![]IssueRecord {
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

// ============================================================================
// Milestone operations
// ============================================================================

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

pub fn listMilestones(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64, state: ?[]const u8) ![]MilestoneRecord {
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

pub fn getMilestone(pool: *Pool, repo_id: i64, milestone_id: i64) !?MilestoneRecord {
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
        \\WHERE m.id = $1 AND m.repository_id = $2
    , .{ milestone_id, repo_id });

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

pub fn createMilestone(
    pool: *Pool,
    repo_id: i64,
    title: []const u8,
    description: ?[]const u8,
    due_date: ?i64,
) !MilestoneRecord {
    // Convert Unix timestamp to PostgreSQL timestamp if due_date is provided
    const row = if (due_date) |dd| blk: {
        break :blk try pool.row(
            \\INSERT INTO milestones (repository_id, title, description, due_date, created_at, updated_at)
            \\VALUES ($1, $2, $3, to_timestamp($4), NOW(), NOW())
            \\RETURNING id, repository_id, title, description,
            \\          EXTRACT(EPOCH FROM due_date)::bigint,
            \\          state,
            \\          EXTRACT(EPOCH FROM created_at)::bigint,
            \\          EXTRACT(EPOCH FROM updated_at)::bigint,
            \\          EXTRACT(EPOCH FROM closed_at)::bigint
        , .{ repo_id, title, description, dd });
    } else blk: {
        break :blk try pool.row(
            \\INSERT INTO milestones (repository_id, title, description, created_at, updated_at)
            \\VALUES ($1, $2, $3, NOW(), NOW())
            \\RETURNING id, repository_id, title, description,
            \\          EXTRACT(EPOCH FROM due_date)::bigint,
            \\          state,
            \\          EXTRACT(EPOCH FROM created_at)::bigint,
            \\          EXTRACT(EPOCH FROM updated_at)::bigint,
            \\          EXTRACT(EPOCH FROM closed_at)::bigint
        , .{ repo_id, title, description });
    };

    if (row) |r| {
        return MilestoneRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .title = r.get([]const u8, 2),
            .description = r.get(?[]const u8, 3),
            .due_date = r.get(?i64, 4),
            .state = r.get([]const u8, 5),
            .open_issues = 0,
            .closed_issues = 0,
            .created_at = r.get(i64, 6),
            .updated_at = r.get(i64, 7),
            .closed_at = r.get(?i64, 8),
        };
    }
    return error.InsertFailed;
}

pub fn updateMilestone(
    pool: *Pool,
    repo_id: i64,
    milestone_id: i64,
    title: ?[]const u8,
    description: ?[]const u8,
    due_date: ?i64,
    state: ?[]const u8,
) !?MilestoneRecord {
    // Build dynamic update query based on provided fields
    var conn = try pool.acquire();
    defer conn.release();

    // This is a simplified version - in production you'd want to build the query dynamically
    // For now, we'll update all fields that are non-null
    const row = if (title != null and description != null and due_date != null and state != null) blk: {
        const should_set_closed = std.mem.eql(u8, state.?, "closed");
        if (should_set_closed) {
            break :blk try pool.row(
                \\UPDATE milestones
                \\SET title = $3, description = $4, due_date = to_timestamp($5), state = $6, closed_at = NOW(), updated_at = NOW()
                \\WHERE id = $1 AND repository_id = $2
                \\RETURNING id, repository_id, title, description,
                \\          EXTRACT(EPOCH FROM due_date)::bigint, state,
                \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'open'),
                \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'closed'),
                \\          EXTRACT(EPOCH FROM created_at)::bigint,
                \\          EXTRACT(EPOCH FROM updated_at)::bigint,
                \\          EXTRACT(EPOCH FROM closed_at)::bigint
            , .{ milestone_id, repo_id, title.?, description.?, due_date.?, state.? });
        } else {
            break :blk try pool.row(
                \\UPDATE milestones
                \\SET title = $3, description = $4, due_date = to_timestamp($5), state = $6, closed_at = NULL, updated_at = NOW()
                \\WHERE id = $1 AND repository_id = $2
                \\RETURNING id, repository_id, title, description,
                \\          EXTRACT(EPOCH FROM due_date)::bigint, state,
                \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'open'),
                \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'closed'),
                \\          EXTRACT(EPOCH FROM created_at)::bigint,
                \\          EXTRACT(EPOCH FROM updated_at)::bigint,
                \\          EXTRACT(EPOCH FROM closed_at)::bigint
            , .{ milestone_id, repo_id, title.?, description.?, due_date.?, state.? });
        }
    } else if (title != null) blk: {
        break :blk try pool.row(
            \\UPDATE milestones SET title = $3, updated_at = NOW()
            \\WHERE id = $1 AND repository_id = $2
            \\RETURNING id, repository_id, title, description,
            \\          EXTRACT(EPOCH FROM due_date)::bigint, state,
            \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'open'),
            \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'closed'),
            \\          EXTRACT(EPOCH FROM created_at)::bigint,
            \\          EXTRACT(EPOCH FROM updated_at)::bigint,
            \\          EXTRACT(EPOCH FROM closed_at)::bigint
        , .{ milestone_id, repo_id, title.? });
    } else if (state != null) blk: {
        const should_set_closed = std.mem.eql(u8, state.?, "closed");
        if (should_set_closed) {
            break :blk try pool.row(
                \\UPDATE milestones SET state = $3, closed_at = NOW(), updated_at = NOW()
                \\WHERE id = $1 AND repository_id = $2
                \\RETURNING id, repository_id, title, description,
                \\          EXTRACT(EPOCH FROM due_date)::bigint, state,
                \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'open'),
                \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'closed'),
                \\          EXTRACT(EPOCH FROM created_at)::bigint,
                \\          EXTRACT(EPOCH FROM updated_at)::bigint,
                \\          EXTRACT(EPOCH FROM closed_at)::bigint
            , .{ milestone_id, repo_id, state.? });
        } else {
            break :blk try pool.row(
                \\UPDATE milestones SET state = $3, closed_at = NULL, updated_at = NOW()
                \\WHERE id = $1 AND repository_id = $2
                \\RETURNING id, repository_id, title, description,
                \\          EXTRACT(EPOCH FROM due_date)::bigint, state,
                \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'open'),
                \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'closed'),
                \\          EXTRACT(EPOCH FROM created_at)::bigint,
                \\          EXTRACT(EPOCH FROM updated_at)::bigint,
                \\          EXTRACT(EPOCH FROM closed_at)::bigint
            , .{ milestone_id, repo_id, state.? });
        }
    } else blk: {
        break :blk try pool.row(
            \\UPDATE milestones SET updated_at = NOW()
            \\WHERE id = $1 AND repository_id = $2
            \\RETURNING id, repository_id, title, description,
            \\          EXTRACT(EPOCH FROM due_date)::bigint, state,
            \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'open'),
            \\          (SELECT COUNT(*) FROM issues WHERE milestone_id = id AND state = 'closed'),
            \\          EXTRACT(EPOCH FROM created_at)::bigint,
            \\          EXTRACT(EPOCH FROM updated_at)::bigint,
            \\          EXTRACT(EPOCH FROM closed_at)::bigint
        , .{ milestone_id, repo_id });
    };

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

pub fn deleteMilestone(pool: *Pool, repo_id: i64, milestone_id: i64) !bool {
    const result = try pool.exec(
        \\DELETE FROM milestones WHERE id = $1 AND repository_id = $2
    , .{ milestone_id, repo_id });
    return if (result) |r| r > 0 else false;
}

pub fn assignMilestoneToIssue(pool: *Pool, repo_id: i64, issue_number: i64, milestone_id: i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET milestone_id = $3, updated_at = NOW()
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number, milestone_id });
}

pub fn removeMilestoneFromIssue(pool: *Pool, repo_id: i64, issue_number: i64) !void {
    _ = try pool.exec(
        \\UPDATE issues SET milestone_id = NULL, updated_at = NOW()
        \\WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });
}

// ============================================================================
// Additional issue operations
// ============================================================================

pub fn deleteIssue(pool: *Pool, repo_id: i64, issue_number: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM issues WHERE repository_id = $1 AND issue_number = $2
    , .{ repo_id, issue_number });
}

// ============================================================================
// Label update/delete operations
// ============================================================================

pub fn updateLabel(pool: *Pool, repo_id: i64, old_name: []const u8, new_name: []const u8, color: []const u8, description: ?[]const u8) !LabelRecord {
    const row = try pool.row(
        \\UPDATE labels SET name = $3, color = $4, description = $5
        \\WHERE repository_id = $1 AND name = $2
        \\RETURNING id, repository_id, name, color, description
    , .{ repo_id, old_name, new_name, color, description });

    if (row) |r| {
        return LabelRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .name = r.get([]const u8, 2),
            .color = r.get([]const u8, 3),
            .description = r.get(?[]const u8, 4),
        };
    }
    return error.UpdateFailed;
}

pub fn deleteLabel(pool: *Pool, repo_id: i64, name: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM labels WHERE repository_id = $1 AND name = $2
    , .{ repo_id, name });
}

// ============================================================================
// Issue history/timeline operations
// ============================================================================

pub const IssueEventRecord = struct {
    id: i64,
    repository_id: i64,
    issue_number: i64,
    actor_id: ?i64,
    event_type: []const u8,
    metadata: []const u8, // JSON string
    created_at: i64,
};

pub fn getIssueHistory(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64, issue_number: i64) ![]IssueEventRecord {
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

// ============================================================================
// Due date operations
// ============================================================================

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
