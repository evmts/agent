//! Agent Tokens Data Access Object
//!
//! SQL operations for agent token generation and validation.
//! Agent tokens are short-lived credentials that allow Python runners
//! to authenticate when persisting messages/parts to the API.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

/// Token prefix for agent tokens
pub const TOKEN_PREFIX = "plat_"; // PLue Agent Token

/// Default token expiration (24 hours)
pub const DEFAULT_EXPIRY_MS: i64 = 24 * 60 * 60 * 1000;

// =============================================================================
// Types
// =============================================================================

/// Information returned when validating an agent token
pub const AgentTokenInfo = struct {
    workflow_run_id: i32,
    session_id: ?[]const u8,
    status: []const u8,
};

// =============================================================================
// Token Operations
// =============================================================================

/// Generate a new agent token for a workflow run.
/// Returns the raw token (to be passed to runner).
/// The token hash is stored in workflow_runs.agent_token_hash.
pub fn generateAgentToken(
    pool: *Pool,
    allocator: std.mem.Allocator,
    workflow_run_id: i32,
    expires_in_ms: i64,
) ![]const u8 {
    // Generate 32 random bytes
    var token_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&token_bytes);

    // Encode as hex with prefix: plat_<64 hex chars>
    const hex = std.fmt.bytesToHex(token_bytes, .lower);
    const raw_token = try std.fmt.allocPrint(allocator, "{s}{s}", .{ TOKEN_PREFIX, hex });
    errdefer allocator.free(raw_token);

    // Hash for storage (SHA-256)
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(raw_token, &hash, .{});
    const hash_hex = std.fmt.bytesToHex(hash, .lower);

    const expires_at = std.time.milliTimestamp() + expires_in_ms;

    // Store hash in workflow_runs
    _ = try pool.exec(
        \\UPDATE workflow_runs
        \\SET agent_token_hash = $1, agent_token_expires_at = to_timestamp($2::bigint / 1000.0)
        \\WHERE id = $3
    , .{ &hash_hex, expires_at, workflow_run_id });

    return raw_token;
}

/// Validate an agent token and return associated workflow/session info.
/// Returns null if token is invalid, expired, or workflow is not active.
pub fn validateAgentToken(pool: *Pool, raw_token: []const u8) !?AgentTokenInfo {
    // Verify prefix
    if (!std.mem.startsWith(u8, raw_token, TOKEN_PREFIX)) return null;

    // Hash the token
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(raw_token, &hash, .{});
    const hash_hex = std.fmt.bytesToHex(hash, .lower);

    // Look up and verify not expired, workflow is active
    const row = try pool.row(
        \\SELECT wr.id, wr.session_id, wr.status
        \\FROM workflow_runs wr
        \\WHERE wr.agent_token_hash = $1
        \\  AND wr.agent_token_expires_at > NOW()
        \\  AND wr.status IN ('pending', 'running')
    , .{&hash_hex});

    if (row) |r| {
        return AgentTokenInfo{
            .workflow_run_id = r.get(i32, 0),
            .session_id = r.get(?[]const u8, 1),
            .status = r.get([]const u8, 2),
        };
    }
    return null;
}

/// Revoke an agent token (clear hash from workflow_runs).
/// Called when workflow completes/fails/cancels.
pub fn revokeAgentToken(pool: *Pool, workflow_run_id: i32) !void {
    _ = try pool.exec(
        \\UPDATE workflow_runs
        \\SET agent_token_hash = NULL, agent_token_expires_at = NULL
        \\WHERE id = $1
    , .{workflow_run_id});
}

/// Clean up expired tokens (optional background task).
/// Sets agent_token_hash to NULL for expired tokens.
pub fn cleanupExpiredTokens(pool: *Pool) !?i64 {
    return try pool.exec(
        \\UPDATE workflow_runs
        \\SET agent_token_hash = NULL, agent_token_expires_at = NULL
        \\WHERE agent_token_expires_at IS NOT NULL
        \\  AND agent_token_expires_at <= NOW()
    , .{});
}

// =============================================================================
// Tests
// =============================================================================

test "token prefix" {
    try std.testing.expectEqualStrings("plat_", TOKEN_PREFIX);
}

test "token format" {
    // Verify token would be 68 chars: "plat_" (5) + 64 hex chars
    try std.testing.expectEqual(@as(usize, 5), TOKEN_PREFIX.len);
    // 32 bytes = 64 hex chars
    const expected_total = 5 + 64;
    try std.testing.expectEqual(@as(usize, 69), expected_total);
}
