//! User routes
//!
//! Handles user profile and search operations:
//! - GET /users/search - Search users by query
//! - GET /users/:username - Get public user profile
//! - PATCH /users/me - Update own profile

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");
const auth = @import("../middleware/auth.zig");

const log = std.log.scoped(.user_routes);

/// Escape LIKE special characters to prevent SQL injection
/// Escapes: %, _, [, ]
fn escapeLikePattern(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    // Count special characters to determine buffer size
    var special_count: usize = 0;
    for (input) |c| {
        if (c == '%' or c == '_' or c == '[' or c == ']') {
            special_count += 1;
        }
    }

    // Allocate buffer with extra space for escape characters
    const escaped = try allocator.alloc(u8, input.len + special_count);
    var idx: usize = 0;

    for (input) |c| {
        if (c == '%' or c == '_' or c == '[' or c == ']') {
            escaped[idx] = '\\';
            idx += 1;
        }
        escaped[idx] = c;
        idx += 1;
    }

    return escaped;
}

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

    // Sanitize query to prevent SQL injection in LIKE pattern
    const escaped_query = try escapeLikePattern(ctx.allocator, query);
    defer ctx.allocator.free(escaped_query);

    var pattern_buf: [512]u8 = undefined;
    const pattern = try std.fmt.bufPrint(&pattern_buf, "%{s}%", .{escaped_query});

    var result = try conn.query(
        \\SELECT id, username, display_name, avatar_url
        \\FROM users
        \\WHERE is_active = true AND lower_username LIKE lower($1) ESCAPE '\'
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
            \\{{"id":{d},"username":"{s}","displayName":
        , .{ id, username });
        if (display_name) |d| {
            try writer.print("\"{s}\"", .{d});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"avatarUrl\":");
        if (avatar_url) |a| {
            try writer.print("\"{s}\"", .{a});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll("}}");
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
        \\SELECT COUNT(*) FROM repositories WHERE user_id = $1
    , .{u.id});
    defer repo_result.deinit();

    var repo_count: i64 = 0;
    if (try repo_result.next()) |row| {
        repo_count = row.get(i64, 0);
    }

    // Return profile
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"username":"{s}","displayName":
    , .{ u.id, u.username });
    if (u.display_name) |d| {
        try writer.print("\"{s}\"", .{d});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(
        \\,"bio":null,"avatarUrl":null,"repositoryCount":{d}}}
    , .{repo_count});
}

/// GET /api/users - List all users (paginated)
pub fn listUsers(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const query_params = try req.query();

    const limit_str = query_params.get("limit") orelse "50";
    const offset_str = query_params.get("offset") orelse "0";

    const limit = std.fmt.parseInt(i32, limit_str, 10) catch 50;
    const offset = std.fmt.parseInt(i32, offset_str, 10) catch 0;

    const safe_limit: i32 = if (limit > 100) 100 else if (limit < 1) 1 else limit;
    const safe_offset: i32 = if (offset < 0) 0 else offset;

    var conn = try ctx.pool.acquire();
    defer conn.release();

    // Get total count first (before the main query to avoid ConnectionBusy)
    var total: i32 = 0;
    {
        var count_result = try conn.query(
            \\SELECT COUNT(*)::int as count FROM users WHERE is_active = true
        , .{});

        if (try count_result.next()) |row| {
            total = row.get(i32, 0);
        }
        try count_result.drain();
        count_result.deinit();
    }

    var result = try conn.query(
        \\SELECT u.id, u.username, u.display_name, u.avatar_url, u.created_at,
        \\       (SELECT COUNT(*)::int FROM repositories WHERE user_id = u.id) as repo_count
        \\FROM users u
        \\WHERE u.is_active = true
        \\ORDER BY u.username
        \\LIMIT $1 OFFSET $2
    , .{ safe_limit, safe_offset });
    defer result.deinit();

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
        const created_at: i64 = row.get(i64, 4);
        const repo_count: i32 = row.get(i32, 5);

        try writer.print(
            \\{{"id":{d},"username":"{s}","displayName":
        , .{ id, username });
        if (display_name) |d| {
            try writer.print("\"{s}\"", .{d});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"avatarUrl\":");
        if (avatar_url) |a| {
            try writer.print("\"{s}\"", .{a});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"repositoryCount\":{d},\"createdAt\":{d}}}", .{
            repo_count,
            created_at,
        });
    }

    try writer.print("],\"total\":{d},\"limit\":{d},\"offset\":{d}}}", .{
        total,
        safe_limit,
        safe_offset,
    });
}

/// GET /api/users/:username/repos - List user's repositories
pub fn getUserRepos(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const username = req.param("username") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const query_params = try req.query();
    const limit_str = query_params.get("limit") orelse "50";
    const limit = std.fmt.parseInt(i32, limit_str, 10) catch 50;
    const safe_limit: i32 = if (limit > 100) 100 else if (limit < 1) 1 else limit;

    // Get user
    const user = try db.getUserByUsername(ctx.pool, username);
    if (user == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"User not found\"}");
        return;
    }

    const u = user.?;

    var conn = try ctx.pool.acquire();
    defer conn.release();

    // Check if requesting user is the owner (can see private repos)
    const show_private = if (ctx.user) |current_user| current_user.id == u.id else false;

    var result = if (show_private)
        try conn.query(
            \\SELECT id, name, description, is_public, default_branch, created_at, updated_at
            \\FROM repositories
            \\WHERE user_id = $1
            \\ORDER BY updated_at DESC
            \\LIMIT $2
        , .{ u.id, safe_limit })
    else
        try conn.query(
            \\SELECT id, name, description, is_public, default_branch, created_at, updated_at
            \\FROM repositories
            \\WHERE user_id = $1 AND is_public = true
            \\ORDER BY updated_at DESC
            \\LIMIT $2
        , .{ u.id, safe_limit });
    defer result.deinit();

    var writer = res.writer();
    try writer.print("{{\"owner\":\"{s}\",\"repositories\":[", .{username});

    var first = true;
    var count: i32 = 0;
    while (try result.next()) |row| {
        if (!first) try writer.writeAll(",");
        first = false;
        count += 1;

        const id: i64 = row.get(i64, 0);
        const name: []const u8 = row.get([]const u8, 1);
        const description: ?[]const u8 = row.get(?[]const u8, 2);
        const is_public: bool = row.get(bool, 3);
        const default_branch: ?[]const u8 = row.get(?[]const u8, 4);
        const created_at: i64 = row.get(i64, 5);
        const updated_at: i64 = row.get(i64, 6);

        try writer.print("{{\"id\":{d},\"name\":\"{s}\",\"description\":", .{ id, name });
        if (description) |d| {
            // Escape JSON special characters
            try writer.writeAll("\"");
            for (d) |c| {
                switch (c) {
                    '"' => try writer.writeAll("\\\""),
                    '\\' => try writer.writeAll("\\\\"),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    '\t' => try writer.writeAll("\\t"),
                    else => try writer.writeByte(c),
                }
            }
            try writer.writeAll("\"");
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"isPrivate\":{s},\"defaultBranch\":", .{
            if (!is_public) "true" else "false",
        });
        if (default_branch) |b| {
            try writer.print("\"{s}\"", .{b});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"createdAt\":{d},\"updatedAt\":{d}}}", .{
            created_at,
            updated_at,
        });
    }

    try writer.print("],\"count\":{d}}}", .{count});
}

