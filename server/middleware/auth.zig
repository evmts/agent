//! Authentication middleware
//!
//! Loads user from session cookie and sets context variables.
//! Does not require authentication - just loads if present.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const User = @import("../main.zig").User;
const db = @import("db");

const log = std.log.scoped(.auth);

const SESSION_COOKIE_NAME = "plue_session";

// =============================================================================
// Token Scopes
// =============================================================================

/// API token scopes
pub const TokenScope = enum {
    repo_read,
    repo_write,
    user_read,
    user_write,
    admin,

    /// Parse scope from string
    pub fn fromString(str: []const u8) ?TokenScope {
        if (std.mem.eql(u8, str, "repo:read")) return .repo_read;
        if (std.mem.eql(u8, str, "repo:write")) return .repo_write;
        if (std.mem.eql(u8, str, "repo")) return .repo_write; // "repo" grants full repo access
        if (std.mem.eql(u8, str, "user:read")) return .user_read;
        if (std.mem.eql(u8, str, "user:write")) return .user_write;
        if (std.mem.eql(u8, str, "user")) return .user_write; // "user" grants full user access
        if (std.mem.eql(u8, str, "admin")) return .admin;
        return null;
    }

    /// Convert scope to string
    pub fn toString(self: TokenScope) []const u8 {
        return switch (self) {
            .repo_read => "repo:read",
            .repo_write => "repo:write",
            .user_read => "user:read",
            .user_write => "user:write",
            .admin => "admin",
        };
    }
};

/// Check if a token has a required scope
/// Scopes are stored as comma-separated strings like "repo,user"
/// Write scopes imply read scopes (e.g., repo:write includes repo:read)
pub fn hasScope(scopes: []const u8, required: TokenScope) bool {
    // Parse comma-separated scopes
    var it = std.mem.splitSequence(u8, scopes, ",");
    while (it.next()) |scope_str| {
        const trimmed = std.mem.trim(u8, scope_str, " \t\n\r");
        if (trimmed.len == 0) continue;

        const scope = TokenScope.fromString(trimmed) orelse continue;

        // Exact match
        if (scope == required) return true;

        // Write implies read for the same resource
        switch (required) {
            .repo_read => if (scope == .repo_write) return true,
            .user_read => if (scope == .user_write) return true,
            else => {},
        }

        // Admin has all permissions
        if (scope == .admin) return true;
    }

    return false;
}

/// Hash a token using SHA256 for comparison with database
fn hashToken(allocator: std.mem.Allocator, token: []const u8) ![]const u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(token, &hash, .{});
    const hex = std.fmt.bytesToHex(hash, .lower);
    return allocator.dupe(u8, &hex);
}

/// Extract Bearer token from Authorization header
fn getBearerToken(auth_header: ?[]const u8) ?[]const u8 {
    const header = auth_header orelse return null;
    if (!std.mem.startsWith(u8, header, "Bearer ")) return null;
    return header[7..]; // Skip "Bearer "
}

/// Header set by Cloudflare edge worker with authenticated user's wallet address
const USER_ADDRESS_HEADER = "x-plue-user-address";

/// Generate a username from wallet address.
/// Format: first 6 + last 4 chars of address (e.g., "0x1234abcd")
fn generateUsernameFromWallet(allocator: std.mem.Allocator, wallet_address: []const u8) ![]const u8 {
    if (wallet_address.len < 10) {
        return try allocator.dupe(u8, wallet_address);
    }
    const first_part = wallet_address[0..6];
    const last_part = wallet_address[wallet_address.len - 4 ..];
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ first_part, last_part });
}

