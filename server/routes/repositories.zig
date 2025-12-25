//! Repository routes - REST API for repository features
//!
//! Implements repository CRUD, stars, watches, topics, bookmarks, and changes endpoints
//! matching the Bun implementation at /server/routes/

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");
const auth = @import("../middleware/auth.zig");

const log = std.log.scoped(.repo_routes);

// Import jj-ffi C bindings
const c = @cImport({
    @cInclude("jj_ffi.h");
});

// =============================================================================
// Helper Functions
// =============================================================================

/// Get the repository path on disk
fn getRepoPath(allocator: std.mem.Allocator, username: []const u8, reponame: []const u8) ![]const u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    return std.fmt.allocPrint(allocator, "{s}/repos/{s}/{s}", .{ cwd, username, reponame });
}

/// Run a jj command and return stdout
fn runJjCommand(allocator: std.mem.Allocator, repo_path: []const u8, args: []const []const u8) ![]const u8 {
    var arg_list = try std.ArrayList([]const u8).initCapacity(allocator, args.len + 1);
    defer arg_list.deinit(allocator);

    try arg_list.append(allocator, "jj");
    for (args) |arg| {
        try arg_list.append(allocator, arg);
    }

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = arg_list.items,
        .cwd = repo_path,
        .max_output_bytes = 10 * 1024 * 1024, // 10MB
    });
    defer allocator.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.JjCommandFailed;
    }

    return result.stdout;
}

/// Escape a string for JSON
fn escapeJson(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, input.len * 2);
    defer result.deinit(allocator);

    for (input) |char| {
        switch (char) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, char),
        }
    }

    return result.toOwnedSlice(allocator);
}

// =============================================================================
// Repository CRUD Routes
// =============================================================================

/// POST /api/repos - Create a new repository
/// Requires authentication and repo:write scope
pub fn createRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .repo_write)) return;

    const user = ctx.user.?; // Safe unwrap - checkScope verified user exists

    // Parse request body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    // Extract fields from JSON
    const name = extractJsonString(body, "name") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing required field: name\"}");
        return;
    };

    // Validate repository name
    if (name.len == 0 or name.len > 100) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Repository name must be 1-100 characters\"}");
        return;
    }

    // Check for valid characters (alphanumeric, dash, underscore)
    for (name) |char| {
        if (!std.ascii.isAlphanumeric(char) and char != '-' and char != '_' and char != '.') {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Repository name can only contain alphanumeric characters, dashes, underscores, and dots\"}");
            return;
        }
    }

    // Reserved names
    const reserved_names = [_][]const u8{ "new", "settings", "admin", "api", "help", "explore" };
    for (reserved_names) |reserved| {
        if (std.ascii.eqlIgnoreCase(name, reserved)) {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"This repository name is reserved\"}");
            return;
        }
    }

    const description = extractJsonString(body, "description");
    const is_public = extractJsonBool(body, "is_public") orelse true;

    // Check if repository already exists
    const exists = db.repositoryExists(ctx.pool, user.id, name) catch |err| {
        log.err("Failed to check repository existence: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    };

    if (exists) {
        res.status = 409;
        try res.writer().writeAll("{\"error\":\"A repository with this name already exists\"}");
        return;
    }

    // Create the repository
    const repo_id = db.createRepository(ctx.pool, user.id, name, description, is_public) catch |err| {
        log.err("Failed to create repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create repository\"}");
        return;
    };

    // Initialize the repository on disk with jj
    const repo_path = getRepoPath(ctx.allocator, user.username, name) catch |err| {
        log.err("Failed to construct repository path: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create repository\"}");
        return;
    };
    defer ctx.allocator.free(repo_path);

    // Ensure parent directory exists
    const parent_dir = std.fs.path.dirname(repo_path) orelse {
        log.err("Failed to get parent directory for: {s}", .{repo_path});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create repository\"}");
        return;
    };
    std.fs.cwd().makePath(parent_dir) catch |err| {
        log.err("Failed to create parent directory {s}: {}", .{ parent_dir, err });
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create repository\"}");
        return;
    };

    // Initialize jj workspace
    const repo_path_z = try ctx.allocator.dupeZ(u8, repo_path);
    defer ctx.allocator.free(repo_path_z);

    const workspace_result = c.jj_workspace_init(repo_path_z.ptr);
    defer {
        if (workspace_result.success and workspace_result.workspace != null) {
            c.jj_workspace_free(workspace_result.workspace);
        }
        if (workspace_result.error_message != null) {
            c.jj_string_free(workspace_result.error_message);
        }
    }

    if (!workspace_result.success) {
        const err_msg = if (workspace_result.error_message != null)
            std.mem.span(workspace_result.error_message)
        else
            "Unknown error";
        log.err("Failed to initialize jj workspace at {s}: {s}", .{ repo_path, err_msg });
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to initialize repository workspace\"}");
        return;
    }

    log.info("Repository created: {s}/{s} (id={d}) at {s}", .{ user.username, name, repo_id, repo_path });

    // Notify edge of repository creation
    if (ctx.edge_notifier) |notifier| {
        const repo_key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ user.username, name });
        defer ctx.allocator.free(repo_key);
        notifier.notifySqlChange("repositories", repo_key) catch |err| {
            log.warn("Failed to notify edge of repository creation: {}", .{err});
            // Don't fail the request, edge will sync eventually
        };
    }

    var writer = res.writer();
    res.status = 201;
    try writer.print("{{\"repository\":{{\"id\":{d},\"name\":\"{s}\",\"owner\":\"{s}\",\"description\":", .{
        repo_id,
        name,
        user.username,
    });
    if (description) |d| {
        try writer.print("\"{s}\"", .{d});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"isPublic\":{s}}}}}", .{
        if (is_public) "true" else "false",
    });
}

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

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .repo_write)) return;

    const user = ctx.user.?;

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

    // Notify edge of star creation
    if (ctx.edge_notifier) |notifier| {
        const repo_key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ username, reponame });
        defer ctx.allocator.free(repo_key);
        notifier.notifySqlChange("stars", repo_key) catch |err| {
            log.warn("Failed to notify edge of star creation: {}", .{err});
        };
    }

    // Get updated count
    const count = db.getStarCount(ctx.pool, repo.id) catch 0;

    var writer = res.writer();
    res.status = 201;
    try writer.print("{{\"message\":\"Repository starred\",\"starCount\":{d}}}", .{count});
}