/// GET /api/users/:username/starred - List repositories starred by user
pub fn getUserStarredRepos(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const username = req.param("username") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const query_params = try req.query();
    const limit_str = query_params.get("limit") orelse "50";
    const offset_str = query_params.get("offset") orelse "0";

    const limit = std.fmt.parseInt(i32, limit_str, 10) catch 50;
    const offset = std.fmt.parseInt(i32, offset_str, 10) catch 0;

    const safe_limit: i32 = if (limit > 100) 100 else if (limit < 1) 1 else limit;
    const safe_offset: i32 = if (offset < 0) 0 else offset;

    // Get user
    const user = try db.getUserByUsername(ctx.pool, username);
    if (user == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"User not found\"}");
        return;
    }

    const u = user.?;

    var conn = try ctx.pool.acquire();
    defer conn.release();

    // Get total count first (before the main query to avoid ConnectionBusy)
    var total: i32 = 0;
    {
        var count_result = try conn.query(
            \\SELECT COUNT(*)::int as count
            \\FROM stars s
            \\JOIN repositories r ON s.repository_id = r.id
            \\WHERE s.user_id = $1 AND r.is_public = true
        , .{u.id});

        if (try count_result.next()) |row| {
            total = row.get(i32, 0);
        }
        try count_result.drain();
        count_result.deinit();
    }

    var result = try conn.query(
        \\SELECT r.id, r.name, r.description, r.is_public, r.default_branch,
        \\       r.created_at, r.updated_at, o.username as owner, s.created_at as starred_at
        \\FROM stars s
        \\JOIN repositories r ON s.repository_id = r.id
        \\JOIN users o ON r.user_id = o.id
        \\WHERE s.user_id = $1 AND r.is_public = true
        \\ORDER BY s.created_at DESC
        \\LIMIT $2 OFFSET $3
    , .{ u.id, safe_limit, safe_offset });
    defer result.deinit();

    var writer = res.writer();
    try writer.print("{{\"user\":\"{s}\",\"repositories\":[", .{username});

    var first = true;
    while (try result.next()) |row| {
        if (!first) try writer.writeAll(",");
        first = false;

        const id: i64 = row.get(i64, 0);
        const name: []const u8 = row.get([]const u8, 1);
        const description: ?[]const u8 = row.get(?[]const u8, 2);
        const is_public: bool = row.get(bool, 3);
        const default_branch: ?[]const u8 = row.get(?[]const u8, 4);
        const created_at: i64 = row.get(i64, 5);
        const updated_at: i64 = row.get(i64, 6);
        const owner: []const u8 = row.get([]const u8, 7);
        const starred_at: i64 = row.get(i64, 8);

        try writer.print("{{\"id\":{d},\"name\":\"{s}\",\"owner\":\"{s}\",\"description\":", .{
            id,
            name,
            owner,
        });
        if (description) |d| {
            // Escape JSON special characters
            try writer.writeAll("\"");
            for (d) |c| {
                switch (c) {
                    '"' => try writer.writeAll("\\\""),
                    '\\' => try writer.writeAll("\\\\"),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    '\t' => try writer.writeAll("\\t"),
                    else => try writer.writeByte(c),
                }
            }
            try writer.writeAll("\"");
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"isPrivate\":{s},\"defaultBranch\":", .{
            if (!is_public) "true" else "false",
        });
        if (default_branch) |b| {
            try writer.print("\"{s}\"", .{b});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"createdAt\":{d},\"updatedAt\":{d},\"starredAt\":{d}}}", .{
            created_at,
            updated_at,
            starred_at,
        });
    }

    try writer.print("],\"total\":{d}}}", .{total});
}

/// PATCH /users/me
/// Update own profile
pub fn updateProfile(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .user_write)) return;

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

    // Notify edge of user profile update
    if (ctx.edge_notifier) |notifier| {
        notifier.notifySqlChange("users", null) catch |err| {
            log.warn("Failed to notify edge of user profile update: {}", .{err});
        };
    }

    try res.writer().writeAll("{\"message\":\"Profile updated successfully\"}");
}
