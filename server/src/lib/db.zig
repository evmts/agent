//! Database layer
//!
//! Wraps pg.zig for PostgreSQL operations.

const std = @import("std");
const pg = @import("pg");

const log = std.log.scoped(.db);

// =============================================================================
// Duration constants (in milliseconds)
// =============================================================================

/// Session validity duration (30 days)
pub const SESSION_DURATION_MS: i64 = 30 * 24 * 60 * 60 * 1000;

/// Session auto-refresh threshold - refresh if expires within 7 days
pub const SESSION_REFRESH_THRESHOLD_MS: i64 = 7 * 24 * 60 * 60 * 1000;

/// Password reset token validity (1 hour)
pub const PASSWORD_RESET_TOKEN_DURATION_MS: i64 = 1 * 60 * 60 * 1000;

/// Email verification token validity (24 hours)
pub const EMAIL_VERIFICATION_TOKEN_DURATION_MS: i64 = 24 * 60 * 60 * 1000;

// =============================================================================
// Types
// =============================================================================

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

    // Session expiration time
    const expires_at = std.time.milliTimestamp() + SESSION_DURATION_MS;

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

pub fn cleanupExpiredSessions(pool: *Pool) !?i64 {
    return try pool.exec(
        \\DELETE FROM auth_sessions WHERE expires_at <= NOW()
    , .{});
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

// ============================================================================
// SSH Key operations
// ============================================================================

pub const SshKeyRecord = struct {
    id: i64,
    user_id: i64,
    name: []const u8,
    fingerprint: []const u8,
    key_type: []const u8,
    created_at: []const u8,
};

pub fn createSshKey(
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

pub fn getSshKeysByUserId(pool: *Pool, user_id: i64) ![]const SshKeyRecord {
    // Note: This is a simplified version - in production you'd want to use a proper query iterator
    _ = pool;
    _ = user_id;
    return error.NotImplemented;
}

pub fn getSshKeyByFingerprint(pool: *Pool, fingerprint: []const u8) !?SshKeyRecord {
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

pub fn deleteSshKey(pool: *Pool, key_id: i64, user_id: i64) !bool {
    const affected = try pool.exec(
        \\DELETE FROM ssh_keys WHERE id = $1 AND user_id = $2
    , .{ key_id, user_id });
    return affected != null and affected.? > 0;
}

pub fn getSshKeyById(pool: *Pool, key_id: i64, user_id: i64) !?SshKeyRecord {
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

// ============================================================================
// Access Token operations
// ============================================================================

pub const AccessTokenRecord = struct {
    id: i64,
    user_id: i64,
    name: []const u8,
    token_last_eight: []const u8,
    scopes: []const u8,
    created_at: []const u8,
    last_used_at: ?[]const u8,
};

pub fn createAccessToken(
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

pub fn deleteAccessToken(pool: *Pool, token_id: i64, user_id: i64) !bool {
    const affected = try pool.exec(
        \\DELETE FROM access_tokens WHERE id = $1 AND user_id = $2
    , .{ token_id, user_id });
    return affected != null and affected.? > 0;
}

pub fn validateAccessToken(pool: *Pool, token_hash: []const u8) !?UserRecord {
    // Update last_used_at and return user
    const row = try pool.row(
        \\UPDATE access_tokens
        \\SET last_used_at = NOW()
        \\WHERE token_hash = $1
        \\RETURNING user_id
    , .{token_hash});

    if (row) |r| {
        const user_id = r.get(i64, 0);
        return try getUserById(pool, user_id);
    }
    return null;
}

// ============================================================================
// User Profile operations
// ============================================================================

pub fn updateUserProfile(
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

// ============================================================================
// Agent Session operations (sessions table, not auth_sessions)
// ============================================================================

pub const AgentSessionRecord = struct {
    id: []const u8,
    project_id: []const u8,
    directory: []const u8,
    title: []const u8,
    version: []const u8,
    time_created: i64,
    time_updated: i64,
    time_archived: ?i64,
    parent_id: ?[]const u8,
    fork_point: ?[]const u8,
    summary: ?[]const u8, // JSONB as string
    revert: ?[]const u8, // JSONB as string
    compaction: ?[]const u8, // JSONB as string
    token_count: i32,
    bypass_mode: bool,
    model: ?[]const u8,
    reasoning_effort: ?[]const u8,
    ghost_commit: ?[]const u8, // JSONB as string
    plugins: []const u8, // JSONB as string
};

/// Get all agent sessions ordered by most recently updated
pub fn getAllAgentSessions(pool: *Pool, allocator: std.mem.Allocator) !std.ArrayList(AgentSessionRecord) {
    var sessions = try std.ArrayList(AgentSessionRecord).initCapacity(allocator, 0);

    var result = try pool.query(
        \\SELECT id, project_id, directory, title, version, time_created, time_updated,
        \\       time_archived, parent_id, fork_point, summary::text, revert::text,
        \\       compaction::text, token_count, bypass_mode, model, reasoning_effort,
        \\       ghost_commit::text, plugins::text
        \\FROM sessions
        \\ORDER BY time_updated DESC
    , .{});
    defer result.deinit();

    while (try result.next()) |row| {
        try sessions.append(allocator, AgentSessionRecord{
            .id = row.get([]const u8, 0),
            .project_id = row.get([]const u8, 1),
            .directory = row.get([]const u8, 2),
            .title = row.get([]const u8, 3),
            .version = row.get([]const u8, 4),
            .time_created = row.get(i64, 5),
            .time_updated = row.get(i64, 6),
            .time_archived = row.get(?i64, 7),
            .parent_id = row.get(?[]const u8, 8),
            .fork_point = row.get(?[]const u8, 9),
            .summary = row.get(?[]const u8, 10),
            .revert = row.get(?[]const u8, 11),
            .compaction = row.get(?[]const u8, 12),
            .token_count = row.get(i32, 13),
            .bypass_mode = row.get(bool, 14),
            .model = row.get(?[]const u8, 15),
            .reasoning_effort = row.get(?[]const u8, 16),
            .ghost_commit = row.get(?[]const u8, 17),
            .plugins = row.get([]const u8, 18),
        });
    }

    return sessions;
}

/// Get an agent session by ID
pub fn getAgentSessionById(pool: *Pool, session_id: []const u8) !?AgentSessionRecord {
    const row = try pool.row(
        \\SELECT id, project_id, directory, title, version, time_created, time_updated,
        \\       time_archived, parent_id, fork_point, summary::text, revert::text,
        \\       compaction::text, token_count, bypass_mode, model, reasoning_effort,
        \\       ghost_commit::text, plugins::text
        \\FROM sessions
        \\WHERE id = $1
    , .{session_id});

    if (row) |r| {
        return AgentSessionRecord{
            .id = r.get([]const u8, 0),
            .project_id = r.get([]const u8, 1),
            .directory = r.get([]const u8, 2),
            .title = r.get([]const u8, 3),
            .version = r.get([]const u8, 4),
            .time_created = r.get(i64, 5),
            .time_updated = r.get(i64, 6),
            .time_archived = r.get(?i64, 7),
            .parent_id = r.get(?[]const u8, 8),
            .fork_point = r.get(?[]const u8, 9),
            .summary = r.get(?[]const u8, 10),
            .revert = r.get(?[]const u8, 11),
            .compaction = r.get(?[]const u8, 12),
            .token_count = r.get(i32, 13),
            .bypass_mode = r.get(bool, 14),
            .model = r.get(?[]const u8, 15),
            .reasoning_effort = r.get(?[]const u8, 16),
            .ghost_commit = r.get(?[]const u8, 17),
            .plugins = r.get([]const u8, 18),
        };
    }
    return null;
}

/// Create a new agent session
pub fn createAgentSession(
    pool: *Pool,
    id: []const u8,
    directory: []const u8,
    title: []const u8,
    parent_id: ?[]const u8,
    bypass_mode: bool,
    model: ?[]const u8,
    reasoning_effort: ?[]const u8,
    plugins: []const u8,
) !void {
    const now = std.time.milliTimestamp();

    _ = try pool.exec(
        \\INSERT INTO sessions (
        \\  id, project_id, directory, title, version, time_created, time_updated,
        \\  parent_id, bypass_mode, model, reasoning_effort, plugins, token_count
        \\) VALUES ($1, 'default', $2, $3, '1.0.0', $4, $4, $5, $6, $7, $8, $9::jsonb, 0)
    , .{ id, directory, title, now, parent_id, bypass_mode, model, reasoning_effort, plugins });
}

/// Update agent session fields
pub fn updateAgentSession(
    pool: *Pool,
    session_id: []const u8,
    title: ?[]const u8,
    archived: ?bool,
    model: ?[]const u8,
    reasoning_effort: ?[]const u8,
) !void {
    const now = std.time.milliTimestamp();

    if (title) |t| {
        _ = try pool.exec(
            \\UPDATE sessions SET title = $1, time_updated = $2 WHERE id = $3
        , .{ t, now, session_id });
    }

    if (archived) |is_archived| {
        if (is_archived) {
            _ = try pool.exec(
                \\UPDATE sessions SET time_archived = $1, time_updated = $1 WHERE id = $2
            , .{ now, session_id });
        } else {
            _ = try pool.exec(
                \\UPDATE sessions SET time_archived = NULL, time_updated = $1 WHERE id = $2
            , .{ now, session_id });
        }
    }

    if (model) |m| {
        _ = try pool.exec(
            \\UPDATE sessions SET model = $1, time_updated = $2 WHERE id = $3
        , .{ m, now, session_id });
    }

    if (reasoning_effort) |re| {
        _ = try pool.exec(
            \\UPDATE sessions SET reasoning_effort = $1, time_updated = $2 WHERE id = $3
        , .{ re, now, session_id });
    }
}

/// Delete an agent session
pub fn deleteAgentSession(pool: *Pool, session_id: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM sessions WHERE id = $1
    , .{session_id});
}

// ============================================================================
// Message operations
// ============================================================================

pub const MessageRecord = struct {
    id: []const u8,
    session_id: []const u8,
    role: []const u8,
    time_created: i64,
    time_completed: ?i64,
    status: []const u8,
    thinking_text: ?[]const u8,
    error_message: ?[]const u8,
};

/// Get messages for a session
pub fn getAgentSessionMessages(pool: *Pool, allocator: std.mem.Allocator, session_id: []const u8) !std.ArrayList(MessageRecord) {
    var messages = try std.ArrayList(MessageRecord).initCapacity(allocator, 0);

    var result = try pool.query(
        \\SELECT id, session_id, role, time_created, time_completed, status,
        \\       thinking_text, error_message
        \\FROM messages
        \\WHERE session_id = $1
        \\ORDER BY time_created ASC
    , .{session_id});
    defer result.deinit();

    while (try result.next()) |row| {
        try messages.append(allocator, MessageRecord{
            .id = row.get([]const u8, 0),
            .session_id = row.get([]const u8, 1),
            .role = row.get([]const u8, 2),
            .time_created = row.get(i64, 3),
            .time_completed = row.get(?i64, 4),
            .status = row.get([]const u8, 5),
            .thinking_text = row.get(?[]const u8, 6),
            .error_message = row.get(?[]const u8, 7),
        });
    }

    return messages;
}

/// Get a message by ID
pub fn getMessageById(pool: *Pool, message_id: []const u8) !?MessageRecord {
    const row = try pool.row(
        \\SELECT id, session_id, role, time_created, time_completed, status,
        \\       thinking_text, error_message
        \\FROM messages
        \\WHERE id = $1
    , .{message_id});

    if (row) |r| {
        return MessageRecord{
            .id = r.get([]const u8, 0),
            .session_id = r.get([]const u8, 1),
            .role = r.get([]const u8, 2),
            .time_created = r.get(i64, 3),
            .time_completed = r.get(?i64, 4),
            .status = r.get([]const u8, 5),
            .thinking_text = r.get(?[]const u8, 6),
            .error_message = r.get(?[]const u8, 7),
        };
    }
    return null;
}

/// Create a new message
pub fn createMessage(
    pool: *Pool,
    id: []const u8,
    session_id: []const u8,
    role: []const u8,
    status: []const u8,
    thinking_text: ?[]const u8,
    error_message: ?[]const u8,
) !void {
    const now = std.time.milliTimestamp();

    _ = try pool.exec(
        \\INSERT INTO messages (
        \\  id, session_id, role, time_created, status, thinking_text, error_message
        \\) VALUES ($1, $2, $3, $4, $5, $6, $7)
    , .{ id, session_id, role, now, status, thinking_text, error_message });
}

/// Update a message
pub fn updateMessage(
    pool: *Pool,
    message_id: []const u8,
    status: ?[]const u8,
    thinking_text: ?[]const u8,
    error_message: ?[]const u8,
    time_completed: ?i64,
) !void {
    if (status) |s| {
        _ = try pool.exec(
            \\UPDATE messages SET status = $1 WHERE id = $2
        , .{ s, message_id });
    }

    if (thinking_text) |tt| {
        _ = try pool.exec(
            \\UPDATE messages SET thinking_text = $1 WHERE id = $2
        , .{ tt, message_id });
    }

    if (error_message) |em| {
        _ = try pool.exec(
            \\UPDATE messages SET error_message = $1 WHERE id = $2
        , .{ em, message_id });
    }

    if (time_completed) |tc| {
        _ = try pool.exec(
            \\UPDATE messages SET time_completed = $1 WHERE id = $2
        , .{ tc, message_id });
    }
}

/// Delete a message
pub fn deleteMessage(pool: *Pool, message_id: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM messages WHERE id = $1
    , .{message_id});
}

// ============================================================================
// Part operations
// ============================================================================

pub const PartRecord = struct {
    id: []const u8,
    session_id: []const u8,
    message_id: []const u8,
    type_: []const u8,
    text: ?[]const u8,
    tool_name: ?[]const u8,
    tool_state: ?[]const u8,
    mime: ?[]const u8,
    url: ?[]const u8,
    filename: ?[]const u8,
    time_start: ?i64,
    time_end: ?i64,
    sort_order: i32,
};

/// Get parts for a message
pub fn getMessageParts(pool: *Pool, allocator: std.mem.Allocator, message_id: []const u8) !std.ArrayList(PartRecord) {
    var parts = try std.ArrayList(PartRecord).initCapacity(allocator, 0);

    var result = try pool.query(
        \\SELECT id, session_id, message_id, type, text, tool_name,
        \\       tool_state::text, mime, url, filename, time_start, time_end, sort_order
        \\FROM parts
        \\WHERE message_id = $1
        \\ORDER BY sort_order ASC
    , .{message_id});
    defer result.deinit();

    while (try result.next()) |row| {
        try parts.append(allocator, PartRecord{
            .id = row.get([]const u8, 0),
            .session_id = row.get([]const u8, 1),
            .message_id = row.get([]const u8, 2),
            .type_ = row.get([]const u8, 3),
            .text = row.get(?[]const u8, 4),
            .tool_name = row.get(?[]const u8, 5),
            .tool_state = row.get(?[]const u8, 6),
            .mime = row.get(?[]const u8, 7),
            .url = row.get(?[]const u8, 8),
            .filename = row.get(?[]const u8, 9),
            .time_start = row.get(?i64, 10),
            .time_end = row.get(?i64, 11),
            .sort_order = row.get(i32, 12),
        });
    }

    return parts;
}

/// Get a part by ID
pub fn getPartById(pool: *Pool, part_id: []const u8) !?PartRecord {
    const row = try pool.row(
        \\SELECT id, session_id, message_id, type, text, tool_name,
        \\       tool_state::text, mime, url, filename, time_start, time_end, sort_order
        \\FROM parts
        \\WHERE id = $1
    , .{part_id});

    if (row) |r| {
        return PartRecord{
            .id = r.get([]const u8, 0),
            .session_id = r.get([]const u8, 1),
            .message_id = r.get([]const u8, 2),
            .type_ = r.get([]const u8, 3),
            .text = r.get(?[]const u8, 4),
            .tool_name = r.get(?[]const u8, 5),
            .tool_state = r.get(?[]const u8, 6),
            .mime = r.get(?[]const u8, 7),
            .url = r.get(?[]const u8, 8),
            .filename = r.get(?[]const u8, 9),
            .time_start = r.get(?i64, 10),
            .time_end = r.get(?i64, 11),
            .sort_order = r.get(i32, 12),
        };
    }
    return null;
}

/// Create a new part
pub fn createPart(
    pool: *Pool,
    id: []const u8,
    session_id: []const u8,
    message_id: []const u8,
    type_: []const u8,
    text: ?[]const u8,
    tool_name: ?[]const u8,
    tool_state: ?[]const u8,
    mime: ?[]const u8,
    url: ?[]const u8,
    filename: ?[]const u8,
    sort_order: i32,
    time_start: ?i64,
    time_end: ?i64,
) !void {
    _ = try pool.exec(
        \\INSERT INTO parts (
        \\  id, session_id, message_id, type, text, tool_name, tool_state,
        \\  mime, url, filename, sort_order, time_start, time_end
        \\) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11, $12, $13)
    , .{ id, session_id, message_id, type_, text, tool_name, tool_state, mime, url, filename, sort_order, time_start, time_end });
}

/// Update a part
pub fn updatePart(
    pool: *Pool,
    part_id: []const u8,
    text: ?[]const u8,
    tool_state: ?[]const u8,
    time_start: ?i64,
    time_end: ?i64,
) !void {
    if (text) |t| {
        _ = try pool.exec(
            \\UPDATE parts SET text = $1 WHERE id = $2
        , .{ t, part_id });
    }

    if (tool_state) |ts| {
        _ = try pool.exec(
            \\UPDATE parts SET tool_state = $1::jsonb WHERE id = $2
        , .{ ts, part_id });
    }

    if (time_start) |ts| {
        _ = try pool.exec(
            \\UPDATE parts SET time_start = $1 WHERE id = $2
        , .{ ts, part_id });
    }

    if (time_end) |te| {
        _ = try pool.exec(
            \\UPDATE parts SET time_end = $1 WHERE id = $2
        , .{ te, part_id });
    }
}

/// Delete a part
pub fn deletePart(pool: *Pool, part_id: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM parts WHERE id = $1
    , .{part_id});
}

// ============================================================================
// Repository operations
// ============================================================================

pub const Repository = struct {
    id: i64,
    user_id: i64,
    name: []const u8,
    description: ?[]const u8,
    is_public: bool,
    default_branch: ?[]const u8,
    topics: ?[][]const u8,
};

pub fn getRepositoryByUserAndName(pool: *Pool, username: []const u8, repo_name: []const u8) !?Repository {
    const row = try pool.row(
        \\SELECT r.id, r.user_id, r.name, r.description, r.is_public, r.default_branch, r.topics
        \\FROM repositories r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE u.username = $1 AND r.name = $2
    , .{ username, repo_name });

    if (row) |r| {
        return Repository{
            .id = r.get(i64, 0),
            .user_id = r.get(i64, 1),
            .name = r.get([]const u8, 2),
            .description = r.get(?[]const u8, 3),
            .is_public = r.get(bool, 4),
            .default_branch = r.get(?[]const u8, 5),
            .topics = r.get(?[][]const u8, 6),
        };
    }
    return null;
}

pub fn updateRepositoryTopics(pool: *Pool, repo_id: i64, topics: [][]const u8) !void {
    _ = try pool.exec(
        \\UPDATE repositories SET topics = $1, updated_at = NOW()
        \\WHERE id = $2
    , .{ topics, repo_id });
}

// ============================================================================
// Stars operations
// ============================================================================

pub const Stargazer = struct {
    id: i64,
    username: []const u8,
    display_name: ?[]const u8,
    created_at: []const u8,
};

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

    return stargazers.toOwnedSlice();
}

pub fn hasStarred(pool: *Pool, user_id: i64, repo_id: i64) !bool {
    const row = try pool.row(
        \\SELECT 1 FROM stars WHERE user_id = $1 AND repository_id = $2
    , .{ user_id, repo_id });

    return row != null;
}

pub fn createStar(pool: *Pool, user_id: i64, repo_id: i64) !void {
    _ = try pool.exec(
        \\INSERT INTO stars (user_id, repository_id) VALUES ($1, $2)
    , .{ user_id, repo_id });
}

pub fn deleteStar(pool: *Pool, user_id: i64, repo_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM stars WHERE user_id = $1 AND repository_id = $2
    , .{ user_id, repo_id });
}