/// DELETE /:user/:repo/star - Unstar a repository
pub fn unstarRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .repo_write)) return;

    const user = ctx.user.?;

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

    // Notify edge of star deletion
    if (ctx.edge_notifier) |notifier| {
        const repo_key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ username, reponame });
        defer ctx.allocator.free(repo_key);
        notifier.notifySqlChange("stars", repo_key) catch |err| {
            log.warn("Failed to notify edge of star deletion: {}", .{err});
        };
    }

    // Get updated count
    const count = db.getStarCount(ctx.pool, repo.id) catch 0;

    var writer = res.writer();
    try writer.print("{{\"message\":\"Repository unstarred\",\"starCount\":{d}}}", .{count});
}

/// POST /:user/:repo/watch - Watch a repository
pub fn watchRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .repo_write)) return;

    const user = ctx.user.?;

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

    // Notify edge of watch update
    if (ctx.edge_notifier) |notifier| {
        const repo_key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ username, reponame });
        defer ctx.allocator.free(repo_key);
        notifier.notifySqlChange("watchers", repo_key) catch |err| {
            log.warn("Failed to notify edge of watch update: {}", .{err});
        };
    }

    var writer = res.writer();
    try writer.print("{{\"message\":\"Watch preferences updated\",\"level\":\"{s}\"}}", .{level});
}

/// DELETE /:user/:repo/watch - Unwatch a repository
pub fn unwatchRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .repo_write)) return;

    const user = ctx.user.?;

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

    // Notify edge of watch deletion
    if (ctx.edge_notifier) |notifier| {
        const repo_key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ username, reponame });
        defer ctx.allocator.free(repo_key);
        notifier.notifySqlChange("watchers", repo_key) catch |err| {
            log.warn("Failed to notify edge of watch deletion: {}", .{err});
        };
    }

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

    // Get repository to verify it exists
    _ = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
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
    // Topics are now fetched separately since pg.zig doesn't support PostgreSQL arrays
    // For now, return empty array - topics functionality can be restored with a separate query
    try writer.writeAll("{\"topics\":[]}");
}

