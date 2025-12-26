//! Repositories Data Access Object
//!
//! SQL operations for the repositories, branches, protected_branches, and renamed_branches tables.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const Repository = struct {
    id: i32,
    user_id: i32,
    name: []const u8,
    description: ?[]const u8,
    is_public: bool,
    default_branch: ?[]const u8,
    // Note: topics is stored as TEXT[] in PostgreSQL but pg.zig doesn't support 2D arrays
    // Topics will be handled separately via getRepositoryTopics()
};

// =============================================================================
// Read Operations
// =============================================================================

pub fn getByUserAndName(pool: *Pool, username: []const u8, repo_name: []const u8) !?Repository {
    const row = try pool.row(
        \\SELECT r.id, r.user_id, r.name, r.description, r.is_public, r.default_branch
        \\FROM repositories r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE u.username = $1 AND r.name = $2
    , .{ username, repo_name });

    if (row) |r| {
        return Repository{
            .id = r.get(i32, 0),
            .user_id = r.get(i32, 1),
            .name = r.get([]const u8, 2),
            .description = r.get(?[]const u8, 3),
            .is_public = r.get(bool, 4),
            .default_branch = r.get(?[]const u8, 5),
        };
    }
    return null;
}

pub fn getById(pool: *Pool, repo_id: i32) !?Repository {
    const row = try pool.row(
        \\SELECT id, user_id, name, description, is_public, default_branch
        \\FROM repositories WHERE id = $1
    , .{repo_id});

    if (row) |r| {
        return Repository{
            .id = r.get(i32, 0),
            .user_id = r.get(i32, 1),
            .name = r.get([]const u8, 2),
            .description = r.get(?[]const u8, 3),
            .is_public = r.get(bool, 4),
            .default_branch = r.get(?[]const u8, 5),
        };
    }
    return null;
}

pub fn exists(pool: *Pool, owner_id: i32, name: []const u8) !bool {
    const row = try pool.row(
        \\SELECT 1 FROM repositories WHERE user_id = $1 AND name = $2
    , .{ owner_id, name });

    return row != null;
}

// =============================================================================
// Write Operations
// =============================================================================

pub fn create(
    pool: *Pool,
    owner_id: i32,
    name: []const u8,
    description: ?[]const u8,
    is_public: bool,
) !i32 {
    const row = try pool.row(
        \\INSERT INTO repositories (user_id, name, description, is_public, created_at, updated_at)
        \\VALUES ($1, $2, $3, $4, NOW(), NOW())
        \\RETURNING id
    , .{ owner_id, name, description, is_public }) orelse return error.InsertFailed;

    return row.get(i32, 0);
}

pub fn updateTopics(pool: *Pool, repo_id: i32, topics: [][]const u8) !void {
    _ = try pool.exec(
        \\UPDATE repositories SET topics = $1, updated_at = NOW()
        \\WHERE id = $2
    , .{ topics, repo_id });
}

pub fn updateDescription(pool: *Pool, repo_id: i32, description: ?[]const u8) !void {
    _ = try pool.exec(
        \\UPDATE repositories SET description = $1, updated_at = NOW()
        \\WHERE id = $2
    , .{ description, repo_id });
}

pub fn updateDefaultBranch(pool: *Pool, repo_id: i32, default_branch: []const u8) !void {
    _ = try pool.exec(
        \\UPDATE repositories SET default_branch = $1, updated_at = NOW()
        \\WHERE id = $2
    , .{ default_branch, repo_id });
}

pub fn delete(pool: *Pool, repo_id: i32) !void {
    _ = try pool.exec(
        \\DELETE FROM repositories WHERE id = $1
    , .{repo_id});
}

/// Get repository ID by username and repository name (case-insensitive)
pub fn getId(pool: *Pool, username: []const u8, repo_name: []const u8) !?i32 {
    const row = try pool.row(
        \\SELECT r.id FROM repositories r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE u.lower_username = lower($1) AND lower(r.name) = lower($2)
    , .{ username, repo_name });

    if (row) |r| {
        return r.get(i32, 0);
    }
    return null;
}
