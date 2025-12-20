//! Database layer
//!
//! Wraps pg.zig for PostgreSQL operations.

const std = @import("std");
const pg = @import("pg");

const log = std.log.scoped(.db);

pub const Pool = pg.Pool;
pub const Conn = pg.Conn;
pub const Result = pg.Result;
pub const QueryRow = pg.QueryRow;

/// Session data stored in auth_sessions table
pub const SessionData = struct {
    user_id: i64,
    username: []const u8,
    is_admin: bool,
    expires_at: i64, // Unix timestamp
};

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

// ============================================================================
// Session operations
// ============================================================================

pub fn createSession(
    pool: *Pool,
    allocator: std.mem.Allocator,
    user_id: i64,
    username: []const u8,
    is_admin: bool,
) ![]const u8 {
    // Generate random session key
    var key_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&key_bytes);

    const session_key = try std.fmt.allocPrint(allocator, "{}", .{
        std.fmt.fmtSliceHexLower(&key_bytes),
    });

    // 30 days from now in milliseconds
    const expires_at = std.time.milliTimestamp() + (30 * 24 * 60 * 60 * 1000);

    _ = try pool.exec(
        \\INSERT INTO auth_sessions (session_key, user_id, username, is_admin, expires_at)
        \\VALUES ($1, $2, $3, $4, to_timestamp($5::bigint / 1000.0))
    , .{ session_key, user_id, username, is_admin, expires_at });

    return session_key;
}

pub fn getSession(pool: *Pool, session_key: []const u8) !?SessionData {
    const row = try pool.row(
        \\SELECT user_id, username, is_admin, EXTRACT(EPOCH FROM expires_at)::bigint as expires_at
        \\FROM auth_sessions
        \\WHERE session_key = $1 AND expires_at > NOW()
    , .{session_key});

    if (row) |r| {
        return SessionData{
            .user_id = r.get(i64, 0),
            .username = r.get([]const u8, 1),
            .is_admin = r.get(bool, 2),
            .expires_at = r.get(i64, 3),
        };
    }
    return null;
}

pub fn refreshSession(pool: *Pool, session_key: []const u8) !void {
    const expires_at = std.time.milliTimestamp() + (30 * 24 * 60 * 60 * 1000);
    _ = try pool.exec(
        \\UPDATE auth_sessions SET expires_at = to_timestamp($1::bigint / 1000.0)
        \\WHERE session_key = $2
    , .{ expires_at, session_key });
}

pub fn deleteSession(pool: *Pool, session_key: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM auth_sessions WHERE session_key = $1
    , .{session_key});
}

// ============================================================================
// User operations
// ============================================================================

pub fn getUserById(pool: *Pool, user_id: i64) !?UserRecord {
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

pub fn getUserByWallet(pool: *Pool, wallet_address: []const u8) !?UserRecord {
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

pub fn getUserByUsername(pool: *Pool, username: []const u8) !?UserRecord {
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

pub fn createUser(
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

// ============================================================================
// Nonce operations
// ============================================================================

pub fn createNonce(pool: *Pool, nonce: []const u8) !void {
    const expires_at = std.time.milliTimestamp() + (10 * 60 * 1000); // 10 minutes
    _ = try pool.exec(
        \\INSERT INTO siwe_nonces (nonce, expires_at)
        \\VALUES ($1, to_timestamp($2::bigint / 1000.0))
    , .{ nonce, expires_at });
}

pub fn validateNonce(pool: *Pool, nonce: []const u8) !bool {
    const row = try pool.row(
        \\SELECT EXTRACT(EPOCH FROM expires_at)::bigint * 1000 as expires_at,
        \\       used_at IS NOT NULL as is_used
        \\FROM siwe_nonces WHERE nonce = $1
    , .{nonce});

    if (row) |r| {
        const is_used = r.get(bool, 1);
        if (is_used) return false; // Already used

        const expires_at = r.get(i64, 0);
        if (std.time.milliTimestamp() > expires_at) return false; // Expired

        return true;
    }
    return false;
}

pub fn markNonceUsed(pool: *Pool, nonce: []const u8, wallet_address: []const u8) !void {
    _ = try pool.exec(
        \\UPDATE siwe_nonces SET used_at = NOW(), wallet_address = $1 WHERE nonce = $2
    , .{ wallet_address, nonce });
}

pub fn cleanupExpiredNonces(pool: *Pool) !?i64 {
    return try pool.exec(
        \\DELETE FROM siwe_nonces WHERE expires_at <= NOW() OR used_at IS NOT NULL
    , .{});
}
