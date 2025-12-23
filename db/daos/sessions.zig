//! Sessions Data Access Object
//!
//! SQL operations for the auth_sessions and siwe_nonces tables.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

/// Session validity duration (30 days)
pub const SESSION_DURATION_MS: i64 = 30 * 24 * 60 * 60 * 1000;

// =============================================================================
// Types
// =============================================================================

/// Session data stored in auth_sessions table
pub const SessionData = struct {
    user_id: i32, // Changed from i64 to match Postgres INTEGER type
    username: []const u8,
    is_admin: bool,
    expires_at: i64, // Unix timestamp
};

// =============================================================================
// Session Operations
// =============================================================================

pub fn create(
    pool: *Pool,
    allocator: std.mem.Allocator,
    user_id: i32, // Changed from i64 to match Postgres INTEGER type
    username: []const u8,
    is_admin: bool,
) ![]const u8 {
    // Generate random session key
    var key_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&key_bytes);

    const session_key = try std.fmt.allocPrint(allocator, "{s}", .{
        &std.fmt.bytesToHex(key_bytes, .lower),
    });

    // Session expiration time
    const expires_at = std.time.milliTimestamp() + SESSION_DURATION_MS;

    _ = try pool.exec(
        \\INSERT INTO auth_sessions (session_key, user_id, username, is_admin, expires_at)
        \\VALUES ($1, $2, $3, $4, to_timestamp($5::bigint / 1000.0))
    , .{ session_key, user_id, username, is_admin, expires_at });

    return session_key;
}

pub fn get(pool: *Pool, session_key: []const u8) !?SessionData {
    const row = try pool.row(
        \\SELECT user_id, username, is_admin, EXTRACT(EPOCH FROM expires_at)::bigint as expires_at
        \\FROM auth_sessions
        \\WHERE session_key = $1 AND expires_at > NOW()
    , .{session_key});

    if (row) |r| {
        return SessionData{
            .user_id = r.get(i32, 0), // Changed from i64 to match Postgres INTEGER type
            .username = r.get([]const u8, 1),
            .is_admin = r.get(bool, 2),
            .expires_at = r.get(i64, 3),
        };
    }
    return null;
}

pub fn refresh(pool: *Pool, session_key: []const u8) !void {
    const expires_at = std.time.milliTimestamp() + SESSION_DURATION_MS;
    _ = try pool.exec(
        \\UPDATE auth_sessions SET expires_at = to_timestamp($1::bigint / 1000.0)
        \\WHERE session_key = $2
    , .{ expires_at, session_key });
}

pub fn delete(pool: *Pool, session_key: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM auth_sessions WHERE session_key = $1
    , .{session_key});
}

pub fn cleanupExpired(pool: *Pool) !?i64 {
    return try pool.exec(
        \\DELETE FROM auth_sessions WHERE expires_at <= NOW()
    , .{});
}

// =============================================================================
// Nonce Operations (SIWE)
// =============================================================================

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
