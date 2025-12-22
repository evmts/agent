//! Changes Data Access Object
//!
//! SQL operations for JJ-native tables: changes, bookmarks, jj_operations,
//! protected_bookmarks, conflicts, landing_queue, landing_reviews, landing_line_comments.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const Bookmark = struct {
    id: i64,
    name: []const u8,
    target_change_id: []const u8,
    is_default: bool,
};

pub const Change = struct {
    id: i64,
    repository_id: i64,
    change_id: []const u8,
    commit_id: ?[]const u8,
    description: ?[]const u8,
    author_id: ?i64,
    author_name: ?[]const u8,
    author_email: ?[]const u8,
    has_conflict: bool,
    is_empty: bool,
};

pub const Conflict = struct {
    id: i64,
    repository_id: i64,
    change_id: []const u8,
    file_path: []const u8,
    conflict_type: []const u8,
    resolved: bool,
};

// =============================================================================
// Bookmark Operations
// =============================================================================

pub fn listBookmarks(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64) ![]Bookmark {
    var result = try pool.query(
        \\SELECT id, name, target_change_id, is_default
        \\FROM bookmarks
        \\WHERE repository_id = $1
        \\ORDER BY CASE WHEN is_default THEN 0 ELSE 1 END, updated_at DESC
    , .{repo_id});
    defer result.deinit();

    var bookmarks = try std.ArrayList(Bookmark).initCapacity(allocator, 0);
    errdefer bookmarks.deinit(allocator);

    while (try result.next()) |row| {
        try bookmarks.append(allocator, Bookmark{
            .id = row.get(i64, 0),
            .name = row.get([]const u8, 1),
            .target_change_id = row.get([]const u8, 2),
            .is_default = row.get(bool, 3),
        });
    }

    return try bookmarks.toOwnedSlice(allocator);
}

pub fn getBookmarkByName(pool: *Pool, repo_id: i64, name: []const u8) !?Bookmark {
    const row = try pool.row(
        \\SELECT id, name, target_change_id, is_default
        \\FROM bookmarks
        \\WHERE repository_id = $1 AND name = $2
    , .{ repo_id, name });

    if (row) |r| {
        return Bookmark{
            .id = r.get(i64, 0),
            .name = r.get([]const u8, 1),
            .target_change_id = r.get([]const u8, 2),
            .is_default = r.get(bool, 3),
        };
    }
    return null;
}

pub fn createBookmark(pool: *Pool, repo_id: i64, name: []const u8, target_change_id: []const u8, pusher_id: i64) !i64 {
    const row = try pool.row(
        \\INSERT INTO bookmarks (repository_id, name, target_change_id)
        \\VALUES ($1, $2, $3)
        \\RETURNING id
    , .{ repo_id, name, target_change_id });
    _ = pusher_id;

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn updateBookmark(pool: *Pool, repo_id: i64, name: []const u8, target_change_id: []const u8) !void {
    _ = try pool.exec(
        \\UPDATE bookmarks SET target_change_id = $1, updated_at = NOW()
        \\WHERE repository_id = $2 AND name = $3
    , .{ target_change_id, repo_id, name });
}

pub fn deleteBookmark(pool: *Pool, repo_id: i64, name: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM bookmarks WHERE repository_id = $1 AND name = $2
    , .{ repo_id, name });
}

pub fn setDefaultBookmark(pool: *Pool, repo_id: i64, name: []const u8) !void {
    // Clear existing default
    _ = try pool.exec(
        \\UPDATE bookmarks SET is_default = false WHERE repository_id = $1
    , .{repo_id});

    // Set new default
    _ = try pool.exec(
        \\UPDATE bookmarks SET is_default = true WHERE repository_id = $1 AND name = $2
    , .{ repo_id, name });
}

// =============================================================================
// Change Operations
// =============================================================================

pub fn getChangeById(pool: *Pool, repo_id: i64, change_id: []const u8) !?Change {
    const row = try pool.row(
        \\SELECT id, repository_id, change_id, commit_id, description,
        \\       author_id, author_name, author_email, has_conflict, is_empty
        \\FROM changes
        \\WHERE repository_id = $1 AND change_id = $2
    , .{ repo_id, change_id });

    if (row) |r| {
        return Change{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .change_id = r.get([]const u8, 2),
            .commit_id = r.get(?[]const u8, 3),
            .description = r.get(?[]const u8, 4),
            .author_id = r.get(?i64, 5),
            .author_name = r.get(?[]const u8, 6),
            .author_email = r.get(?[]const u8, 7),
            .has_conflict = r.get(bool, 8),
            .is_empty = r.get(bool, 9),
        };
    }
    return null;
}

pub fn upsertChange(
    pool: *Pool,
    repo_id: i64,
    change_id: []const u8,
    commit_id: ?[]const u8,
    description: ?[]const u8,
    author_name: ?[]const u8,
    author_email: ?[]const u8,
    has_conflict: bool,
    is_empty: bool,
) !void {
    _ = try pool.exec(
        \\INSERT INTO changes (repository_id, change_id, commit_id, description, author_name, author_email, has_conflict, is_empty)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        \\ON CONFLICT (repository_id, change_id) DO UPDATE SET
        \\  commit_id = $3, description = $4, author_name = $5, author_email = $6,
        \\  has_conflict = $7, is_empty = $8, updated_at = NOW()
    , .{ repo_id, change_id, commit_id, description, author_name, author_email, has_conflict, is_empty });
}

// =============================================================================
// Conflict Operations
// =============================================================================

pub fn upsertConflict(
    pool: *Pool,
    repo_id: i64,
    change_id: []const u8,
    file_path: []const u8,
    conflict_type: []const u8,
) !void {
    _ = try pool.exec(
        \\INSERT INTO conflicts (repository_id, change_id, file_path, conflict_type)
        \\VALUES ($1, $2, $3, $4)
        \\ON CONFLICT (change_id, file_path) DO UPDATE SET
        \\  conflict_type = $4, updated_at = NOW()
    , .{ repo_id, change_id, file_path, conflict_type });
}

pub fn resolveConflict(
    pool: *Pool,
    change_id: []const u8,
    file_path: []const u8,
    resolved_by: i64,
    resolution_method: []const u8,
) !void {
    _ = try pool.exec(
        \\UPDATE conflicts SET
        \\  resolved = true, resolved_by = $1, resolution_method = $2, resolved_at = NOW()
        \\WHERE change_id = $3 AND file_path = $4
    , .{ resolved_by, resolution_method, change_id, file_path });
}

pub fn getConflicts(pool: *Pool, allocator: std.mem.Allocator, change_id: []const u8) ![]Conflict {
    var result = try pool.query(
        \\SELECT id, repository_id, change_id, file_path, conflict_type, resolved
        \\FROM conflicts
        \\WHERE change_id = $1
        \\ORDER BY file_path
    , .{change_id});
    defer result.deinit();

    var conflicts = try std.ArrayList(Conflict).initCapacity(allocator, 0);
    errdefer conflicts.deinit(allocator);

    while (try result.next()) |row| {
        try conflicts.append(allocator, Conflict{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .change_id = row.get([]const u8, 2),
            .file_path = row.get([]const u8, 3),
            .conflict_type = row.get([]const u8, 4),
            .resolved = row.get(bool, 5),
        });
    }

    return try conflicts.toOwnedSlice(allocator);
}