pub fn getStarCount(pool: *Pool, repo_id: i64) !i64 {
    const row = try pool.row(
        \\SELECT COUNT(*) as count FROM stars WHERE repository_id = $1
    , .{repo_id});

    if (row) |r| {
        return r.get(i64, 0);
    }
    return 0;
}

// ============================================================================
// Watches operations
// ============================================================================

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

// ============================================================================
// Bookmarks operations (jj branches)
// ============================================================================

pub const Bookmark = struct {
    id: i64,
    name: []const u8,
    target_change_id: []const u8,
    is_default: bool,
};

pub fn listBookmarks(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64) ![]Bookmark {
    var result = try pool.query(
        \\SELECT id, name, target_change_id, is_default
        \\FROM bookmarks
        \\WHERE repository_id = $1
        \\ORDER BY CASE WHEN is_default THEN 0 ELSE 1 END, updated_at DESC
    , .{repo_id});
    defer result.deinit();

    var bookmarks = try std.ArrayList(Bookmark).initCapacity(allocator, 0);
    errdefer bookmarks.deinit(allocator);

    while (try result.next()) |row| {
        try bookmarks.append(allocator, Bookmark{
            .id = row.get(i64, 0),
            .name = row.get([]const u8, 1),
            .target_change_id = row.get([]const u8, 2),
            .is_default = row.get(bool, 3),
        });
    }

    return bookmarks.toOwnedSlice();
}

