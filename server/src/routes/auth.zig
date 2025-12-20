//! Authentication routes
//!
//! Handles SIWE (Sign In With Ethereum) authentication flow:
//! - GET /auth/siwe/nonce - Generate nonce for signing
//! - POST /auth/siwe/verify - Verify signature and login (auto-creates account if needed)
//! - POST /auth/siwe/register - Register new account with custom username
//! - POST /auth/logout - Destroy session
//! - GET /auth/me - Get current user

const std = @import("std");
const httpz = @import("httpz");
const primitives = @import("primitives");
const Context = @import("../main.zig").Context;
const db = @import("../lib/db.zig");
const siwe = @import("../lib/siwe.zig");
const jwt = @import("../lib/jwt.zig");
const auth_middleware = @import("../middleware/auth.zig");
const csrf_middleware = @import("../middleware/csrf.zig");

const log = std.log.scoped(.auth_routes);

/// Generate a username from wallet address.
/// Format: first 6 + last 4 chars of address (e.g., "0x1234abcd")
fn generateUsernameFromWallet(allocator: std.mem.Allocator, wallet_address: []const u8) ![]const u8 {
    if (wallet_address.len < 10) {
        // Fallback for short addresses
        return try allocator.dupe(u8, wallet_address);
    }

    // Take first 6 characters (0x1234) and last 4 characters (abcd)
    const first_part = wallet_address[0..6];
    const last_part = wallet_address[wallet_address.len - 4 ..];

    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ first_part, last_part });
}

/// GET /auth/siwe/nonce
/// Generate a nonce for SIWE authentication
pub fn getNonce(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    const nonce = try siwe.createNonce(ctx.allocator, ctx.pool);
    defer ctx.allocator.free(nonce);

    res.content_type = .JSON;
    var writer = res.writer();
    try writer.print("{{\"nonce\":\"{s}\"}}", .{nonce});
}

/// POST /auth/siwe/verify
/// Verify SIWE signature and authenticate user.
/// Auto-creates account if wallet is not registered.
pub fn verify(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        message: []const u8,
        signature: []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const message = parsed.value.message;
    const signature = parsed.value.signature;

    // Verify SIWE signature
    const result = siwe.verifySiweSignature(ctx.allocator, ctx.pool, message, signature) catch |err| {
        res.status = 401;
        var writer = res.writer();
        try writer.print("{{\"error\":\"{s}\"}}", .{@errorName(err)});
        return;
    };

    // Convert Address to lowercase hex string
    const address_hex = primitives.Address.Address.addressToHex(result.address);
    var wallet_address_buf: [42]u8 = undefined;
    _ = std.ascii.lowerString(&wallet_address_buf, &address_hex);
    const wallet_address: []const u8 = &wallet_address_buf;

    // Check if user exists, auto-create if not
    var user = try db.getUserByWallet(ctx.pool, wallet_address);
    var created_username: ?[]const u8 = null;
    defer if (created_username) |un| ctx.allocator.free(un);

    if (user == null) {
        // Auto-create user with generated username
        var username = try generateUsernameFromWallet(ctx.allocator, wallet_address);
        created_username = username;

        // Handle potential username collision by appending a number
        var attempt: u32 = 0;
        var user_id: i64 = 0;
        while (attempt < 100) : (attempt += 1) {
            user_id = db.createUser(ctx.pool, username, username, wallet_address) catch |err| {
                if (attempt < 99) {
                    // If username is taken, try with a suffix
                    ctx.allocator.free(username);
                    const base_username = try generateUsernameFromWallet(ctx.allocator, wallet_address);
                    defer ctx.allocator.free(base_username);
                    username = try std.fmt.allocPrint(ctx.allocator, "{s}{d}", .{ base_username, attempt + 1 });
                    created_username = username;
                    continue;
                }
                return err;
            };
            break;
        }

        // Re-fetch the user from database to get consistent data
        user = try db.getUserById(ctx.pool, user_id);
    }

    const u = user.?;
    if (u.prohibit_login) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Account is disabled\"}");
        return;
    }

    // Create session
    const session_key = try db.createSession(ctx.pool, ctx.allocator, u.id, u.username, u.is_admin);
    defer ctx.allocator.free(session_key);

    // Generate JWT
    const token = try jwt.create(ctx.allocator, u.id, u.username, u.is_admin, ctx.config.jwt_secret);
    defer ctx.allocator.free(token);

    // Update last login
    try db.updateLastLogin(ctx.pool, u.id);

    // Set session cookie
    try auth_middleware.setSessionCookie(res, session_key, ctx.config.is_production);

    // Generate and set CSRF token
    const csrf_token = try ctx.csrf_store.generateToken(session_key);
    var csrf_cookie_buf: [256]u8 = undefined;
    const csrf_secure = if (ctx.config.is_production) "; Secure" else "";
    const csrf_cookie = try std.fmt.bufPrint(&csrf_cookie_buf, "csrf_token={s}; Path=/; SameSite=Strict; Max-Age={d}{s}", .{
        csrf_token,
        24 * 60 * 60, // 24 hours in seconds
        csrf_secure,
    });
    res.headers.add("Set-Cookie", csrf_cookie);

    // Return user data
    var writer = res.writer();
    try writer.print(
        \\{{"message":"Login successful","user":{{"id":{d},"username":"{s}","email":{s},"isActive":{s},"isAdmin":{s},"walletAddress":"{s}"}}}}
    , .{
        u.id,
        u.username,
        if (u.email) |e| try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{e}) else "null",
        if (u.is_active) "true" else "false",
        if (u.is_admin) "true" else "false",
        wallet_address,
    });
}

