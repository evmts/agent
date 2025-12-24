//! Tokens Data Access Object
//!
//! SQL operations for the access_tokens and email_verification_tokens tables.

const std = @import("std");
const pg = @import("pg");
const users = @import("users.zig");

pub const Pool = pg.Pool;

// Token prefix for API tokens (like GitHub's "ghp_")
const TOKEN_PREFIX = "plt_";

// =============================================================================
// Types
// =============================================================================

pub const AccessTokenRecord = struct {
    id: i32, // Postgres SERIAL is INTEGER (32-bit)
    user_id: i32, // References users.id which is SERIAL (32-bit)
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

/// Generate a new access token, store it in the database, and return the raw token.
/// The raw token should be shown to the user once and never stored.
/// Caller owns the returned slice and must free it.
pub fn createAccessToken(
    pool: *Pool,
    allocator: std.mem.Allocator,
    user_id: i32,
    name: []const u8,
    scopes: []const u8,
) ![]const u8 {
    // Generate 32 random bytes for the token
    var token_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&token_bytes);

    // Encode as hex and add prefix
    const hex_buf = std.fmt.bytesToHex(token_bytes, .lower);

    const raw_token = try std.fmt.allocPrint(allocator, "{s}{s}", .{ TOKEN_PREFIX, hex_buf });
    errdefer allocator.free(raw_token);

    // Hash the token for storage (SHA-256)
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(raw_token, &hash, .{});
    const hash_hex = std.fmt.bytesToHex(hash, .lower);

    // Get last 8 characters of raw token for display
    const token_last_eight = raw_token[raw_token.len - 8 ..];

    // Store in database
    _ = try create(pool, user_id, name, &hash_hex, token_last_eight, scopes);

    return raw_token;
}

/// Low-level create that stores pre-hashed token
pub fn create(
    pool: *Pool,
    user_id: i32,
    name: []const u8,
    token_hash: []const u8,
    token_last_eight: []const u8,
    scopes: []const u8,
) !i32 {
    const row = try pool.row(
        \\INSERT INTO access_tokens (user_id, name, token_hash, token_last_eight, scopes, created_at, updated_at)
        \\VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
        \\RETURNING id
    , .{ user_id, name, token_hash, token_last_eight, scopes });

    if (row) |r| {
        return r.get(i32, 0);
    }
    return error.InsertFailed;
}

pub fn delete(pool: *Pool, token_id: i32, user_id: i32) !bool {
    const affected = try pool.exec(
        \\DELETE FROM access_tokens WHERE id = $1 AND user_id = $2
    , .{ token_id, user_id });
    return affected != null and affected.? > 0;
}

/// Validate a token hash and return the associated user and scopes.
/// The token_hash should already be SHA-256 hashed (by auth middleware).
/// Note: scopes slice points to internal memory and should be copied if needed beyond immediate use.
pub fn validate(pool: *Pool, token_hash: []const u8) !?TokenValidationResult {
    // Update last_used_at and return user_id + scopes
    const row = try pool.row(
        \\UPDATE access_tokens
        \\SET last_used_at = NOW()
        \\WHERE token_hash = $1
        \\RETURNING user_id, scopes
    , .{token_hash});

    if (row) |r| {
        const user_id = r.get(i32, 0); // Changed from i64 to match Postgres INTEGER type
        const scopes = r.get([]const u8, 1);
        const user = try users.getById(pool, user_id) orelse return null;
        return TokenValidationResult{
            .user = user,
            .scopes = scopes,
        };
    }
    return null;
}