/// Auth middleware - loads user from edge header, session cookie, or Bearer token
/// Does not require authentication, just loads if present
pub fn authMiddleware(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
    // First, check for edge-authenticated user (X-Plue-User-Address header from Cloudflare)
    // This header is set by the edge worker after verifying SIWE signatures
    if (req.headers.get(USER_ADDRESS_HEADER)) |wallet_address| {
        // Look up user by wallet address
        var user_record = db.getUserByWallet(ctx.pool, wallet_address) catch null;

        // Auto-create user if wallet address is provided but user doesn't exist
        if (user_record == null) {
            // Generate username from wallet address (first 6 + last 4 chars)
            const username = generateUsernameFromWallet(ctx.allocator, wallet_address) catch null;
            if (username) |un| {
                defer ctx.allocator.free(un);
                // Create user with generated username
                const user_id = db.createUser(ctx.pool, un, un, wallet_address) catch null;
                if (user_id) |id| {
                    user_record = db.getUserById(ctx.pool, id) catch null;
                }
            }
        }

        if (user_record) |ur| {
            if (!ur.prohibit_login) {
                ctx.user = User{
                    .id = ur.id,
                    .username = ur.username,
                    .email = ur.email,
                    .display_name = ur.display_name,
                    .is_admin = ur.is_admin,
                    .is_active = ur.is_active,
                    .wallet_address = ur.wallet_address,
                };
                ctx.session_key = null; // No session key for edge auth
                ctx.token_scopes = null;
                _ = res;
                return true;
            }
        }
    }

    // Second, try Bearer token authentication (for API access tokens)
    const auth_header = req.headers.get("authorization");
    if (getBearerToken(auth_header)) |token| {
        // Hash the token
        const token_hash = try hashToken(ctx.allocator, token);
        defer ctx.allocator.free(token_hash);

        // Validate token and get user + scopes
        const token_result = db.validateAccessToken(ctx.pool, token_hash) catch null;
        if (token_result) |result| {
            if (!result.user.prohibit_login) {
                // Set context from access token
                ctx.user = User{
                    .id = result.user.id,
                    .username = result.user.username,
                    .email = result.user.email,
                    .display_name = result.user.display_name,
                    .is_admin = result.user.is_admin,
                    .is_active = result.user.is_active,
                    .wallet_address = result.user.wallet_address,
                };
                ctx.session_key = null; // No session key for token auth
                ctx.token_scopes = result.scopes; // Store scopes for scope checking
                _ = res;
                return true; // Continue to next handler
            }
        }
    }

    // Fall back to session cookie authentication
    const cookie_header = req.headers.get("cookie");
    const session_key = getSessionFromCookie(cookie_header) orelse {
        ctx.user = null;
        ctx.session_key = null;
        return true; // Continue to next handler
    };

    // Look up session
    const session_data = try db.getSession(ctx.pool, session_key);
    if (session_data == null) {
        ctx.user = null;
        ctx.session_key = null;
        return true;
    }

    // Load user from database
    const user_record = try db.getUserById(ctx.pool, session_data.?.user_id);
    if (user_record == null or user_record.?.prohibit_login) {
        ctx.user = null;
        ctx.session_key = null;
        return true;
    }

    // Check if session is near expiry (within refresh threshold)
    const now = std.time.milliTimestamp();
    const expires_at_ms = session_data.?.expires_at * 1000; // Convert to milliseconds
    const time_remaining = expires_at_ms - now;

    // Auto-refresh if near expiry
    if (time_remaining < db.SESSION_REFRESH_THRESHOLD_MS and time_remaining > 0) {
        try db.refreshSession(ctx.pool, session_key);
    }

    // Set context
    const ur = user_record.?;
    ctx.user = User{
        .id = ur.id,
        .username = ur.username,
        .email = ur.email,
        .display_name = ur.display_name,
        .is_admin = ur.is_admin,
        .is_active = ur.is_active,
        .wallet_address = ur.wallet_address,
    };
    ctx.session_key = session_key;

    _ = res;
    return true; // Continue to next handler
}

/// Require authentication - returns 401 if not authenticated
pub fn requireAuth(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !bool {
    if (ctx.user == null) {
        res.status = 401;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return false; // Stop handler chain
    }
    return true;
}

/// Require active account - returns 403 if not activated
pub fn requireActiveAccount(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !bool {
    if (ctx.user == null) {
        res.status = 401;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return false;
    }

    if (!ctx.user.?.is_active) {
        res.status = 403;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Account not activated. Please verify your email.\"}");
        return false;
    }
    return true;
}

/// Require admin - returns 403 if not admin
pub fn requireAdmin(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !bool {
    if (ctx.user == null) {
        res.status = 401;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return false;
    }

    if (!ctx.user.?.is_admin) {
        res.status = 403;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Admin access required\"}");
        return false;
    }
    return true;
}

/// Check if the request has a required scope (for use in route handlers)
/// Returns true if authorized, false if unauthorized (and sets appropriate HTTP response)
/// Note: Session-based auth (cookies) bypasses scope checks - only API tokens are restricted
pub fn checkScope(ctx: *Context, res: *httpz.Response, required: TokenScope) !bool {
    // Require authentication first
    if (ctx.user == null) {
        res.status = 401;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return false;
    }

    // If using session auth (no token_scopes), allow access
    // Session-based auth has full access
    const scopes = ctx.token_scopes orelse return true;

    // Check if token has required scope
    if (!hasScope(scopes, required)) {
        res.status = 403;
        res.content_type = .JSON;
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "{{\"error\":\"Insufficient scope. Required: {s}\"}}", .{required.toString()});
        try res.writer().writeAll(msg);
        return false;
    }

    return true;
}

