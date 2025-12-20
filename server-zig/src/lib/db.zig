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
    // Build dynamic update based on what's provided
    if (display_name) |dn| {
        _ = try pool.exec(
            \\UPDATE users SET display_name = $1, updated_at = NOW() WHERE id = $2
        , .{ dn, user_id });
    }
    if (bio) |b| {
        _ = try pool.exec(
            \\UPDATE users SET bio = $1, updated_at = NOW() WHERE id = $2
        , .{ b, user_id });
    }
    if (email) |e| {
        _ = try pool.exec(
            \\UPDATE users SET email = $1, lower_email = lower($1), updated_at = NOW() WHERE id = $2
        , .{ e, user_id });
    }
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
    var sessions = std.ArrayList(AgentSessionRecord).init(allocator);

    const result = try pool.query(
        \\SELECT id, project_id, directory, title, version, time_created, time_updated,
        \\       time_archived, parent_id, fork_point, summary::text, revert::text,
        \\       compaction::text, token_count, bypass_mode, model, reasoning_effort,
        \\       ghost_commit::text, plugins::text
        \\FROM sessions
        \\ORDER BY time_updated DESC
    , .{});
    defer result.deinit();

    var iter = result.iterator();
    while (try iter.next()) |row| {
        try sessions.append(AgentSessionRecord{
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
    var messages = std.ArrayList(MessageRecord).init(allocator);

    const result = try pool.query(
        \\SELECT id, session_id, role, time_created, time_completed, status,
        \\       thinking_text, error_message
        \\FROM messages
        \\WHERE session_id = $1
        \\ORDER BY time_created ASC
    , .{session_id});
    defer result.deinit();

    var iter = result.iterator();
    while (try iter.next()) |row| {
        try messages.append(MessageRecord{
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

    var stargazers = std.ArrayList(Stargazer).init(allocator);
    errdefer stargazers.deinit();

    var iter = result.iterator();
    while (try iter.next()) |row| {
        try stargazers.append(Stargazer{
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

    var bookmarks = std.ArrayList(Bookmark).init(allocator);
    errdefer bookmarks.deinit();

    var iter = result.iterator();
    while (try iter.next()) |row| {
        try bookmarks.append(Bookmark{
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

    var changes = std.ArrayList(Change).init(allocator);
    errdefer changes.deinit();

    var iter = result.iterator();
    while (try iter.next()) |row| {
        try changes.append(Change{
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

    var runs = std.ArrayList(WorkflowRun).init(allocator);
    defer runs.deinit();

    while (try result.next()) |row| {
        try runs.append(.{
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

    var jobs = std.ArrayList(WorkflowJob).init(allocator);
    defer jobs.deinit();

    while (try result.next()) |row| {
        try jobs.append(.{
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

    var logs = std.ArrayList(WorkflowLog).init(allocator);
    defer logs.deinit();

    while (try result.next()) |row| {
        try logs.append(.{
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

pub fn getTaskByToken(pool: *Pool, token_hash: []const u8) !?WorkflowTask {
    const row = try pool.row(
        \\SELECT id, job_id, attempt, repository_id, commit_sha,
        \\       COALESCE(workflow_content, '') as workflow_content,
        \\       COALESCE(workflow_path, '') as workflow_path
        \\FROM workflow_tasks
        \\WHERE token_hash = $1
    , .{token_hash});

    if (row) |r| {
        // Note: This leaks memory - caller should handle deallocation
        const allocator = std.heap.page_allocator;
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
