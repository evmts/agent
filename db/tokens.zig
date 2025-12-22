//! Tokens Data Access Object
//!
//! SQL operations for the access_tokens and email_verification_tokens tables.

const std = @import("std");
const pg = @import("pg");
const users = @import("users.zig");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const AccessTokenRecord = struct {
    id: i64,
    user_id: i64,
    name: []const u8,
    token_last_eight: []const u8,
    scopes: []const u8,
    created_at: []const u8,
    last_used_at: ?[]const u8,
};

/// Result from validating an access token with user and scopes
pub const TokenValidationResult = struct {
    user: users.UserRecord,
    scopes: []const u8,
};

// =============================================================================
// Access Token Operations
// =============================================================================

pub fn create(
    pool: *Pool,
    user_id: i64,
    name: []const u8,
    token_hash: []const u8,
    token_last_eight: []const u8,
    scopes: []const u8,
) !i64 {
    const row = try pool.row(
        \\INSERT INTO access_tokens (user_id, name, token_hash, token_last_eight, scopes, created_at, updated_at)
        \\VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
        \\RETURNING id
    , .{ user_id, name, token_hash, token_last_eight, scopes });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn delete(pool: *Pool, token_id: i64, user_id: i64) !bool {
    const affected = try pool.exec(
        \\DELETE FROM access_tokens WHERE id = $1 AND user_id = $2
    , .{ token_id, user_id });
    return affected != null and affected.? > 0;
}

pub fn validate(pool: *Pool, token_hash: []const u8) !?TokenValidationResult {
    // Update last_used_at and return user_id + scopes
    const row = try pool.row(
        \\UPDATE access_tokens
        \\SET last_used_at = NOW()
        \\WHERE token_hash = $1
        \\RETURNING user_id, scopes
    , .{token_hash});

    if (row) |r| {
        const user_id = r.get(i64, 0);
        const scopes = r.get([]const u8, 1);
        const user = try users.getById(pool, user_id) orelse return null;
        return TokenValidationResult{
            .user = user,
            .scopes = scopes,
        };
    }
    return null;
}
