//! Users Data Access Object
//!
//! SQL operations for the users and email_addresses tables.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

/// User record from the users table
pub const UserRecord = struct {
    id: i64,
    username: []const u8,
    email: ?[]const u8,
    display_name: ?[]const u8,
    is_admin: bool,
    is_active: bool,
    prohibit_login: bool,
    wallet_address: ?[]const u8,
};

// =============================================================================
// Read Operations
// =============================================================================

pub fn getById(pool: *Pool, user_id: i64) !?UserRecord {
    const row = try pool.row(
        \\SELECT id, username, email, display_name, is_admin, is_active, prohibit_login, wallet_address
        \\FROM users WHERE id = $1
    , .{user_id});

    if (row) |r| {
        return UserRecord{
            .id = r.get(i64, 0),
            .username = r.get([]const u8, 1),
            .email = r.get(?[]const u8, 2),
            .display_name = r.get(?[]const u8, 3),
            .is_admin = r.get(bool, 4),
            .is_active = r.get(bool, 5),
            .prohibit_login = r.get(bool, 6),
            .wallet_address = r.get(?[]const u8, 7),
        };
    }
    return null;
}

pub fn getByWallet(pool: *Pool, wallet_address: []const u8) !?UserRecord {
    const row = try pool.row(
        \\SELECT id, username, email, display_name, is_admin, is_active, prohibit_login, wallet_address
        \\FROM users WHERE wallet_address = $1
    , .{wallet_address});

    if (row) |r| {
        return UserRecord{
            .id = r.get(i64, 0),
            .username = r.get([]const u8, 1),
            .email = r.get(?[]const u8, 2),
            .display_name = r.get(?[]const u8, 3),
            .is_admin = r.get(bool, 4),
            .is_active = r.get(bool, 5),
            .prohibit_login = r.get(bool, 6),
            .wallet_address = r.get(?[]const u8, 7),
        };
    }
    return null;
}

pub fn getByUsername(pool: *Pool, username: []const u8) !?UserRecord {
    const row = try pool.row(
        \\SELECT id, username, email, display_name, is_admin, is_active, prohibit_login, wallet_address
        \\FROM users WHERE lower_username = lower($1)
    , .{username});

    if (row) |r| {
        return UserRecord{
            .id = r.get(i64, 0),
            .username = r.get([]const u8, 1),
            .email = r.get(?[]const u8, 2),
            .display_name = r.get(?[]const u8, 3),
            .is_admin = r.get(bool, 4),
            .is_active = r.get(bool, 5),
            .prohibit_login = r.get(bool, 6),
            .wallet_address = r.get(?[]const u8, 7),
        };
    }
    return null;
}

// =============================================================================
// Write Operations
// =============================================================================

pub fn create(
    pool: *Pool,
    username: []const u8,
    display_name: ?[]const u8,
    wallet_address: []const u8,
) !i64 {
    const row = try pool.row(
        \\INSERT INTO users (username, lower_username, display_name, wallet_address, is_active, created_at, updated_at)
        \\VALUES ($1, lower($1), $2, $3, true, NOW(), NOW())
        \\RETURNING id
    , .{ username, display_name orelse username, wallet_address });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn updateLastLogin(pool: *Pool, user_id: i64) !void {
    _ = try pool.exec(
        \\UPDATE users SET last_login_at = NOW(), updated_at = NOW() WHERE id = $1
    , .{user_id});
}

pub fn updateProfile(
    pool: *Pool,
    user_id: i64,
    display_name: ?[]const u8,
    bio: ?[]const u8,
    email: ?[]const u8,
) !void {
    // Single efficient UPDATE using COALESCE to only update provided fields
    _ = try pool.exec(
        \\UPDATE users SET
        \\    display_name = COALESCE($1, display_name),
        \\    bio = COALESCE($2, bio),
        \\    email = COALESCE($3, email),
        \\    lower_email = COALESCE(lower($3), lower_email),
        \\    updated_at = NOW()
        \\WHERE id = $4
    , .{ display_name, bio, email, user_id });
}
