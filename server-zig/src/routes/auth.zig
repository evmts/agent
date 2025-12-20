//! Authentication routes
//!
//! Handles SIWE (Sign In With Ethereum) authentication flow:
//! - GET /auth/siwe/nonce - Generate nonce for signing
//! - POST /auth/siwe/verify - Verify signature and login
//! - POST /auth/siwe/register - Register new account
//! - POST /auth/logout - Destroy session
//! - GET /auth/me - Get current user

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("../lib/db.zig");
const siwe = @import("../lib/siwe.zig");
const jwt = @import("../lib/jwt.zig");
const auth_middleware = @import("../middleware/auth.zig");

const log = std.log.scoped(.auth_routes);

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
/// Verify SIWE signature and authenticate existing user
pub fn verify(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Parse JSON body
    const body = req.body() orelse {
        res.status = .@"Bad Request";
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        message: []const u8,
        signature: []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = .@"Bad Request";
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const message = parsed.value.message;
    const signature = parsed.value.signature;

    // Verify SIWE signature
    const result = siwe.verifySiweSignature(ctx.allocator, ctx.pool, message, signature) catch |err| {
        res.status = .unauthorized;
        var writer = res.writer();
        try writer.print("{{\"error\":\"{s}\"}}", .{@errorName(err)});
        return;
    };

    const wallet_address = std.ascii.lowerString(ctx.allocator.alloc(u8, result.address.len) catch unreachable, result.address) catch result.address;
    defer if (wallet_address.ptr != result.address.ptr) ctx.allocator.free(wallet_address);

    // Check if user exists
    const user = try db.getUserByWallet(ctx.pool, wallet_address);
    if (user == null) {
        res.status = .@"Not Found";
        var writer = res.writer();
        try writer.print("{{\"error\":\"Wallet not registered\",\"code\":\"WALLET_NOT_REGISTERED\",\"address\":\"{s}\"}}", .{wallet_address});
        return;
    }

    const u = user.?;
    if (u.prohibit_login) {
        res.status = .forbidden;
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

    // Set cookies
    try auth_middleware.setSessionCookie(res, session_key, ctx.config.is_production);

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
        res.status = .@"Bad Request";
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        message: []const u8,
        signature: []const u8,
        username: []const u8,
        displayName: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = .@"Bad Request";
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Validate username
    if (v.username.len < 3 or v.username.len > 39) {
        res.status = .@"Bad Request";
        try res.writer().writeAll("{\"error\":\"Username must be 3-39 characters\"}");
        return;
    }

    // Verify SIWE signature
    const result = siwe.verifySiweSignature(ctx.allocator, ctx.pool, v.message, v.signature) catch |err| {
        res.status = .unauthorized;
        var writer = res.writer();
        try writer.print("{{\"error\":\"{s}\"}}", .{@errorName(err)});
        return;
    };

    const wallet_address = std.ascii.lowerString(ctx.allocator.alloc(u8, result.address.len) catch unreachable, result.address) catch result.address;
    defer if (wallet_address.ptr != result.address.ptr) ctx.allocator.free(wallet_address);

    // Check if wallet already registered
    if (try db.getUserByWallet(ctx.pool, wallet_address) != null) {
        res.status = .conflict;
        try res.writer().writeAll("{\"error\":\"Wallet already registered\"}");
        return;
    }

    // Check if username taken
    if (try db.getUserByUsername(ctx.pool, v.username) != null) {
        res.status = .conflict;
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

    // Set cookies
    try auth_middleware.setSessionCookie(res, session_key, ctx.config.is_production);

    res.status = .created;
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

    try auth_middleware.clearSessionCookie(res, ctx.config.is_production);

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
