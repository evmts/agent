//! Labels Data Access Object
//!
//! SQL operations for the labels and issue_labels tables.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const LabelRecord = struct {
    id: i64,
    repository_id: i64,
    name: []const u8,
    color: []const u8,
    description: ?[]const u8,
};

// =============================================================================
// Label Operations
// =============================================================================

pub fn list(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64) ![]LabelRecord {
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

pub fn getByName(pool: *Pool, repo_id: i64, name: []const u8) !?LabelRecord {
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

pub fn create(pool: *Pool, repo_id: i64, name: []const u8, color: []const u8, description: ?[]const u8) !LabelRecord {
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

pub fn update(pool: *Pool, label_id: i64, name: ?[]const u8, color: ?[]const u8, description: ?[]const u8) !void {
    if (name != null and color != null and description != null) {
        _ = try pool.exec(
            \\UPDATE labels SET name = $2, color = $3, description = $4 WHERE id = $1
        , .{ label_id, name.?, color.?, description.? });
    } else if (name != null and color != null) {
        _ = try pool.exec(
            \\UPDATE labels SET name = $2, color = $3 WHERE id = $1
        , .{ label_id, name.?, color.? });
    } else if (name != null) {
        _ = try pool.exec(
            \\UPDATE labels SET name = $2 WHERE id = $1
        , .{ label_id, name.? });
    } else if (color != null) {
        _ = try pool.exec(
            \\UPDATE labels SET color = $2 WHERE id = $1
        , .{ label_id, color.? });
    } else if (description != null) {
        _ = try pool.exec(
            \\UPDATE labels SET description = $2 WHERE id = $1
        , .{ label_id, description.? });
    }
}

pub fn delete(pool: *Pool, label_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM labels WHERE id = $1
    , .{label_id});
}

/// Update a label by repo_id and old name (backward compatible with old db_issues API)
pub fn updateByName(pool: *Pool, repo_id: i64, old_name: []const u8, new_name: []const u8, color: []const u8, description: ?[]const u8) !LabelRecord {
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

/// Delete a label by repo_id and name (backward compatible with old db_issues API)
pub fn deleteByName(pool: *Pool, repo_id: i64, name: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM labels WHERE repository_id = $1 AND name = $2
    , .{ repo_id, name });
}

// =============================================================================
// Issue-Label Association Operations
// =============================================================================

pub fn addToIssue(pool: *Pool, issue_id: i64, label_id: i64) !void {
    _ = try pool.exec(
        \\INSERT INTO issue_labels (issue_id, label_id) VALUES ($1, $2)
        \\ON CONFLICT (issue_id, label_id) DO NOTHING
    , .{ issue_id, label_id });
}

pub fn removeFromIssue(pool: *Pool, issue_id: i64, label_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM issue_labels WHERE issue_id = $1 AND label_id = $2
    , .{ issue_id, label_id });
}

pub fn getForIssue(pool: *Pool, allocator: std.mem.Allocator, issue_id: i64) ![]LabelRecord {
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