pub fn getBookmarkByName(pool: *Pool, repo_id: i64, name: []const u8) !?Bookmark {
    const row = try pool.row(
        \\SELECT id, name, target_change_id, is_default
        \\FROM bookmarks
        \\WHERE repository_id = $1 AND name = $2
    , .{ repo_id, name });

    if (row) |r| {
        return Bookmark{
            .id = r.get(i64, 0),
            .name = r.get([]const u8, 1),
            .target_change_id = r.get([]const u8, 2),
            .is_default = r.get(bool, 3),
        };
    }
    return null;
}

pub fn createBookmark(pool: *Pool, repo_id: i64, name: []const u8, target_change_id: []const u8, pusher_id: i64) !i64 {
    const row = try pool.row(
        \\INSERT INTO bookmarks (repository_id, name, target_change_id, pusher_id)
        \\VALUES ($1, $2, $3, $4)
        \\RETURNING id
    , .{ repo_id, name, target_change_id, pusher_id });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn updateBookmark(pool: *Pool, repo_id: i64, name: []const u8, target_change_id: []const u8, pusher_id: i64) !void {
    _ = try pool.exec(
        \\UPDATE bookmarks
        \\SET target_change_id = $1, updated_at = NOW(), pusher_id = $2
        \\WHERE repository_id = $3 AND name = $4
    , .{ target_change_id, pusher_id, repo_id, name });
}

pub fn deleteBookmark(pool: *Pool, repo_id: i64, name: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM bookmarks WHERE repository_id = $1 AND name = $2
    , .{ repo_id, name });
}

