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

    const query_params = try req.query();
    const query = query_params.get("q") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing query parameter 'q'\"}");
        return;
    };

    if (query.len < 2) {
        res.status = 400;
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
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    // Get user
    const user = try db.getUserByUsername(ctx.pool, username);
    if (user == null) {
        res.status = 404;
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
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    if (!ctx.user.?.is_active) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Account not activated\"}");
        return;
    }

    const user_id = ctx.user.?.id;

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        displayName: ?[]const u8 = null,
        bio: ?[]const u8 = null,
        email: ?[]const u8 = null,
        avatarUrl: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Validate field lengths
    if (v.displayName) |dn| {
        if (dn.len > 255) {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Display name must be at most 255 characters\"}");
            return;
        }
    }

    if (v.bio) |b| {
        if (b.len > 2000) {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Bio must be at most 2000 characters\"}");
            return;
        }
    }

    if (v.email) |e| {
        if (e.len > 255) {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Email must be at most 255 characters\"}");
            return;
        }
        // Basic email validation
        if (std.mem.indexOf(u8, e, "@") == null) {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Invalid email address\"}");
            return;
        }
    }

    if (v.avatarUrl) |au| {
        if (au.len > 2048) {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Avatar URL must be at most 2048 characters\"}");
            return;
        }
    }

    // Check if at least one field is provided
    if (v.displayName == null and v.bio == null and v.email == null and v.avatarUrl == null) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"No updates provided\"}");
        return;
    }

    // Update profile using db function
    try db.updateUserProfile(ctx.pool, user_id, v.displayName, v.bio, v.email);

    // Handle avatar URL separately (not in updateUserProfile function)
    if (v.avatarUrl) |avatar_url| {
        var conn = try ctx.pool.acquire();
        defer conn.release();
        _ = try conn.exec(
            \\UPDATE users SET avatar_url = $1, updated_at = NOW() WHERE id = $2
        , .{ avatar_url, user_id });
    }

    try res.writer().writeAll("{\"message\":\"Profile updated successfully\"}");
}
