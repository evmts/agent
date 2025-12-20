//! Repository routes - REST API for repository features
//!
//! Implements stars, watches, topics, bookmarks, and changes endpoints
//! matching the Bun implementation at /server/routes/

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("../lib/db.zig");

const log = std.log.scoped(.repo_routes);

// =============================================================================
// Stars/Watches Routes
// =============================================================================

/// GET /:user/:repo/stargazers - Get repository stargazers
pub fn getStargazers(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Get stargazers
    const stargazers = db.getStargazers(ctx.pool, allocator, repo.id) catch |err| {
        log.err("Failed to get stargazers: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to fetch stargazers\"}");
        return;
    };
    defer allocator.free(stargazers);

    var writer = res.writer();
    try writer.writeAll("{\"stargazers\":[");
    for (stargazers, 0..) |stargazer, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{{\"id\":{d},\"username\":\"{s}\",\"displayName\":\"{s}\",\"createdAt\":\"{s}\"}}", .{
            stargazer.id,
            stargazer.username,
            stargazer.display_name orelse "",
            stargazer.created_at,
        });
    }
    try writer.print("],\"total\":{d}}}", .{stargazers.len});
}

/// POST /:user/:repo/star - Star a repository
pub fn starRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Check if already starred
    const existing = db.hasStarred(ctx.pool, user.id, repo.id) catch false;
    if (existing) {
        res.status = 200;
        try res.writer().writeAll("{\"message\":\"Already starred\"}");
        return;
    }

    // Create star
    db.createStar(ctx.pool, user.id, repo.id) catch |err| {
        log.err("Failed to create star: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to star repository\"}");
        return;
    };

    // Get updated count
    const count = db.getStarCount(ctx.pool, repo.id) catch 0;

    var writer = res.writer();
    res.status = 201;
    try writer.print("{{\"message\":\"Repository starred\",\"starCount\":{d}}}", .{count});
}

/// DELETE /:user/:repo/star - Unstar a repository
pub fn unstarRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Delete star
    db.deleteStar(ctx.pool, user.id, repo.id) catch |err| {
        log.err("Failed to delete star: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to unstar repository\"}");
        return;
    };

    // Get updated count
    const count = db.getStarCount(ctx.pool, repo.id) catch 0;

    var writer = res.writer();
    try writer.print("{{\"message\":\"Repository unstarred\",\"starCount\":{d}}}", .{count});
}

/// POST /:user/:repo/watch - Watch a repository
pub fn watchRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Parse body for watch level
    const body = req.body() orelse "{\"level\":\"all\"}";
    const level = extractJsonString(body, "level") orelse "all";

    // Validate level
    if (!std.mem.eql(u8, level, "all") and
        !std.mem.eql(u8, level, "releases") and
        !std.mem.eql(u8, level, "ignore"))
    {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid watch level\"}");
        return;
    }

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Create or update watch
    db.upsertWatch(ctx.pool, user.id, repo.id, level) catch |err| {
        log.err("Failed to watch repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to watch repository\"}");
        return;
    };

    var writer = res.writer();
    try writer.print("{{\"message\":\"Watch preferences updated\",\"level\":\"{s}\"}}", .{level});
}

/// DELETE /:user/:repo/watch - Unwatch a repository
pub fn unwatchRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Delete watch
    db.deleteWatch(ctx.pool, user.id, repo.id) catch |err| {
        log.err("Failed to unwatch repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to unwatch repository\"}");
        return;
    };

    try res.writer().writeAll("{\"message\":\"Repository unwatched\"}");
}

// =============================================================================
// Topics Routes
// =============================================================================

/// GET /:user/:repo/topics - Get repository topics
pub fn getTopics(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository with topics
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    var writer = res.writer();
    try writer.writeAll("{\"topics\":[");
    if (repo.topics) |topics| {
        for (topics, 0..) |topic, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("\"{s}\"", .{topic});
        }
    }
    try writer.writeAll("]}");
}