pub fn setDefaultBookmark(pool: *Pool, repo_id: i64, name: []const u8) !void {
    // Clear all existing defaults for this repository
    _ = try pool.exec(
        \\UPDATE bookmarks SET is_default = false WHERE repository_id = $1
    , .{repo_id});

    // Set the new default
    _ = try pool.exec(
        \\UPDATE bookmarks SET is_default = true WHERE repository_id = $1 AND name = $2
    , .{ repo_id, name });

    // Also update the repository's default_bookmark field
    _ = try pool.exec(
        \\UPDATE repositories SET default_bookmark = $1 WHERE id = $2
    , .{ name, repo_id });
}

// ============================================================================
// Changes operations (jj changes)
// ============================================================================

pub const Change = struct {
    change_id: []const u8,
    commit_id: []const u8,
    description: []const u8,
};

pub fn listChanges(pool: *Pool, allocator: std.mem.Allocator, repo_id: i64) ![]Change {
    var result = try pool.query(
        \\SELECT change_id, commit_id, description
        \\FROM changes
        \\WHERE repository_id = $1
        \\ORDER BY timestamp DESC
        \\LIMIT 50
    , .{repo_id});
    defer result.deinit();

    var changes = try std.ArrayList(Change).initCapacity(allocator, 0);
    errdefer changes.deinit(allocator);

    while (try result.next()) |row| {
        try changes.append(allocator, Change{
            .change_id = row.get([]const u8, 0),
            .commit_id = row.get([]const u8, 1),
            .description = row.get([]const u8, 2),
        });
    }

    return changes.toOwnedSlice();
}

pub fn getChangeById(pool: *Pool, repo_id: i64, change_id: []const u8) !?Change {
    const row = try pool.row(
        \\SELECT change_id, commit_id, description
        \\FROM changes
        \\WHERE repository_id = $1 AND change_id = $2
    , .{ repo_id, change_id });

    if (row) |r| {
        return Change{
            .change_id = r.get([]const u8, 0),
            .commit_id = r.get([]const u8, 1),
            .description = r.get([]const u8, 2),
        };
    }
    return null;
}

// ============================================================================
// Repository operations
// ============================================================================

pub fn getRepositoryId(pool: *Pool, username: []const u8, repo_name: []const u8) !?i64 {
    const row = try pool.row(
        \\SELECT r.id FROM repositories r
        \\JOIN users u ON r.owner_id = u.id
        \\WHERE u.lower_username = lower($1) AND lower(r.name) = lower($2)
    , .{ username, repo_name });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return null;
}

// ============================================================================
// Workflow operations
// ============================================================================

pub const WorkflowRun = struct {
    id: i64,
    run_number: i32,
    title: []const u8,
    status: []const u8,
    trigger_event: []const u8,
    created_at: []const u8,
};

pub const WorkflowJob = struct {
    id: i64,
    name: []const u8,
    job_id: []const u8,
    status: []const u8,
};

pub const WorkflowTask = struct {
    id: i64,
    job_id: i64,
    attempt: i32,
    repository_id: i64,
    commit_sha: ?[]const u8,
    workflow_content: []const u8,
    workflow_path: []const u8,
};

pub const WorkflowLog = struct {
    content: []const u8,
};

pub const Runner = struct {
    id: i64,
    name: []const u8,
};

pub fn listWorkflowRuns(
    pool: *Pool,
    allocator: std.mem.Allocator,
    repository_id: i64,
    status_filter: ?i32,
    limit: i32,
    offset: i32,
) ![]WorkflowRun {
    var conn = try pool.acquire();
    defer conn.release();

    var query_buf: [1024]u8 = undefined;
    const query = if (status_filter) |status|
        try std.fmt.bufPrint(&query_buf,
            \\SELECT id, run_number, title, status, trigger_event,
            \\       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as created_at
            \\FROM workflow_runs
            \\WHERE repository_id = $1 AND status = {d}
            \\ORDER BY run_number DESC
            \\LIMIT $2 OFFSET $3
        , .{status})
    else
        try std.fmt.bufPrint(&query_buf,
            \\SELECT id, run_number, title, status, trigger_event,
            \\       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as created_at
            \\FROM workflow_runs
            \\WHERE repository_id = $1
            \\ORDER BY run_number DESC
            \\LIMIT $2 OFFSET $3
        , .{});

    var result = try conn.query(query, .{ repository_id, limit, offset });
    defer result.deinit();

    var runs = try std.ArrayList(WorkflowRun).initCapacity(allocator, 0);
    defer runs.deinit(allocator);

    while (try result.next()) |row| {
        try runs.append(allocator, .{
            .id = row.get(i64, 0),
            .run_number = row.get(i32, 1),
            .title = try allocator.dupe(u8, row.get([]const u8, 2)),
            .status = try allocator.dupe(u8, row.get([]const u8, 3)),
            .trigger_event = try allocator.dupe(u8, row.get([]const u8, 4)),
            .created_at = try allocator.dupe(u8, row.get([]const u8, 5)),
        });
    }

    return try runs.toOwnedSlice();
}