/// PUT /:user/:repo/topics - Update repository topics
pub fn updateTopics(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .repo_write)) return;

    const user = ctx.user.?;

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

    // Notify edge of topics update
    if (ctx.edge_notifier) |notifier| {
        const repo_key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ username, reponame });
        defer ctx.allocator.free(repo_key);
        notifier.notifySqlChange("repositories", repo_key) catch |err| {
            log.warn("Failed to notify edge of topics update: {}", .{err});
        };
    }

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

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .repo_write)) return;

    const user = ctx.user.?;

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

    // Notify edge of bookmark creation
    if (ctx.edge_notifier) |notifier| {
        const repo_key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ username, reponame });
        defer ctx.allocator.free(repo_key);
        notifier.notifySqlChange("bookmarks", repo_key) catch |err| {
            log.warn("Failed to notify edge of bookmark creation: {}", .{err});
        };
    }

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

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .repo_write)) return;

    const user = ctx.user.?;

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
    db.updateBookmark(ctx.pool, repo.id, name, change_id) catch |err| {
        log.err("Failed to update bookmark: {}", .{err});
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Failed to move bookmark\"}");
        return;
    };

    // Notify edge of bookmark update
    if (ctx.edge_notifier) |notifier| {
        const repo_key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ username, reponame });
        defer ctx.allocator.free(repo_key);
        notifier.notifySqlChange("bookmarks", repo_key) catch |err| {
            log.warn("Failed to notify edge of bookmark update: {}", .{err});
        };
    }

    var writer = res.writer();
    try writer.print("{{\"bookmark\":{{\"name\":\"{s}\",\"targetChangeId\":\"{s}\"}}}}", .{
        name,
        change_id,
    });
}

/// DELETE /:user/:repo/bookmarks/:name - Delete bookmark
pub fn deleteBookmark(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .repo_write)) return;

    const user = ctx.user.?;

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

    // Notify edge of bookmark deletion
    if (ctx.edge_notifier) |notifier| {
        const repo_key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ username, reponame });
        defer ctx.allocator.free(repo_key);
        notifier.notifySqlChange("bookmarks", repo_key) catch |err| {
            log.warn("Failed to notify edge of bookmark deletion: {}", .{err});
        };
    }

    try res.writer().writeAll("{\"success\":true}");
}

/// POST /:user/:repo/bookmarks/:name/set-default - Set bookmark as default
pub fn setDefaultBookmark(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Check scope (also checks authentication)
    if (!try auth.checkScope(ctx, res, .repo_write)) return;

    const user = ctx.user.?;

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

    // Notify edge of default bookmark change
    if (ctx.edge_notifier) |notifier| {
        const repo_key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ username, reponame });
        defer ctx.allocator.free(repo_key);
        notifier.notifySqlChange("repositories", repo_key) catch |err| {
            log.warn("Failed to notify edge of default bookmark change: {}", .{err});
        };
    }

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

    // Get repository (verify it exists)
    _ = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Get repository path on disk
    const repo_path = getRepoPath(allocator, username, reponame) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to access repository\"}");
        return;
    };
    defer allocator.free(repo_path);

    // Check if it's a jj workspace
    const repo_path_z = try allocator.dupeZ(u8, repo_path);
    defer allocator.free(repo_path_z);

    const is_jj = c.jj_is_jj_workspace(repo_path_z.ptr);
    if (!is_jj) {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Repository is not a jj workspace\"}");
        return;
    }

    // Open the workspace
    const workspace_result = c.jj_workspace_open(repo_path_z.ptr);
    defer {
        if (workspace_result.success and workspace_result.workspace != null) {
            c.jj_workspace_free(workspace_result.workspace);
        }
        if (workspace_result.error_message != null) {
            c.jj_string_free(workspace_result.error_message);
        }
    }

    if (!workspace_result.success) {
        const err_msg = if (workspace_result.error_message != null)
            std.mem.span(workspace_result.error_message)
        else
            "Unknown error";
        log.err("Failed to open workspace: {s}", .{err_msg});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to open repository workspace\"}");
        return;
    }

    const workspace = workspace_result.workspace;

    // List changes from jj
    const changes_result = c.jj_list_changes(workspace, 50, null);
    defer {
        if (changes_result.success and changes_result.commits != null) {
            c.jj_commit_array_free(changes_result.commits, changes_result.len);
        }
        if (changes_result.error_message != null) {
            c.jj_string_free(changes_result.error_message);
        }
    }

    if (!changes_result.success) {
        const err_msg = if (changes_result.error_message != null)
            std.mem.span(changes_result.error_message)
        else
            "Unknown error";
        log.err("Failed to list changes: {s}", .{err_msg});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to list changes\"}");
        return;
    }

    var writer = res.writer();
    try writer.writeAll("{\"changes\":[");
    const commits = changes_result.commits[0..changes_result.len];
    for (commits, 0..) |commit_ptr, i| {
        if (i > 0) try writer.writeAll(",");
        const commit = commit_ptr.*;
        const change_id = std.mem.span(commit.change_id);
        const commit_id = std.mem.span(commit.id);
        const description = std.mem.span(commit.description);
        try writer.print("{{\"changeId\":\"{s}\",\"commitId\":\"{s}\",\"description\":\"{s}\"}}", .{
            change_id,
            commit_id,
            description,
        });
    }
    try writer.print("],\"total\":{d}}}", .{changes_result.len});
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
    const commit_id = change.commit_id orelse "";
    const description = change.description orelse "";
    try writer.print("{{\"change\":{{\"changeId\":\"{s}\",\"commitId\":\"{s}\",\"description\":\"{s}\"}}}}", .{
        change.change_id,
        commit_id,
        description,
    });
}