/// POST /auth/siwe/register
/// Register new user with SIWE
pub fn register(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        message: []const u8,
        signature: []const u8,
        username: []const u8,
        displayName: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Validate username
    if (v.username.len < 3 or v.username.len > 39) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Username must be 3-39 characters\"}");
        return;
    }

    // Verify SIWE signature
    const result = siwe.verifySiweSignature(ctx.allocator, ctx.pool, v.message, v.signature) catch |err| {
        res.status = 401;
        var writer = res.writer();
        try writer.print("{{\"error\":\"{s}\"}}", .{@errorName(err)});
        return;
    };

    // Convert Address to lowercase hex string
    const address_hex = primitives.Address.Address.addressToHex(result.address);
    var wallet_address_buf: [42]u8 = undefined;
    _ = std.ascii.lowerString(&wallet_address_buf, &address_hex);
    const wallet_address: []const u8 = &wallet_address_buf;

    // Check if wallet already registered
    if (try db.getUserByWallet(ctx.pool, wallet_address) != null) {
        res.status = 409;
        try res.writer().writeAll("{\"error\":\"Wallet already registered\"}");
        return;
    }

    // Check if username taken
    if (try db.getUserByUsername(ctx.pool, v.username) != null) {
        res.status = 409;
        try res.writer().writeAll("{\"error\":\"Username already taken\"}");
        return;
    }

    // Create user
    const user_id = try db.createUser(ctx.pool, v.username, v.displayName, wallet_address);

    // Create session
    const session_key = try db.createSession(ctx.pool, ctx.allocator, user_id, v.username, false);
    defer ctx.allocator.free(session_key);

    // Generate JWT
    const token = try jwt.create(ctx.allocator, user_id, v.username, false, ctx.config.jwt_secret);
    defer ctx.allocator.free(token);

    // Set session cookie
    try auth_middleware.setSessionCookie(res, session_key, ctx.config.is_production);

    // Generate and set CSRF token
    const csrf_token = try ctx.csrf_store.generateToken(session_key);
    var csrf_cookie_buf: [256]u8 = undefined;
    const csrf_secure = if (ctx.config.is_production) "; Secure" else "";
    const csrf_cookie = try std.fmt.bufPrint(&csrf_cookie_buf, "csrf_token={s}; Path=/; SameSite=Strict; Max-Age={d}{s}", .{
        csrf_token,
        24 * 60 * 60, // 24 hours in seconds
        csrf_secure,
    });
    res.headers.add("Set-Cookie", csrf_cookie);

    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"message":"Registration successful","user":{{"id":{d},"username":"{s}","isActive":true,"isAdmin":false,"walletAddress":"{s}"}}}}
    , .{ user_id, v.username, wallet_address });
}