pub fn getWorkflowRun(pool: *Pool, allocator: std.mem.Allocator, run_id: i64) !?WorkflowRun {
    const row = try pool.row(
        \\SELECT id, run_number, title, status, trigger_event,
        \\       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as created_at
        \\FROM workflow_runs
        \\WHERE id = $1
    , .{run_id});

    if (row) |r| {
        return WorkflowRun{
            .id = r.get(i64, 0),
            .run_number = r.get(i32, 1),
            .title = try allocator.dupe(u8, r.get([]const u8, 2)),
            .status = try allocator.dupe(u8, r.get([]const u8, 3)),
            .trigger_event = try allocator.dupe(u8, r.get([]const u8, 4)),
            .created_at = try allocator.dupe(u8, r.get([]const u8, 5)),
        };
    }
    return null;
}

pub fn getWorkflowJobs(pool: *Pool, allocator: std.mem.Allocator, run_id: i64) ![]WorkflowJob {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, name, job_id, status
        \\FROM workflow_jobs
        \\WHERE run_id = $1
        \\ORDER BY id
    , .{run_id});
    defer result.deinit();

    var jobs = try std.ArrayList(WorkflowJob).initCapacity(allocator, 0);
    defer jobs.deinit(allocator);

    while (try result.next()) |row| {
        try jobs.append(allocator, .{
            .id = row.get(i64, 0),
            .name = try allocator.dupe(u8, row.get([]const u8, 1)),
            .job_id = try allocator.dupe(u8, row.get([]const u8, 2)),
            .status = try allocator.dupe(u8, row.get([]const u8, 3)),
        });
    }

    return try jobs.toOwnedSlice();
}

pub fn createWorkflowRun(
    pool: *Pool,
    repository_id: i64,
    workflow_definition_id: ?i64,
    title: []const u8,
    trigger_event: []const u8,
    trigger_user_id: i64,
    ref: ?[]const u8,
    commit_sha: ?[]const u8,
) !i64 {
    // Get next run number
    const row = try pool.row(
        \\SELECT COALESCE(MAX(run_number), 0) + 1 FROM workflow_runs WHERE repository_id = $1
    , .{repository_id});

    const run_number = if (row) |r| r.get(i32, 0) else 1;

    const insert_row = try pool.row(
        \\INSERT INTO workflow_runs
        \\(repository_id, workflow_definition_id, run_number, title, trigger_event,
        \\ trigger_user_id, ref, commit_sha, status, created_at)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 5, NOW())
        \\RETURNING id
    , .{ repository_id, workflow_definition_id, run_number, title, trigger_event, trigger_user_id, ref, commit_sha });

    if (insert_row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn updateWorkflowRunStatus(pool: *Pool, run_id: i64, status: i32) !void {
    const status_int = status;
    _ = try pool.exec(
        \\UPDATE workflow_runs
        \\SET status = $1,
        \\    stopped_at = CASE WHEN $1 IN (1, 2, 3, 4) THEN NOW() ELSE stopped_at END,
        \\    updated_at = NOW()
        \\WHERE id = $2
    , .{ status_int, run_id });
}

pub fn getWorkflowLogs(
    pool: *Pool,
    allocator: std.mem.Allocator,
    run_id: i64,
    step_filter: ?i32,
) ![]WorkflowLog {
    var conn = try pool.acquire();
    defer conn.release();

    var result = if (step_filter) |step|
        try conn.query(
            \\SELECT l.content FROM workflow_logs l
            \\JOIN workflow_tasks t ON l.task_id = t.id
            \\JOIN workflow_jobs j ON t.job_id = j.id
            \\WHERE j.run_id = $1 AND l.step_index = $2
            \\ORDER BY l.task_id, l.line_number
        , .{ run_id, step })
    else
        try conn.query(
            \\SELECT l.content FROM workflow_logs l
            \\JOIN workflow_tasks t ON l.task_id = t.id
            \\JOIN workflow_jobs j ON t.job_id = j.id
            \\WHERE j.run_id = $1
            \\ORDER BY l.task_id, l.line_number
        , .{run_id});
    defer result.deinit();

    var logs = try std.ArrayList(WorkflowLog).initCapacity(allocator, 0);
    defer logs.deinit(allocator);

    while (try result.next()) |row| {
        try logs.append(allocator, .{
            .content = try allocator.dupe(u8, row.get([]const u8, 0)),
        });
    }

    return try logs.toOwnedSlice();
}

// ============================================================================
// Runner operations
// ============================================================================

pub fn createRunner(
    pool: *Pool,
    name: []const u8,
    version: ?[]const u8,
    labels: ?[]const []const u8,
    token_hash: []const u8,
) !i64 {
    // Convert labels to JSON array if provided
    const labels_json = if (labels) |l| blk: {
        var json_buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&json_buf);
        var writer = fbs.writer();
        try writer.writeByte('[');
        for (l, 0..) |label, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("\"{s}\"", .{label});
        }
        try writer.writeByte(']');
        break :blk fbs.getWritten();
    } else "[]";

    const row = try pool.row(
        \\INSERT INTO workflow_runners (name, version, labels, token_hash, status, created_at, last_online_at)
        \\VALUES ($1, $2, $3::jsonb, $4, 0, NOW(), NOW())
        \\RETURNING id
    , .{ name, version, labels_json, token_hash });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn getRunnerByToken(pool: *Pool, token_hash: []const u8) !?Runner {
    const row = try pool.row(
        \\SELECT id, name FROM workflow_runners WHERE token_hash = $1
    , .{token_hash});

    if (row) |r| {
        return Runner{
            .id = r.get(i64, 0),
            .name = r.get([]const u8, 1),
        };
    }
    return null;
}

pub fn updateRunnerHeartbeat(pool: *Pool, token_hash: []const u8) !void {
    _ = try pool.exec(
        \\UPDATE workflow_runners SET last_online_at = NOW(), status = 1 WHERE token_hash = $1
    , .{token_hash});
}

pub fn findAvailableTask(pool: *Pool, allocator: std.mem.Allocator, runner_id: i64) !?WorkflowTask {
    _ = runner_id; // For now, ignore runner_id (in production would match labels)

    const row = try pool.row(
        \\SELECT t.id, t.job_id, t.attempt, t.repository_id, t.commit_sha,
        \\       COALESCE(t.workflow_content, '') as workflow_content,
        \\       COALESCE(t.workflow_path, '') as workflow_path
        \\FROM workflow_tasks t
        \\JOIN workflow_jobs j ON t.job_id = j.id
        \\WHERE t.status = 5 AND t.runner_id IS NULL
        \\ORDER BY t.id
        \\LIMIT 1
        \\FOR UPDATE SKIP LOCKED
    , .{});

    if (row) |r| {
        return WorkflowTask{
            .id = r.get(i64, 0),
            .job_id = r.get(i64, 1),
            .attempt = r.get(i32, 2),
            .repository_id = r.get(i64, 3),
            .commit_sha = r.get(?[]const u8, 4),
            .workflow_content = try allocator.dupe(u8, r.get([]const u8, 5)),
            .workflow_path = try allocator.dupe(u8, r.get([]const u8, 6)),
        };
    }
    return null;
}