/// GET /:user/:repo/changes/:changeId/diff - Get change diff
pub fn getChangeDiff(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
    _ = repo;

    // Get repository path on disk
    const repo_path = getRepoPath(allocator, username, reponame) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to access repository\"}");
        return;
    };
    defer allocator.free(repo_path);

    // Use jj CLI to get diff for this change
    const args = &[_][]const u8{ "diff", "-r", change_id };
    const diff_output = runJjCommand(allocator, repo_path, args) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get diff\"}");
        return;
    };
    defer allocator.free(diff_output);

    const escaped = try escapeJson(allocator, diff_output);
    defer allocator.free(escaped);

    var writer = res.writer();
    try writer.print("{{\"diff\":\"{s}\"}}", .{escaped});
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

/// Extract boolean value from simple JSON
pub fn extractJsonBool(json: []const u8, key: []const u8) ?bool {
    var pattern_buf: [256]u8 = undefined;
    const pattern = std.fmt.bufPrint(&pattern_buf, "\"{s}\":", .{key}) catch return null;

    const start_idx = std.mem.indexOf(u8, json, pattern) orelse return null;
    const value_start = start_idx + pattern.len;

    // Skip whitespace
    var pos = value_start;
    while (pos < json.len and (json[pos] == ' ' or json[pos] == '\t')) : (pos += 1) {}

    if (pos + 4 <= json.len and std.mem.eql(u8, json[pos .. pos + 4], "true")) {
        return true;
    }
    if (pos + 5 <= json.len and std.mem.eql(u8, json[pos .. pos + 5], "false")) {
        return false;
    }

    return null;
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
        for (topic, 0..) |char, j| {
            normalized[j] = std.ascii.toLower(char);
        }
        topics[i] = normalized;
    }

    return topics;
}

// =============================================================================
// Public Repository Listing Routes
// =============================================================================

