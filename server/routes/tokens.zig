//! Access Token routes
//!
//! Handles API access token management:
//! - GET /api/user/tokens - List user's access tokens
//! - POST /api/user/tokens - Create new access token
//! - DELETE /api/user/tokens/:id - Revoke access token

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");

const log = std.log.scoped(.tokens);

/// GET /api/user/tokens - List user's access tokens
pub fn list(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    };

    if (!user.is_active) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Account not activated\"}");
        return;
    }

    // Query access tokens
    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT
        \\  id,
        \\  name,
        \\  token_last_eight,
        \\  scopes,
        \\  created_at::text,
        \\  last_used_at::text
        \\FROM access_tokens
        \\WHERE user_id = $1
        \\ORDER BY created_at DESC
    , .{user.id});
    defer result.deinit();

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"tokens\":[");

    var first = true;
    while (try result.next()) |row| {
        if (!first) try writer.writeAll(",");
        first = false;

        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const token_last_eight = row.get([]const u8, 2);
        const scopes = row.get([]const u8, 3);
        const created_at = row.get([]const u8, 4);
        const last_used_at = row.get(?[]const u8, 5);

        try writer.print(
            \\{{"id":{d},"name":"{s}","tokenLastEight":"{s}","scopes":"{s}","createdAt":"{s}","lastUsedAt":
        , .{
            id,
            name,
            token_last_eight,
            scopes,
            created_at,
        });
        if (last_used_at) |lut| {
            try writer.print("\"{s}\"", .{lut});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll("}}}");
    }

    try writer.writeAll("]}");
}

/// POST /api/user/tokens - Create new access token
pub fn create(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    };

    if (!user.is_active) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Account not activated\"}");
        return;
    }

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        name: []const u8,
        scopes: [][]const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const name = std.mem.trim(u8, parsed.value.name, " \t\n\r");
    const scopes = parsed.value.scopes;

    // Validate inputs
    if (name.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Token name is required\"}");
        return;
    }

    if (name.len > 255) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Name must be at most 255 characters\"}");
        return;
    }

    if (scopes.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"At least one scope is required\"}");
        return;
    }

    // Validate scopes
    // Supported scopes: repo (full), repo:read, repo:write, user (full), user:read, user:write, admin
    const valid_scopes = [_][]const u8{ "repo", "repo:read", "repo:write", "user", "user:read", "user:write", "admin" };
    for (scopes) |scope| {
        var valid = false;
        for (valid_scopes) |vs| {
            if (std.mem.eql(u8, scope, vs)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Invalid scope. Must be one of: repo, repo:read, repo:write, user, user:read, user:write, admin\"}");
            return;
        }
    }

    // Join scopes with comma
    var scopes_str = std.ArrayList(u8){};
    defer scopes_str.deinit(ctx.allocator);

    for (scopes, 0..) |scope, i| {
        if (i > 0) try scopes_str.appendSlice(ctx.allocator, ",");
        try scopes_str.appendSlice(ctx.allocator, scope);
    }

    // Create token (generates, hashes, stores, returns raw token)
    const token = db.createAccessToken(
        ctx.pool,
        ctx.allocator,
        user.id,
        name,
        scopes_str.items,
    ) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create access token\"}");
        return;
    };
    defer ctx.allocator.free(token);

    // Get last 8 chars for display
    const token_last_eight = if (token.len >= 8) token[token.len - 8 ..] else token;

    // Return created token with FULL token (only time it's shown)
    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"token":{{"name":"{s}","tokenLastEight":"{s}","scopes":"{s}"}},"fullToken":"{s}","message":"Token created successfully. Save it now - you won't be able to see it again!"}}
    , .{ name, token_last_eight, scopes_str.items, token });
}

/// DELETE /api/user/tokens/:id - Revoke access token
pub fn delete(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    };

    if (!user.is_active) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Account not activated\"}");
        return;
    }

    // Parse token ID from path
    const token_id_str = req.param("id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing token ID\"}");
        return;
    };

    const token_id = std.fmt.parseInt(i32, token_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid token ID\"}");
        return;
    };

    // Delete the token (only if it belongs to the user)
    const deleted = try db.deleteAccessToken(ctx.pool, token_id, user.id);
    if (!deleted) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Token not found\"}");
        return;
    }

    try res.writer().writeAll("{\"message\":\"Token revoked successfully\"}");
}