pub fn assignTaskToRunner(pool: *Pool, task_id: i64, runner_id: i64, token_hash: []const u8) !void {
    _ = try pool.exec(
        \\UPDATE workflow_tasks
        \\SET runner_id = $1, token_hash = $2, status = 6, started_at = NOW()
        \\WHERE id = $3
    , .{ runner_id, token_hash, task_id });
}

pub fn getTaskByToken(pool: *Pool, allocator: std.mem.Allocator, token_hash: []const u8) !?WorkflowTask {
    const row = try pool.row(
        \\SELECT id, job_id, attempt, repository_id, commit_sha,
        \\       COALESCE(workflow_content, '') as workflow_content,
        \\       COALESCE(workflow_path, '') as workflow_path
        \\FROM workflow_tasks
        \\WHERE token_hash = $1
    , .{token_hash});

    if (row) |r| {
        return WorkflowTask{
            .id = r.get(i64, 0),
            .job_id = r.get(i64, 1),
            .attempt = r.get(i32, 2),
            .repository_id = r.get(i64, 3),
            .commit_sha = r.get(?[]const u8, 4),
            .workflow_content = try allocator.dupe(u8, r.get([]const u8, 5)),
            .workflow_path = try allocator.dupe(u8, r.get([]const u8, 6)),
        };
    }
    return null;
}

/// Free a WorkflowTask's allocated strings
pub fn freeWorkflowTask(allocator: std.mem.Allocator, task: *WorkflowTask) void {
    allocator.free(task.workflow_content);
    allocator.free(task.workflow_path);
}

pub fn updateTaskStatus(pool: *Pool, task_id: i64, status: i32) !void {
    const status_int = status;
    _ = try pool.exec(
        \\UPDATE workflow_tasks
        \\SET status = $1,
        \\    stopped_at = CASE WHEN $1 IN (1, 2, 3, 4) THEN NOW() ELSE stopped_at END
        \\WHERE id = $2
    , .{ status_int, task_id });
}

pub fn updateJobStatusFromTask(pool: *Pool, job_id: i64, status: i32) !void {
    const status_int = status;
    _ = try pool.exec(
        \\UPDATE workflow_jobs
        \\SET status = $1,
        \\    stopped_at = CASE WHEN $1 IN (1, 2, 3, 4) THEN NOW() ELSE stopped_at END
        \\WHERE id = $2
    , .{ status_int, job_id });
}

pub fn appendWorkflowLogs(pool: *Pool, task_id: i64, step_index: i32, lines: []const []const u8) !void {
    var conn = try pool.acquire();
    defer conn.release();

    // Get current max line number for this task/step
    var result = try conn.query(
        \\SELECT COALESCE(MAX(line_number), 0) FROM workflow_logs
        \\WHERE task_id = $1 AND step_index = $2
    , .{ task_id, step_index });
    defer result.deinit();

    var line_number: i32 = 0;
    if (try result.next()) |r| {
        line_number = r.get(i32, 0);
    }

    // Insert each line
    for (lines) |line| {
        line_number += 1;
        _ = try conn.exec(
            \\INSERT INTO workflow_logs (task_id, step_index, line_number, content, timestamp)
            \\VALUES ($1, $2, $3, $4, NOW())
        , .{ task_id, step_index, line_number, line });
    }
}

// ============================================================================
// Landing Queue operations
// ============================================================================

pub const LandingRequest = struct {
    id: i64,
    repository_id: i64,
    change_id: []const u8,
    target_bookmark: []const u8,
    title: ?[]const u8,
    description: ?[]const u8,
    author_id: i64,
    status: []const u8,
    has_conflicts: bool,
    conflicted_files: ?[][]const u8,
    created_at: i64,
    updated_at: i64,
    landed_at: ?i64,
    landed_by: ?i64,
    landed_change_id: ?[]const u8,
};

pub const LandingReview = struct {
    id: i64,
    landing_id: i64,
    reviewer_id: i64,
    review_type: []const u8,
    content: ?[]const u8,
    change_id: []const u8,
    created_at: i64,
};

pub const LineComment = struct {
    id: i64,
    landing_id: i64,
    author_id: i64,
    file_path: []const u8,
    line_number: i32,
    side: []const u8,
    body: []const u8,
    resolved: bool,
    created_at: i64,
    updated_at: i64,
};

pub fn listLandingRequests(
    pool: *Pool,
    allocator: std.mem.Allocator,
    repository_id: i64,
    status_filter: ?[]const u8,
    limit: i32,
    offset: i32,
) ![]LandingRequest {
    var conn = try pool.acquire();
    defer conn.release();

    const result = if (status_filter) |status|
        try conn.query(
            \\SELECT id, repository_id, change_id, target_bookmark, title, description,
            \\       author_id, status, has_conflicts, conflicted_files,
            \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
            \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
            \\       EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
            \\       landed_by, landed_change_id
            \\FROM landing_queue
            \\WHERE repository_id = $1 AND status = $2
            \\ORDER BY created_at DESC
            \\LIMIT $3 OFFSET $4
        , .{ repository_id, status, limit, offset })
    else
        try conn.query(
            \\SELECT id, repository_id, change_id, target_bookmark, title, description,
            \\       author_id, status, has_conflicts, conflicted_files,
            \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
            \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
            \\       EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
            \\       landed_by, landed_change_id
            \\FROM landing_queue
            \\WHERE repository_id = $1
            \\ORDER BY CASE WHEN status IN ('pending', 'checking', 'ready') THEN 0 ELSE 1 END,
            \\         created_at DESC
            \\LIMIT $2 OFFSET $3
        , .{ repository_id, limit, offset });
    defer result.deinit();

    var requests = std.ArrayList(LandingRequest).init(allocator);
    errdefer requests.deinit();

    var iter = result.iterator();
    while (try iter.next()) |row| {
        try requests.append(LandingRequest{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .change_id = row.get([]const u8, 2),
            .target_bookmark = row.get([]const u8, 3),
            .title = row.get(?[]const u8, 4),
            .description = row.get(?[]const u8, 5),
            .author_id = row.get(i64, 6),
            .status = row.get([]const u8, 7),
            .has_conflicts = row.get(bool, 8),
            .conflicted_files = null, // PostgreSQL array type needs special handling
            .created_at = row.get(i64, 10),
            .updated_at = row.get(i64, 11),
            .landed_at = row.get(?i64, 12),
            .landed_by = row.get(?i64, 13),
            .landed_change_id = row.get(?[]const u8, 14),
        });
    }

    return requests.toOwnedSlice(allocator);
}

pub fn countLandingRequests(pool: *Pool, repository_id: i64, status_filter: ?[]const u8) !i64 {
    const row = if (status_filter) |status|
        try pool.row(
            \\SELECT COUNT(*) FROM landing_queue WHERE repository_id = $1 AND status = $2
        , .{ repository_id, status })
    else
        try pool.row(
            \\SELECT COUNT(*) FROM landing_queue WHERE repository_id = $1
        , .{repository_id});

    if (row) |r| {
        return r.get(i64, 0);
    }
    return 0;
}