/// GET /api/repos - List public repositories
pub fn listPublicRepos(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const query_params = try req.query();

    // Parse pagination params
    const limit_str = query_params.get("limit") orelse "50";
    const offset_str = query_params.get("offset") orelse "0";
    const sort_by = query_params.get("sort") orelse "updated_at";

    const limit = std.fmt.parseInt(i32, limit_str, 10) catch 50;
    const offset = std.fmt.parseInt(i32, offset_str, 10) catch 0;

    // Validate limit
    const safe_limit: i32 = if (limit > 100) 100 else if (limit < 1) 1 else limit;
    const safe_offset: i32 = if (offset < 0) 0 else offset;

    // Validate sort
    const valid_sort = if (std.mem.eql(u8, sort_by, "name") or
        std.mem.eql(u8, sort_by, "updated_at") or
        std.mem.eql(u8, sort_by, "created_at"))
        sort_by
    else
        "updated_at";

    var conn = try ctx.pool.acquire();
    defer conn.release();

    // Build and execute query based on sort
    const query = if (std.mem.eql(u8, valid_sort, "name"))
        \\SELECT r.id, r.name, r.description, r.is_private, r.default_branch,
        \\       r.created_at, r.updated_at, u.username as owner
        \\FROM repositories r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE r.is_private = false
        \\ORDER BY r.name
        \\LIMIT $1 OFFSET $2
    else if (std.mem.eql(u8, valid_sort, "created_at"))
        \\SELECT r.id, r.name, r.description, r.is_private, r.default_branch,
        \\       r.created_at, r.updated_at, u.username as owner
        \\FROM repositories r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE r.is_private = false
        \\ORDER BY r.created_at DESC
        \\LIMIT $1 OFFSET $2
    else
        \\SELECT r.id, r.name, r.description, r.is_private, r.default_branch,
        \\       r.created_at, r.updated_at, u.username as owner
        \\FROM repositories r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE r.is_private = false
        \\ORDER BY r.updated_at DESC
        \\LIMIT $1 OFFSET $2
    ;

    var result = try conn.query(query, .{ safe_limit, safe_offset });
    defer result.deinit();

    // Get total count
    var count_result = try conn.query(
        \\SELECT COUNT(*)::int as count FROM repositories WHERE is_private = false
    , .{});
    defer count_result.deinit();

    var total: i32 = 0;
    if (try count_result.next()) |row| {
        total = row.get(i32, 0);
    }

    var writer = res.writer();
    try writer.writeAll("{\"repositories\":[");

    var first = true;
    while (try result.next()) |row| {
        if (!first) try writer.writeAll(",");
        first = false;

        const id: i64 = row.get(i64, 0);
        const name: []const u8 = row.get([]const u8, 1);
        const description: ?[]const u8 = row.get(?[]const u8, 2);
        const is_private: bool = row.get(bool, 3);
        const default_branch: ?[]const u8 = row.get(?[]const u8, 4);
        const created_at: []const u8 = row.get([]const u8, 5);
        const updated_at: []const u8 = row.get([]const u8, 6);
        const owner: []const u8 = row.get([]const u8, 7);

        try writer.print("{{\"id\":{d},\"name\":\"{s}\",\"owner\":\"{s}\",\"description\":", .{
            id,
            name,
            owner,
        });
        if (description) |d| {
            const escaped = try escapeJson(ctx.allocator, d);
            defer ctx.allocator.free(escaped);
            try writer.print("\"{s}\"", .{escaped});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"isPrivate\":{s},\"defaultBranch\":", .{
            if (is_private) "true" else "false",
        });
        if (default_branch) |b| {
            try writer.print("\"{s}\"", .{b});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"createdAt\":\"{s}\",\"updatedAt\":\"{s}\"}}", .{
            created_at,
            updated_at,
        });
    }

    try writer.print("],\"total\":{d},\"limit\":{d},\"offset\":{d}}}", .{
        total,
        safe_limit,
        safe_offset,
    });
}