/// PUT /:user/:repo/topics - Update repository topics
pub fn updateTopics(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    };

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Verify ownership
    if (user.id != repo.user_id) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Forbidden: You don't own this repository\"}");
        return;
    }

    // Parse topics from JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    // Extract topics array from JSON (simple parser)
    const topics = parseTopicsFromJson(allocator, body) catch |err| {
        log.err("Failed to parse topics: {}", .{err});
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON format\"}");
        return;
    };
    defer {
        for (topics) |topic| allocator.free(topic);
        allocator.free(topics);
    }

    // Update topics in database
    db.updateRepositoryTopics(ctx.pool, repo.id, topics) catch |err| {
        log.err("Failed to update topics: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update topics\"}");
        return;
    };

    var writer = res.writer();
    try writer.writeAll("{\"topics\":[");
    for (topics, 0..) |topic, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{topic});
    }
    try writer.writeAll("]}");
}

// =============================================================================
// Bookmarks Routes (jj branches)
// =============================================================================

/// GET /:user/:repo/bookmarks - List bookmarks
pub fn listBookmarks(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Get bookmarks
    const bookmarks = db.listBookmarks(ctx.pool, allocator, repo.id) catch |err| {
        log.err("Failed to list bookmarks: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to list bookmarks\"}");
        return;
    };
    defer allocator.free(bookmarks);

    var writer = res.writer();
    try writer.writeAll("{\"bookmarks\":[");
    for (bookmarks, 0..) |bookmark, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{{\"id\":{d},\"name\":\"{s}\",\"targetChangeId\":\"{s}\",\"isDefault\":{s}}}", .{
            bookmark.id,
            bookmark.name,
            bookmark.target_change_id,
            if (bookmark.is_default) "true" else "false",
        });
    }
    try writer.print("],\"total\":{d}}}", .{bookmarks.len});
}

/// GET /:user/:repo/bookmarks/:name - Get single bookmark
pub fn getBookmark(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const name = req.param("name") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing name parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Get bookmark
    const bookmark = db.getBookmarkByName(ctx.pool, repo.id, name) catch |err| {
        log.err("Failed to get bookmark: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get bookmark\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Bookmark not found\"}");
        return;
    };

    var writer = res.writer();
    try writer.print("{{\"bookmark\":{{\"id\":{d},\"name\":\"{s}\",\"targetChangeId\":\"{s}\",\"isDefault\":{s}}}}}", .{
        bookmark.id,
        bookmark.name,
        bookmark.target_change_id,
        if (bookmark.is_default) "true" else "false",
    });
}

/// POST /:user/:repo/bookmarks - Create bookmark
pub fn createBookmark(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Parse body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const name = extractJsonString(body, "name") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing required field: name\"}");
        return;
    };

    const change_id = extractJsonString(body, "change_id") orelse "HEAD";

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Verify ownership
    if (user.id != repo.user_id) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Forbidden\"}");
        return;
    }

    // Create bookmark
    const bookmark_id = db.createBookmark(ctx.pool, repo.id, name, change_id, user.id) catch |err| {
        log.err("Failed to create bookmark: {}", .{err});
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Failed to create bookmark\"}");
        return;
    };

    var writer = res.writer();
    res.status = 201;
    try writer.print("{{\"bookmark\":{{\"id\":{d},\"name\":\"{s}\",\"targetChangeId\":\"{s}\"}}}}", .{
        bookmark_id,
        name,
        change_id,
    });
}

/// PUT /:user/:repo/bookmarks/:name - Update bookmark
pub fn updateBookmark(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const name = req.param("name") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing name parameter\"}");
        return;
    };

    // Parse body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const change_id = extractJsonString(body, "change_id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing change_id\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Verify ownership
    if (user.id != repo.user_id) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Forbidden\"}");
        return;
    }

    // Update bookmark
    db.updateBookmark(ctx.pool, repo.id, name, change_id, user.id) catch |err| {
        log.err("Failed to update bookmark: {}", .{err});
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Failed to move bookmark\"}");
        return;
    };

    var writer = res.writer();
    try writer.print("{{\"bookmark\":{{\"name\":\"{s}\",\"targetChangeId\":\"{s}\"}}}}", .{
        name,
        change_id,
    });
}

