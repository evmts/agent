//! User routes
//!
//! Handles user profile and search operations:
//! - GET /users/search - Search users by query
//! - GET /users/:username - Get public user profile
//! - PATCH /users/me - Update own profile

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("../lib/db.zig");

const log = std.log.scoped(.user_routes);

/// GET /users/search?q=query
/// Search active users by username
pub fn search(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const query = req.query.get("q") orelse {
        res.status = .@"Bad Request";
        try res.writer().writeAll("{\"error\":\"Missing query parameter 'q'\"}");
        return;
    };

    if (query.len < 2) {
        res.status = .@"Bad Request";
        try res.writer().writeAll("{\"error\":\"Query must be at least 2 characters\"}");
        return;
    }

    // Search users (using LIKE pattern)
    var conn = try ctx.pool.acquire();
    defer conn.release();

    var pattern_buf: [256]u8 = undefined;
    const pattern = try std.fmt.bufPrint(&pattern_buf, "%{s}%", .{query});

    var result = try conn.query(
        \\SELECT id, username, display_name, avatar_url
        \\FROM users
        \\WHERE is_active = true AND lower_username LIKE lower($1)
        \\ORDER BY username
        \\LIMIT 20
    , .{pattern});
    defer result.deinit();

    // Build JSON array
    var writer = res.writer();
    try writer.writeAll("{\"users\":[");

    var first = true;
    while (try result.next()) |row| {
        if (!first) try writer.writeAll(",");
        first = false;

        const id: i64 = row.get(i64, 0);
        const username: []const u8 = row.get([]const u8, 1);
        const display_name: ?[]const u8 = row.get(?[]const u8, 2);
        const avatar_url: ?[]const u8 = row.get(?[]const u8, 3);

        try writer.print(
            \\{{"id":{d},"username":"{s}","displayName":{s},"avatarUrl":{s}}}
        , .{
            id,
            username,
            if (display_name) |d| try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{d}) else "null",
            if (avatar_url) |a| try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{a}) else "null",
        });
    }

    try writer.writeAll("]}");
}

/// GET /users/:username
/// Get public user profile
pub fn getProfile(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const username = req.param("username") orelse {
        res.status = .@"Bad Request";
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    // Get user
    const user = try db.getUserByUsername(ctx.pool, username);
    if (user == null) {
        res.status = .@"Not Found";
        try res.writer().writeAll("{\"error\":\"User not found\"}");
        return;
    }

    const u = user.?;

    // Count repositories
    var conn = try ctx.pool.acquire();
    defer conn.release();

    var repo_result = try conn.query(
        \\SELECT COUNT(*) FROM repositories WHERE owner_id = $1
    , .{u.id});
    defer repo_result.deinit();

    var repo_count: i64 = 0;
    if (try repo_result.next()) |row| {
        repo_count = row.get(i64, 0);
    }

    // Return profile
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"username":"{s}","displayName":{s},"bio":{s},"avatarUrl":{s},"repositoryCount":{d}}}
    , .{
        u.id,
        u.username,
        if (u.display_name) |d| try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{d}) else "null",
        "null", // bio not in UserRecord, would need separate query
        "null", // avatar_url not in UserRecord
        repo_count,
    });
}

/// PATCH /users/me
/// Update own profile
pub fn updateProfile(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = .unauthorized;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const user_id = ctx.user.?.id;

    // Parse JSON body
    const body = req.body() orelse {
        res.status = .@"Bad Request";
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        displayName: ?[]const u8 = null,
        bio: ?[]const u8 = null,
        email: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = .@"Bad Request";
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Build dynamic UPDATE query
    var conn = try ctx.pool.acquire();
    defer conn.release();

    // For simplicity, update all fields that are provided
    if (v.displayName) |display_name| {
        _ = try conn.exec(
            \\UPDATE users SET display_name = $1, updated_at = NOW() WHERE id = $2
        , .{ display_name, user_id });
    }

    if (v.bio) |bio| {
        _ = try conn.exec(
            \\UPDATE users SET bio = $1, updated_at = NOW() WHERE id = $2
        , .{ bio, user_id });
    }

    if (v.email) |email| {
        _ = try conn.exec(
            \\UPDATE users SET email = $1, updated_at = NOW() WHERE id = $2
        , .{ email, user_id });
    }

    try res.writer().writeAll("{\"message\":\"Profile updated\"}");
}