/// GET /api/repos/search - Search public repositories
pub fn searchRepos(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const query_params = try req.query();

    const search_query = query_params.get("q") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing query parameter 'q'\"}");
        return;
    };

    if (search_query.len < 2) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Query must be at least 2 characters\"}");
        return;
    }

    const limit_str = query_params.get("limit") orelse "50";
    const offset_str = query_params.get("offset") orelse "0";

    const limit = std.fmt.parseInt(i32, limit_str, 10) catch 50;
    const offset = std.fmt.parseInt(i32, offset_str, 10) catch 0;

    const safe_limit: i32 = if (limit > 100) 100 else if (limit < 1) 1 else limit;
    const safe_offset: i32 = if (offset < 0) 0 else offset;

    var conn = try ctx.pool.acquire();
    defer conn.release();

    // Build search pattern
    var pattern_buf: [512]u8 = undefined;
    const pattern = try std.fmt.bufPrint(&pattern_buf, "%{s}%", .{search_query});

    var result = try conn.query(
        \\SELECT r.id, r.name, r.description, r.is_private, r.default_branch,
        \\       r.created_at, r.updated_at, u.username as owner
        \\FROM repositories r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE r.is_private = false
        \\  AND (r.name ILIKE $1 OR r.description ILIKE $1)
        \\ORDER BY r.updated_at DESC
        \\LIMIT $2 OFFSET $3
    , .{ pattern, safe_limit, safe_offset });
    defer result.deinit();

    var writer = res.writer();
    try writer.writeAll("{\"repositories\":[");

    var first = true;
    var count: i32 = 0;
    while (try result.next()) |row| {
        if (!first) try writer.writeAll(",");
        first = false;
        count += 1;

        const id: i64 = row.get(i64, 0);
        const name: []const u8 = row.get([]const u8, 1);
        const description: ?[]const u8 = row.get(?[]const u8, 2);
        const is_private: bool = row.get(bool, 3);
        const default_branch: ?[]const u8 = row.get(?[]const u8, 4);
        const created_at: []const u8 = row.get([]const u8, 5);
        const updated_at: []const u8 = row.get([]const u8, 6);
        const owner: []const u8 = row.get([]const u8, 7);

        try writer.print("{{\"id\":{d},\"name\":\"{s}\",\"owner\":\"{s}\",\"description\":", .{
            id,
            name,
            owner,
        });
        if (description) |d| {
            const escaped = try escapeJson(ctx.allocator, d);
            defer ctx.allocator.free(escaped);
            try writer.print("\"{s}\"", .{escaped});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"isPrivate\":{s},\"defaultBranch\":", .{
            if (is_private) "true" else "false",
        });
        if (default_branch) |b| {
            try writer.print("\"{s}\"", .{b});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"createdAt\":\"{s}\",\"updatedAt\":\"{s}\"}}", .{
            created_at,
            updated_at,
        });
    }

    try writer.print("],\"count\":{d}}}", .{count});
}

/// GET /api/repos/topics/popular - Get popular topics
pub fn getPopularTopics(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const query_params = try req.query();
    const limit_str = query_params.get("limit") orelse "10";
    const limit = std.fmt.parseInt(i32, limit_str, 10) catch 10;
    const safe_limit: i32 = if (limit > 50) 50 else if (limit < 1) 1 else limit;

    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT unnest(topics) as topic, COUNT(*)::int as count
        \\FROM repositories
        \\WHERE is_private = false AND topics IS NOT NULL AND array_length(topics, 1) > 0
        \\GROUP BY topic
        \\ORDER BY count DESC
        \\LIMIT $1
    , .{safe_limit});
    defer result.deinit();

    var writer = res.writer();
    try writer.writeAll("{\"topics\":[");

    var first = true;
    while (try result.next()) |row| {
        if (!first) try writer.writeAll(",");
        first = false;

        const topic: []const u8 = row.get([]const u8, 0);
        const count: i32 = row.get(i32, 1);

        try writer.print("{{\"topic\":\"{s}\",\"count\":{d}}}", .{ topic, count });
    }

    try writer.writeAll("]}");
}

/// GET /api/repos/topics/:topic - List repositories by topic
pub fn getReposByTopic(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const topic = req.param("topic") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing topic parameter\"}");
        return;
    };

    const query_params = try req.query();
    const limit_str = query_params.get("limit") orelse "50";
    const offset_str = query_params.get("offset") orelse "0";

    const limit = std.fmt.parseInt(i32, limit_str, 10) catch 50;
    const offset = std.fmt.parseInt(i32, offset_str, 10) catch 0;

    const safe_limit: i32 = if (limit > 100) 100 else if (limit < 1) 1 else limit;
    const safe_offset: i32 = if (offset < 0) 0 else offset;

    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT r.id, r.name, r.description, r.is_private, r.default_branch,
        \\       r.created_at, r.updated_at, u.username as owner
        \\FROM repositories r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE r.is_private = false AND $1 = ANY(r.topics)
        \\ORDER BY r.updated_at DESC
        \\LIMIT $2 OFFSET $3
    , .{ topic, safe_limit, safe_offset });
    defer result.deinit();

    var writer = res.writer();
    try writer.print("{{\"topic\":\"{s}\",\"repositories\":[", .{topic});

    var first = true;
    var count: i32 = 0;
    while (try result.next()) |row| {
        if (!first) try writer.writeAll(",");
        first = false;
        count += 1;

        const id: i64 = row.get(i64, 0);
        const name: []const u8 = row.get([]const u8, 1);
        const description: ?[]const u8 = row.get(?[]const u8, 2);
        const is_private: bool = row.get(bool, 3);
        const default_branch: ?[]const u8 = row.get(?[]const u8, 4);
        const created_at: []const u8 = row.get([]const u8, 5);
        const updated_at: []const u8 = row.get([]const u8, 6);
        const owner: []const u8 = row.get([]const u8, 7);

        try writer.print("{{\"id\":{d},\"name\":\"{s}\",\"owner\":\"{s}\",\"description\":", .{
            id,
            name,
            owner,
        });
        if (description) |d| {
            const escaped = try escapeJson(ctx.allocator, d);
            defer ctx.allocator.free(escaped);
            try writer.print("\"{s}\"", .{escaped});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"isPrivate\":{s},\"defaultBranch\":", .{
            if (is_private) "true" else "false",
        });
        if (default_branch) |b| {
            try writer.print("\"{s}\"", .{b});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"createdAt\":\"{s}\",\"updatedAt\":\"{s}\"}}", .{
            created_at,
            updated_at,
        });
    }

    try writer.print("],\"count\":{d}}}", .{count});
}