/// POST /auth/logout
/// Destroy session and clear cookies
pub fn logout(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    if (ctx.session_key) |session_key| {
        try db.deleteSession(ctx.pool, session_key);
    }

    // Clear session cookie
    try auth_middleware.clearSessionCookie(res, ctx.config.is_production);

    // Clear CSRF token cookie
    var csrf_cookie_buf: [128]u8 = undefined;
    const csrf_secure = if (ctx.config.is_production) "; Secure" else "";
    const csrf_cookie = try std.fmt.bufPrint(&csrf_cookie_buf, "csrf_token=; Path=/; SameSite=Strict; Max-Age=0{s}", .{csrf_secure});
    res.headers.add("Set-Cookie", csrf_cookie);

    try res.writer().writeAll("{\"message\":\"Logout successful\"}");
}

/// GET /auth/me
/// Get current authenticated user
pub fn me(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    if (ctx.user) |u| {
        var writer = res.writer();
        try writer.print(
            \\{{"user":{{"id":{d},"username":"{s}","email":{s},"displayName":{s},"isActive":{s},"isAdmin":{s},"walletAddress":{s}}}}}
        , .{
            u.id,
            u.username,
            if (u.email) |e| try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{e}) else "null",
            if (u.display_name) |d| try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{d}) else "null",
            if (u.is_active) "true" else "false",
            if (u.is_admin) "true" else "false",
            if (u.wallet_address) |w| try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{w}) else "null",
        });
    } else {
        try res.writer().writeAll("{\"user\":null}");
    }
}

/// POST /auth/refresh
/// Explicitly refresh session token
/// Requires valid session, extends expiration and issues new session key
pub fn refresh(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Must be authenticated
    if (ctx.user == null or ctx.session_key == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const user = ctx.user.?;
    const old_session_key = ctx.session_key.?;

    // Delete old session
    try db.deleteSession(ctx.pool, old_session_key);

    // Create new session with fresh expiration
    const new_session_key = try db.createSession(ctx.pool, ctx.allocator, user.id, user.username, user.is_admin);
    defer ctx.allocator.free(new_session_key);

    // Generate new JWT
    const token = try jwt.create(ctx.allocator, user.id, user.username, user.is_admin, ctx.config.jwt_secret);
    defer ctx.allocator.free(token);

    // Set new session cookie
    try auth_middleware.setSessionCookie(res, new_session_key, ctx.config.is_production);

    // Generate and set new CSRF token
    const csrf_token = try ctx.csrf_store.generateToken(new_session_key);
    var csrf_cookie_buf: [256]u8 = undefined;
    const csrf_secure = if (ctx.config.is_production) "; Secure" else "";
    const csrf_cookie = try std.fmt.bufPrint(&csrf_cookie_buf, "csrf_token={s}; Path=/; SameSite=Strict; Max-Age={d}{s}", .{
        csrf_token,
        24 * 60 * 60, // 24 hours in seconds
        csrf_secure,
    });
    res.headers.add("Set-Cookie", csrf_cookie);

    // Return success with new session info
    var writer = res.writer();
    try writer.print(
        \\{{"message":"Session refreshed","expiresAt":{d}}}
    , .{std.time.milliTimestamp() + (30 * 24 * 60 * 60 * 1000)});
}
