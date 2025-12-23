//! SSH Keys Data Access Object
//!
//! SQL operations for the ssh_keys table.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const SshKeyRecord = struct {
    id: i64,
    user_id: i64,
    name: []const u8,
    fingerprint: []const u8,
    key_type: []const u8,
    created_at: []const u8,
};

// =============================================================================
// Operations
// =============================================================================

pub fn create(
    pool: *Pool,
    user_id: i64,
    name: []const u8,
    public_key: []const u8,
    fingerprint: []const u8,
    key_type: []const u8,
) !i64 {
    const row = try pool.row(
        \\INSERT INTO ssh_keys (user_id, name, public_key, fingerprint, key_type, created_at, updated_at)
        \\VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
        \\RETURNING id
    , .{ user_id, name, public_key, fingerprint, key_type });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn getByFingerprint(pool: *Pool, fingerprint: []const u8) !?SshKeyRecord {
    const row = try pool.row(
        \\SELECT id, user_id, name, fingerprint, key_type, created_at::text
        \\FROM ssh_keys
        \\WHERE fingerprint = $1
    , .{fingerprint});

    if (row) |r| {
        return SshKeyRecord{
            .id = r.get(i64, 0),
            .user_id = r.get(i64, 1),
            .name = r.get([]const u8, 2),
            .fingerprint = r.get([]const u8, 3),
            .key_type = r.get([]const u8, 4),
            .created_at = r.get([]const u8, 5),
        };
    }
    return null;
}

pub fn getById(pool: *Pool, key_id: i64, user_id: i64) !?SshKeyRecord {
    const row = try pool.row(
        \\SELECT id, user_id, name, fingerprint, key_type, created_at::text
        \\FROM ssh_keys
        \\WHERE id = $1 AND user_id = $2
    , .{ key_id, user_id });

    if (row) |r| {
        return SshKeyRecord{
            .id = r.get(i64, 0),
            .user_id = r.get(i64, 1),
            .name = r.get([]const u8, 2),
            .fingerprint = r.get([]const u8, 3),
            .key_type = r.get([]const u8, 4),
            .created_at = r.get([]const u8, 5),
        };
    }
    return null;
}

pub fn delete(pool: *Pool, key_id: i64, user_id: i64) !bool {
    const affected = try pool.exec(
        \\DELETE FROM ssh_keys WHERE id = $1 AND user_id = $2
    , .{ key_id, user_id });
    return affected != null and affected.? > 0;
}