/// GET /api/:user/:repo/stats - Get repository stats
pub fn getRepositoryStats(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    var conn = try ctx.pool.acquire();
    defer conn.release();

    // Get issue count
    var issue_result = try conn.query(
        \\SELECT COUNT(*)::int as count FROM issues
        \\WHERE repository_id = $1 AND state = 'open'
    , .{repo.id});
    defer issue_result.deinit();

    var issue_count: i32 = 0;
    if (try issue_result.next()) |row| {
        issue_count = row.get(i32, 0);
    }

    // Get star count
    var star_result = try conn.query(
        \\SELECT COUNT(*)::int as count FROM stars WHERE repository_id = $1
    , .{repo.id});
    defer star_result.deinit();

    var star_count: i32 = 0;
    if (try star_result.next()) |row| {
        star_count = row.get(i32, 0);
    }

    // Get landing count
    var landing_result = try conn.query(
        \\SELECT COUNT(*)::int as count FROM landing_queue
        \\WHERE repository_id = $1 AND status NOT IN ('landed', 'cancelled')
    , .{repo.id});
    defer landing_result.deinit();

    var landing_count: i32 = 0;
    if (try landing_result.next()) |row| {
        landing_count = row.get(i32, 0);
    }

    // Get watcher count
    var watcher_result = try conn.query(
        \\SELECT COUNT(*)::int as count FROM watchers WHERE repository_id = $1
    , .{repo.id});
    defer watcher_result.deinit();

    var watcher_count: i32 = 0;
    if (try watcher_result.next()) |row| {
        watcher_count = row.get(i32, 0);
    }

    var writer = res.writer();
    try writer.print("{{\"issueCount\":{d},\"starCount\":{d},\"landingCount\":{d},\"watcherCount\":{d}}}", .{
        issue_count,
        star_count,
        landing_count,
        watcher_count,
    });
}

/// GET /api/:user/:repo/watchers - Get repository watchers
pub fn getWatchers(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT u.id, u.username, u.display_name, w.watch_level, w.created_at
        \\FROM watchers w
        \\JOIN users u ON w.user_id = u.id
        \\WHERE w.repository_id = $1
        \\ORDER BY w.created_at DESC
    , .{repo.id});
    defer result.deinit();

    var writer = res.writer();
    try writer.writeAll("{\"watchers\":[");

    var first = true;
    var count: i32 = 0;
    while (try result.next()) |row| {
        if (!first) try writer.writeAll(",");
        first = false;
        count += 1;

        const id: i64 = row.get(i64, 0);
        const watcher_username: []const u8 = row.get([]const u8, 1);
        const display_name: ?[]const u8 = row.get(?[]const u8, 2);
        const watch_level: []const u8 = row.get([]const u8, 3);
        const created_at: []const u8 = row.get([]const u8, 4);

        try writer.print("{{\"id\":{d},\"username\":\"{s}\",\"displayName\":", .{
            id,
            watcher_username,
        });
        if (display_name) |d| {
            try writer.print("\"{s}\"", .{d});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"watchLevel\":\"{s}\",\"createdAt\":\"{s}\"}}", .{
            watch_level,
            created_at,
        });
    }

    try writer.print("],\"total\":{d}}}", .{count});
}
