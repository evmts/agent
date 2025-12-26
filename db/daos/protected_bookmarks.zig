//! Protected Bookmarks Data Access Object
//!
//! SQL operations for the protected_bookmarks table.
//! Manages bookmark protection rules for repositories.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const ProtectedBookmarkRecord = struct {
    id: i64,
    repository_id: i64,
    pattern: []const u8,
    require_review: bool,
    required_approvals: i32,
    created_at: i64,
};

// =============================================================================
// CRUD Operations
// =============================================================================

/// List all protection rules for a repository
pub fn list(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64) ![]ProtectedBookmarkRecord {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, repository_id, pattern, require_review, required_approvals,
        \\       EXTRACT(EPOCH FROM created_at)::bigint as created_at
        \\FROM protected_bookmarks
        \\WHERE repository_id = $1
        \\ORDER BY pattern
    , .{repo_id});
    defer result.deinit();

    var rules = std.ArrayList(ProtectedBookmarkRecord){};
    errdefer rules.deinit(allocator);

    while (try result.next()) |row| {
        try rules.append(allocator, ProtectedBookmarkRecord{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .pattern = try allocator.dupe(u8, row.get([]const u8, 2)),
            .require_review = row.get(bool, 3),
            .required_approvals = row.get(i32, 4),
            .created_at = row.get(i64, 5),
        });
    }

    return try rules.toOwnedSlice(allocator);
}

/// Get a single protection rule by ID
pub fn getById(pool: *Pool, repo_id: i64, rule_id: i64) !?ProtectedBookmarkRecord {
    const row = try pool.row(
        \\SELECT id, repository_id, pattern, require_review, required_approvals,
        \\       EXTRACT(EPOCH FROM created_at)::bigint as created_at
        \\FROM protected_bookmarks
        \\WHERE repository_id = $1 AND id = $2
    , .{ repo_id, rule_id });

    if (row) |r| {
        return ProtectedBookmarkRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .pattern = r.get([]const u8, 2),
            .require_review = r.get(bool, 3),
            .required_approvals = r.get(i32, 4),
            .created_at = r.get(i64, 5),
        };
    }
    return null;
}

/// Create a new protection rule
pub fn create(
    pool: *Pool,
    repo_id: i64,
    pattern: []const u8,
    require_review: bool,
    required_approvals: i32,
) !ProtectedBookmarkRecord {
    const row = try pool.row(
        \\INSERT INTO protected_bookmarks (repository_id, pattern, require_review, required_approvals)
        \\VALUES ($1, $2, $3, $4)
        \\RETURNING id, repository_id, pattern, require_review, required_approvals,
        \\          EXTRACT(EPOCH FROM created_at)::bigint as created_at
    , .{ repo_id, pattern, require_review, required_approvals });

    if (row) |r| {
        return ProtectedBookmarkRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .pattern = r.get([]const u8, 2),
            .require_review = r.get(bool, 3),
            .required_approvals = r.get(i32, 4),
            .created_at = r.get(i64, 5),
        };
    }
    return error.InsertFailed;
}

/// Delete a protection rule by ID
pub fn delete(pool: *Pool, repo_id: i64, rule_id: i64) !bool {
    const affected = try pool.exec(
        \\DELETE FROM protected_bookmarks
        \\WHERE repository_id = $1 AND id = $2
    , .{ repo_id, rule_id });

    return affected != null and affected.? > 0;
}

/// Check if a bookmark matches any protection rule
pub fn matchesProtection(pool: *Pool, repo_id: i64, bookmark_name: []const u8) !?ProtectedBookmarkRecord {
    // First try exact match, then glob patterns
    // For now, only exact match is supported. Glob matching would require
    // either a SQL function or checking patterns in Zig.
    const row = try pool.row(
        \\SELECT id, repository_id, pattern, require_review, required_approvals,
        \\       EXTRACT(EPOCH FROM created_at)::bigint as created_at
        \\FROM protected_bookmarks
        \\WHERE repository_id = $1 AND pattern = $2
    , .{ repo_id, bookmark_name });

    if (row) |r| {
        return ProtectedBookmarkRecord{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .pattern = r.get([]const u8, 2),
            .require_review = r.get(bool, 3),
            .required_approvals = r.get(i32, 4),
            .created_at = r.get(i64, 5),
        };
    }
    return null;
}