pub fn getLandingRequestById(pool: *Pool, repository_id: i64, landing_id: i64) !?LandingRequest {
    const row = try pool.row(
        \\SELECT id, repository_id, change_id, target_bookmark, title, description,
        \\       author_id, status, has_conflicts, conflicted_files,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
        \\       EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
        \\       landed_by, landed_change_id
        \\FROM landing_queue
        \\WHERE repository_id = $1 AND id = $2
    , .{ repository_id, landing_id });

    if (row) |r| {
        return LandingRequest{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .change_id = r.get([]const u8, 2),
            .target_bookmark = r.get([]const u8, 3),
            .title = r.get(?[]const u8, 4),
            .description = r.get(?[]const u8, 5),
            .author_id = r.get(i64, 6),
            .status = r.get([]const u8, 7),
            .has_conflicts = r.get(bool, 8),
            .conflicted_files = null, // PostgreSQL array type needs special handling
            .created_at = r.get(i64, 10),
            .updated_at = r.get(i64, 11),
            .landed_at = r.get(?i64, 12),
            .landed_by = r.get(?i64, 13),
            .landed_change_id = r.get(?[]const u8, 14),
        };
    }
    return null;
}

pub fn findLandingRequestByChangeId(pool: *Pool, repository_id: i64, change_id: []const u8) !?LandingRequest {
    const row = try pool.row(
        \\SELECT id, repository_id, change_id, target_bookmark, title, description,
        \\       author_id, status, has_conflicts, conflicted_files,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
        \\       EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
        \\       landed_by, landed_change_id
        \\FROM landing_queue
        \\WHERE repository_id = $1 AND change_id = $2 AND status NOT IN ('landed', 'cancelled')
    , .{ repository_id, change_id });

    if (row) |r| {
        return LandingRequest{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .change_id = r.get([]const u8, 2),
            .target_bookmark = r.get([]const u8, 3),
            .title = r.get(?[]const u8, 4),
            .description = r.get(?[]const u8, 5),
            .author_id = r.get(i64, 6),
            .status = r.get([]const u8, 7),
            .has_conflicts = r.get(bool, 8),
            .conflicted_files = null, // PostgreSQL array type needs special handling
            .created_at = r.get(i64, 10),
            .updated_at = r.get(i64, 11),
            .landed_at = r.get(?i64, 12),
            .landed_by = r.get(?i64, 13),
            .landed_change_id = r.get(?[]const u8, 14),
        };
    }
    return null;
}

pub fn createLandingRequest(
    pool: *Pool,
    repository_id: i64,
    change_id: []const u8,
    target_bookmark: []const u8,
    title: ?[]const u8,
    description: ?[]const u8,
    author_id: i64,
) !LandingRequest {
    const row = try pool.row(
        \\INSERT INTO landing_queue (
        \\  repository_id, change_id, target_bookmark, title, description,
        \\  author_id, status, has_conflicts
        \\) VALUES ($1, $2, $3, $4, $5, $6, 'pending', false)
        \\RETURNING id, repository_id, change_id, target_bookmark, title, description,
        \\          author_id, status, has_conflicts, conflicted_files,
        \\          EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\          EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
        \\          EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
        \\          landed_by, landed_change_id
    , .{ repository_id, change_id, target_bookmark, title, description, author_id });

    if (row) |r| {
        return LandingRequest{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .change_id = r.get([]const u8, 2),
            .target_bookmark = r.get([]const u8, 3),
            .title = r.get(?[]const u8, 4),
            .description = r.get(?[]const u8, 5),
            .author_id = r.get(i64, 6),
            .status = r.get([]const u8, 7),
            .has_conflicts = r.get(bool, 8),
            .conflicted_files = null, // PostgreSQL array type needs special handling
            .created_at = r.get(i64, 10),
            .updated_at = r.get(i64, 11),
            .landed_at = r.get(?i64, 12),
            .landed_by = r.get(?i64, 13),
            .landed_change_id = r.get(?[]const u8, 14),
        };
    }
    return error.InsertFailed;
}

pub fn updateLandingRequestStatus(pool: *Pool, landing_id: i64, status: []const u8) !void {
    _ = try pool.exec(
        \\UPDATE landing_queue SET status = $1, updated_at = NOW() WHERE id = $2
    , .{ status, landing_id });
}

pub fn updateLandingRequestConflicts(
    pool: *Pool,
    landing_id: i64,
    has_conflicts: bool,
    conflicted_files: []const []const u8,
) !void {
    _ = try pool.exec(
        \\UPDATE landing_queue
        \\SET has_conflicts = $1, conflicted_files = $2, updated_at = NOW()
        \\WHERE id = $3
    , .{ has_conflicts, conflicted_files, landing_id });
}

pub fn markLandingRequestLanded(
    pool: *Pool,
    landing_id: i64,
    landed_by: i64,
    landed_change_id: []const u8,
) !void {
    _ = try pool.exec(
        \\UPDATE landing_queue
        \\SET status = 'landed', landed_at = NOW(), landed_by = $1,
        \\    landed_change_id = $2, updated_at = NOW()
        \\WHERE id = $3
    , .{ landed_by, landed_change_id, landing_id });
}

pub fn getLandingReviews(pool: *Pool, allocator: std.mem.Allocator, landing_id: i64) ![]LandingReview {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, landing_id, reviewer_id, type, content, change_id,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at
        \\FROM landing_reviews
        \\WHERE landing_id = $1
        \\ORDER BY created_at ASC
    , .{landing_id});
    defer result.deinit();

    var reviews = std.ArrayList(LandingReview).init(allocator);
    errdefer reviews.deinit();

    var iter = result.iterator();
    while (try iter.next()) |row| {
        try reviews.append(LandingReview{
            .id = row.get(i64, 0),
            .landing_id = row.get(i64, 1),
            .reviewer_id = row.get(i64, 2),
            .review_type = row.get([]const u8, 3),
            .content = row.get(?[]const u8, 4),
            .change_id = row.get([]const u8, 5),
            .created_at = row.get(i64, 6),
        });
    }

    return reviews.toOwnedSlice(allocator);
}

pub fn createLandingReview(
    pool: *Pool,
    landing_id: i64,
    reviewer_id: i64,
    review_type: []const u8,
    content: ?[]const u8,
    change_id: []const u8,
) !LandingReview {
    const row = try pool.row(
        \\INSERT INTO landing_reviews (landing_id, reviewer_id, type, content, change_id)
        \\VALUES ($1, $2, $3, $4, $5)
        \\RETURNING id, landing_id, reviewer_id, type, content, change_id,
        \\          EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at
    , .{ landing_id, reviewer_id, review_type, content, change_id });

    if (row) |r| {
        return LandingReview{
            .id = r.get(i64, 0),
            .landing_id = r.get(i64, 1),
            .reviewer_id = r.get(i64, 2),
            .review_type = r.get([]const u8, 3),
            .content = r.get(?[]const u8, 4),
            .change_id = r.get([]const u8, 5),
            .created_at = r.get(i64, 6),
        };
    }
    return error.InsertFailed;
}