// ============================================================================
// Cookie helpers
// ============================================================================

fn getSessionFromCookie(cookie_header: ?[]const u8) ?[]const u8 {
    const header = cookie_header orelse return null;

    var cookies = std.mem.splitSequence(u8, header, "; ");
    while (cookies.next()) |cookie| {
        if (std.mem.startsWith(u8, cookie, SESSION_COOKIE_NAME)) {
            const eq_pos = std.mem.indexOf(u8, cookie, "=") orelse continue;
            return cookie[eq_pos + 1 ..];
        }
    }
    return null;
}

pub fn setSessionCookie(res: *httpz.Response, session_key: []const u8, is_production: bool) !void {
    var cookie_buf: [4096]u8 = undefined;
    const secure = if (is_production) "; Secure" else "";
    const max_age = 30 * 24 * 60 * 60; // 30 days

    const cookie = try std.fmt.bufPrint(&cookie_buf, "{s}={s}; Path=/; HttpOnly; SameSite=Lax; Max-Age={d}{s}", .{
        SESSION_COOKIE_NAME,
        session_key,
        max_age,
        secure,
    });

    res.headers.add("Set-Cookie", cookie);
}

pub fn clearSessionCookie(res: *httpz.Response, is_production: bool) !void {
    var cookie_buf: [256]u8 = undefined;
    const secure = if (is_production) "; Secure" else "";

    const cookie = try std.fmt.bufPrint(&cookie_buf, "{s}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0{s}", .{
        SESSION_COOKIE_NAME,
        secure,
    });

    res.headers.add("Set-Cookie", cookie);
}

test "parse session cookie" {
    const cookie = "other=value; plue_session=abc123; another=test";
    const session = getSessionFromCookie(cookie);
    try std.testing.expectEqualStrings("abc123", session.?);
}

test "parse session cookie missing" {
    const cookie = "other=value; another=test";
    const session = getSessionFromCookie(cookie);
    try std.testing.expect(session == null);
}

test "parse session cookie null header" {
    const session = getSessionFromCookie(null);
    try std.testing.expect(session == null);
}

test "parse session cookie first" {
    const cookie = "plue_session=firstvalue; other=value";
    const session = getSessionFromCookie(cookie);
    try std.testing.expectEqualStrings("firstvalue", session.?);
}

test "parse session cookie only" {
    const cookie = "plue_session=onlyvalue";
    const session = getSessionFromCookie(cookie);
    try std.testing.expectEqualStrings("onlyvalue", session.?);
}

test "parse session cookie complex value" {
    const cookie = "plue_session=abc-123_XYZ; other=value";
    const session = getSessionFromCookie(cookie);
    try std.testing.expectEqualStrings("abc-123_XYZ", session.?);
}

test "hashToken produces consistent output" {
    const allocator = std.testing.allocator;

    const hash1 = try hashToken(allocator, "test_token");
    defer allocator.free(hash1);

    const hash2 = try hashToken(allocator, "test_token");
    defer allocator.free(hash2);

    try std.testing.expectEqualStrings(hash1, hash2);
}

test "hashToken different inputs produce different hashes" {
    const allocator = std.testing.allocator;

    const hash1 = try hashToken(allocator, "token1");
    defer allocator.free(hash1);

    const hash2 = try hashToken(allocator, "token2");
    defer allocator.free(hash2);

    try std.testing.expect(!std.mem.eql(u8, hash1, hash2));
}

test "hashToken output format" {
    const allocator = std.testing.allocator;

    const hash = try hashToken(allocator, "any_token");
    defer allocator.free(hash);

    // SHA256 produces 32 bytes = 64 hex characters
    try std.testing.expectEqual(@as(usize, 64), hash.len);

    // All characters should be valid hex
    for (hash) |c| {
        const is_hex = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(is_hex);
    }
}

test "getBearerToken valid" {
    const token = getBearerToken("Bearer abc123token");
    try std.testing.expectEqualStrings("abc123token", token.?);
}

test "getBearerToken missing Bearer prefix" {
    const token = getBearerToken("Basic abc123");
    try std.testing.expect(token == null);
}

test "getBearerToken null header" {
    const token = getBearerToken(null);
    try std.testing.expect(token == null);
}

test "getBearerToken empty token" {
    const token = getBearerToken("Bearer ");
    try std.testing.expectEqualStrings("", token.?);
}

test "getBearerToken case sensitive" {
    // Bearer must be exactly "Bearer "
    const token1 = getBearerToken("bearer abc123");
    try std.testing.expect(token1 == null);

    const token2 = getBearerToken("BEARER abc123");
    try std.testing.expect(token2 == null);
}
