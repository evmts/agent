//! Stars Data Access Object
//!
//! SQL operations for the stars and watches tables.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const Stargazer = struct {
    id: i64,
    username: []const u8,
    display_name: ?[]const u8,
    created_at: []const u8,
};

// =============================================================================
// Star Operations
// =============================================================================

pub fn getStargazers(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64) ![]Stargazer {
    var result = try pool.query(
        \\SELECT u.id, u.username, u.display_name, to_char(s.created_at, 'YYYY-MM-DD HH24:MI:SS') as created_at
        \\FROM stars s
        \\JOIN users u ON s.user_id = u.id
        \\WHERE s.repository_id = $1
        \\ORDER BY s.created_at DESC
    , .{repo_id});
    defer result.deinit();

    var stargazers = try std.ArrayList(Stargazer).initCapacity(allocator, 0);
    errdefer stargazers.deinit(allocator);

    while (try result.next()) |row| {
        try stargazers.append(allocator, Stargazer{
            .id = row.get(i64, 0),
            .username = row.get([]const u8, 1),
            .display_name = row.get(?[]const u8, 2),
            .created_at = row.get([]const u8, 3),
        });
    }

    return try stargazers.toOwnedSlice(allocator);
}

pub fn hasStarred(pool: *Pool, user_id: i64, repo_id: i64) !bool {
    const row = try pool.row(
        \\SELECT 1 FROM stars WHERE user_id = $1 AND repository_id = $2
    , .{ user_id, repo_id });

    return row != null;
}

pub fn create(pool: *Pool, user_id: i64, repo_id: i64) !void {
    _ = try pool.exec(
        \\INSERT INTO stars (user_id, repository_id) VALUES ($1, $2)
    , .{ user_id, repo_id });
}

pub fn delete(pool: *Pool, user_id: i64, repo_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM stars WHERE user_id = $1 AND repository_id = $2
    , .{ user_id, repo_id });
}

pub fn getCount(pool: *Pool, repo_id: i64) !i64 {
    const row = try pool.row(
        \\SELECT COUNT(*) as count FROM stars WHERE repository_id = $1
    , .{repo_id});

    if (row) |r| {
        return r.get(i64, 0);
    }
    return 0;
}

// =============================================================================
// Watch Operations
// =============================================================================

pub fn upsertWatch(pool: *Pool, user_id: i64, repo_id: i64, level: []const u8) !void {
    _ = try pool.exec(
        \\INSERT INTO watches (user_id, repository_id, level)
        \\VALUES ($1, $2, $3)
        \\ON CONFLICT (user_id, repository_id)
        \\DO UPDATE SET level = $3, updated_at = NOW()
    , .{ user_id, repo_id, level });
}

pub fn deleteWatch(pool: *Pool, user_id: i64, repo_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM watches WHERE user_id = $1 AND repository_id = $2
    , .{ user_id, repo_id });
}

pub fn getWatchLevel(pool: *Pool, user_id: i64, repo_id: i64) !?[]const u8 {
    const row = try pool.row(
        \\SELECT level FROM watches WHERE user_id = $1 AND repository_id = $2
    , .{ user_id, repo_id });

    if (row) |r| {
        return r.get([]const u8, 0);
    }
    return null;
}