pub fn getLineComments(pool: *Pool, allocator: std.mem.Allocator, landing_id: i64) ![]LineComment {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, landing_id, author_id, file_path, line_number, side, body, resolved,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
        \\FROM line_comments
        \\WHERE landing_id = $1
        \\ORDER BY file_path, line_number, created_at ASC
    , .{landing_id});
    defer result.deinit();

    var comments = std.ArrayList(LineComment).init(allocator);
    errdefer comments.deinit();

    var iter = result.iterator();
    while (try iter.next()) |row| {
        try comments.append(LineComment{
            .id = row.get(i64, 0),
            .landing_id = row.get(i64, 1),
            .author_id = row.get(i64, 2),
            .file_path = row.get([]const u8, 3),
            .line_number = row.get(i32, 4),
            .side = row.get([]const u8, 5),
            .body = row.get([]const u8, 6),
            .resolved = row.get(bool, 7),
            .created_at = row.get(i64, 8),
            .updated_at = row.get(i64, 9),
        });
    }

    return comments.toOwnedSlice(allocator);
}

pub fn getLineCommentById(pool: *Pool, comment_id: i64) !?LineComment {
    const row = try pool.row(
        \\SELECT id, landing_id, author_id, file_path, line_number, side, body, resolved,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
        \\FROM line_comments
        \\WHERE id = $1
    , .{comment_id});

    if (row) |r| {
        return LineComment{
            .id = r.get(i64, 0),
            .landing_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .file_path = r.get([]const u8, 3),
            .line_number = r.get(i32, 4),
            .side = r.get([]const u8, 5),
            .body = r.get([]const u8, 6),
            .resolved = r.get(bool, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
        };
    }
    return null;
}

pub fn createLineComment(
    pool: *Pool,
    landing_id: i64,
    author_id: i64,
    file_path: []const u8,
    line_number: i32,
    side: []const u8,
    body: []const u8,
) !LineComment {
    const row = try pool.row(
        \\INSERT INTO line_comments (landing_id, author_id, file_path, line_number, side, body)
        \\VALUES ($1, $2, $3, $4, $5, $6)
        \\RETURNING id, landing_id, author_id, file_path, line_number, side, body, resolved,
        \\          EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\          EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
    , .{ landing_id, author_id, file_path, line_number, side, body });

    if (row) |r| {
        return LineComment{
            .id = r.get(i64, 0),
            .landing_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .file_path = r.get([]const u8, 3),
            .line_number = r.get(i32, 4),
            .side = r.get([]const u8, 5),
            .body = r.get([]const u8, 6),
            .resolved = r.get(bool, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
        };
    }
    return error.InsertFailed;
}

pub fn updateLineComment(
    pool: *Pool,
    comment_id: i64,
    body: ?[]const u8,
    resolved: ?bool,
) !LineComment {
    const row = if (body != null and resolved != null)
        try pool.row(
            \\UPDATE line_comments
            \\SET body = $1, resolved = $2, updated_at = NOW()
            \\WHERE id = $3
            \\RETURNING id, landing_id, author_id, file_path, line_number, side, body, resolved,
            \\          EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
            \\          EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
        , .{ body.?, resolved.?, comment_id })
    else if (body != null)
        try pool.row(
            \\UPDATE line_comments
            \\SET body = $1, updated_at = NOW()
            \\WHERE id = $2
            \\RETURNING id, landing_id, author_id, file_path, line_number, side, body, resolved,
            \\          EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
            \\          EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
        , .{ body.?, comment_id })
    else if (resolved != null)
        try pool.row(
            \\UPDATE line_comments
            \\SET resolved = $1, updated_at = NOW()
            \\WHERE id = $2
            \\RETURNING id, landing_id, author_id, file_path, line_number, side, body, resolved,
            \\          EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
            \\          EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
        , .{ resolved.?, comment_id })
    else
        return error.NoUpdatesProvided;

    if (row) |r| {
        return LineComment{
            .id = r.get(i64, 0),
            .landing_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .file_path = r.get([]const u8, 3),
            .line_number = r.get(i32, 4),
            .side = r.get([]const u8, 5),
            .body = r.get([]const u8, 6),
            .resolved = r.get(bool, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
        };
    }
    return error.UpdateFailed;
}

pub fn deleteLineComment(pool: *Pool, comment_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM line_comments WHERE id = $1
    , .{comment_id});
}

// ============================================================================
// JJ Operations
// ============================================================================

/// JJ operation record from jj_operations table
pub const JjOperation = struct {
    id: i64,
    repository_id: i64,
    operation_id: []const u8,
    operation_type: []const u8,
    description: []const u8,
    timestamp: i64,
    is_undone: bool,
};

pub const JjOperationList = struct {
    items: []JjOperation,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *JjOperationList) void {
        self.allocator.free(self.items);
    }
};

/// Get operations for a repository
pub fn getOperationsByRepository(
    pool: *Pool,
    allocator: std.mem.Allocator,
    repository_id: i64,
    limit: i32,
) !JjOperationList {
    var result = try pool.query(
        \\SELECT id, repository_id, operation_id, operation_type, description, timestamp, is_undone
        \\FROM jj_operations
        \\WHERE repository_id = $1
        \\ORDER BY timestamp DESC
        \\LIMIT $2
    , .{ repository_id, limit });
    defer result.deinit();

    var operations = std.ArrayList(JjOperation).init(allocator);
    errdefer operations.deinit();

    while (try result.next()) |row| {
        try operations.append(JjOperation{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .operation_id = row.get([]const u8, 2),
            .operation_type = row.get([]const u8, 3),
            .description = row.get([]const u8, 4),
            .timestamp = row.get(i64, 5),
            .is_undone = row.get(bool, 6),
        });
    }

    return JjOperationList{
        .items = try operations.toOwnedSlice(),
        .allocator = allocator,
    };
}

/// Get a specific operation by ID
pub fn getOperationById(
    pool: *Pool,
    repository_id: i64,
    operation_id: []const u8,
) !?JjOperation {
    const row = try pool.row(
        \\SELECT id, repository_id, operation_id, operation_type, description, timestamp, is_undone
        \\FROM jj_operations
        \\WHERE repository_id = $1 AND operation_id = $2
    , .{ repository_id, operation_id });

    if (row) |r| {
        return JjOperation{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .operation_id = r.get([]const u8, 2),
            .operation_type = r.get([]const u8, 3),
            .description = r.get([]const u8, 4),
            .timestamp = r.get(i64, 5),
            .is_undone = r.get(bool, 6),
        };
    }
    return null;
}

/// Create a new operation record
pub fn createOperation(
    pool: *Pool,
    repository_id: i64,
    operation_id: []const u8,
    operation_type: []const u8,
    description: []const u8,
    timestamp: i64,
) !void {
    _ = try pool.exec(
        \\INSERT INTO jj_operations (repository_id, operation_id, operation_type, description, timestamp, is_undone)
        \\VALUES ($1, $2, $3, $4, $5, false)
        \\ON CONFLICT (repository_id, operation_id) DO NOTHING
    , .{ repository_id, operation_id, operation_type, description, timestamp });
}

/// Mark operations as undone after a certain timestamp
pub fn markOperationsAsUndone(
    pool: *Pool,
    repository_id: i64,
    after_timestamp: i64,
) !void {
    _ = try pool.exec(
        \\UPDATE jj_operations
        \\SET is_undone = true
        \\WHERE repository_id = $1 AND timestamp > $2
    , .{ repository_id, after_timestamp });
}
