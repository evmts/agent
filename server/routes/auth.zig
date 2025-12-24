//! Authentication routes
//!
//! SIWE authentication is now handled at the Cloudflare edge.
//! The origin server trusts the X-Plue-User-Address header from the edge.
//!
//! Remaining endpoints:
//! - GET /auth/me - Get current user
//! - POST /auth/logout - Clear session (for legacy session-based auth)
//! - POST /auth/dev-login - Development-only login

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");
const jwt = @import("../lib/jwt.zig");
const auth_middleware = @import("../middleware/auth.zig");

const log = std.log.scoped(.auth_routes);

/// GET /auth/me
/// Get current authenticated user
pub fn me(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    if (ctx.user) |u| {
        var writer = res.writer();
        try writer.print(
            \\{{"user":{{"id":{d},"username":"{s}","email":
        , .{ u.id, u.username });
        if (u.email) |e| {
            try writer.print("\"{s}\"", .{e});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"displayName\":");
        if (u.display_name) |d| {
            try writer.print("\"{s}\"", .{d});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(
            \\,"isActive":{s},"isAdmin":{s},"walletAddress":
        , .{
            if (u.is_active) "true" else "false",
            if (u.is_admin) "true" else "false",
        });
        if (u.wallet_address) |w| {
            try writer.print("\"{s}\"", .{w});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll("}}}}");
    } else {
        try res.writer().writeAll("{\"user\":null}");
    }
}

/// POST /auth/logout
/// Clear session cookie (for legacy session-based auth)
pub fn logout(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    if (ctx.session_key) |session_key| {
        try db.deleteSession(ctx.pool, session_key);
    }

    // Clear session cookie
    try auth_middleware.clearSessionCookie(res, ctx.config.is_production);

    try res.writer().writeAll("{\"message\":\"Logout successful\"}");
}

/// POST /auth/dev-login
/// Development-only login endpoint that bypasses authentication
/// Only available when is_production = false
pub fn devLogin(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Only allow in development mode
    if (ctx.config.is_production) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Not found\"}");
        return;
    }

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        username: []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const username = parsed.value.username;

    // Get user from database
    const user = try db.getUserByUsername(ctx.pool, username);
    if (user == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"User not found\"}");
        return;
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

    // Return user data
    var writer = res.writer();
    try writer.print(
        \\{{"message":"Dev login successful","user":{{"id":{d},"username":"{s}","email":
    , .{ u.id, u.username });
    if (u.email) |e| {
        try writer.print("\"{s}\"", .{e});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(
        \\,"isActive":{s},"isAdmin":{s}}}}}
    , .{
        if (u.is_active) "true" else "false",
        if (u.is_admin) "true" else "false",
    });
}