/// DELETE /:user/:repo/bookmarks/:name - Delete bookmark
pub fn deleteBookmark(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const name = req.param("name") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing name parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Verify ownership
    if (user.id != repo.user_id) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Forbidden\"}");
        return;
    }

    // Cannot delete default bookmark
    if (repo.default_branch) |default_branch| {
        if (std.mem.eql(u8, name, default_branch)) {
            res.status = 403;
            try res.writer().writeAll("{\"error\":\"Cannot delete default bookmark\"}");
            return;
        }
    }

    // Delete bookmark
    db.deleteBookmark(ctx.pool, repo.id, name) catch |err| {
        log.err("Failed to delete bookmark: {}", .{err});
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Failed to delete bookmark\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

/// POST /:user/:repo/bookmarks/:name/set-default - Set bookmark as default
pub fn setDefaultBookmark(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const name = req.param("name") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing name parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Verify ownership
    if (user.id != repo.user_id) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Forbidden\"}");
        return;
    }

    // Check that bookmark exists
    const bookmark = db.getBookmarkByName(ctx.pool, repo.id, name) catch |err| {
        log.err("Failed to check bookmark: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Bookmark not found\"}");
        return;
    };
    _ = bookmark;

    // Set as default
    db.setDefaultBookmark(ctx.pool, repo.id, name) catch |err| {
        log.err("Failed to set default bookmark: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to set default bookmark\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

// =============================================================================
// Changes Routes (jj changes)
// =============================================================================

/// GET /:user/:repo/changes - List changes
pub fn listChanges(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Get changes (stub - would call jj in production)
    const changes = db.listChanges(ctx.pool, allocator, repo.id) catch |err| {
        log.err("Failed to list changes: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to list changes\"}");
        return;
    };
    defer allocator.free(changes);

    var writer = res.writer();
    try writer.writeAll("{\"changes\":[");
    for (changes, 0..) |change, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{{\"changeId\":\"{s}\",\"commitId\":\"{s}\",\"description\":\"{s}\"}}", .{
            change.change_id,
            change.commit_id,
            change.description,
        });
    }
    try writer.print("],\"total\":{d}}}", .{changes.len});
}

/// GET /:user/:repo/changes/:changeId - Get change
pub fn getChange(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Get change
    const change = db.getChangeById(ctx.pool, repo.id, change_id) catch |err| {
        log.err("Failed to get change: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get change\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Change not found\"}");
        return;
    };

    var writer = res.writer();
    try writer.print("{{\"change\":{{\"changeId\":\"{s}\",\"commitId\":\"{s}\",\"description\":\"{s}\"}}}}", .{
        change.change_id,
        change.commit_id,
        change.description,
    });
}

/// GET /:user/:repo/changes/:changeId/diff - Get change diff
pub fn getChangeDiff(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Get diff (stub - would call jj diff in production)
    _ = repo;
    _ = change_id;

    var writer = res.writer();
    try writer.writeAll("{\"diff\":\"(diff output would go here)\"}");
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Extract string value from simple JSON (avoids full JSON parser)
pub fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    var pattern_buf: [256]u8 = undefined;
    const pattern = std.fmt.bufPrint(&pattern_buf, "\"{s}\":\"", .{key}) catch return null;

    const start_idx = std.mem.indexOf(u8, json, pattern) orelse return null;
    const value_start = start_idx + pattern.len;

    const value_end = std.mem.indexOfPos(u8, json, value_start, "\"") orelse return null;

    return json[value_start..value_end];
}

/// Parse topics array from JSON
pub fn parseTopicsFromJson(allocator: std.mem.Allocator, json: []const u8) ![][]const u8 {
    // Find "topics":[...]
    const topics_start = std.mem.indexOf(u8, json, "\"topics\":[") orelse return error.InvalidJson;
    const array_start = topics_start + 10;
    const array_end = std.mem.indexOfPos(u8, json, array_start, "]") orelse return error.InvalidJson;

    const array_content = json[array_start..array_end];

    // Count topics
    var count: usize = 0;
    var iter = std.mem.splitScalar(u8, array_content, ',');
    while (iter.next()) |_| count += 1;

    if (count == 0) return &[_][]const u8{};

    // Parse topics
    var topics = try allocator.alloc([]const u8, count);
    errdefer allocator.free(topics);

    var i: usize = 0;
    iter = std.mem.splitScalar(u8, array_content, ',');
    while (iter.next()) |item| : (i += 1) {
        const trimmed = std.mem.trim(u8, item, " \t\n\r");
        if (trimmed.len < 2) return error.InvalidJson;
        // Remove quotes and normalize to lowercase
        const topic = trimmed[1 .. trimmed.len - 1];
        var normalized = try allocator.alloc(u8, topic.len);
        for (topic, 0..) |c, j| {
            normalized[j] = std.ascii.toLower(c);
        }
        topics[i] = normalized;
    }

    return topics;
}
