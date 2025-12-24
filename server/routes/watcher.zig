//! Repository Watcher Control Routes
//!
//! Provides API endpoints to control the repository watcher service

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");

const log = std.log.scoped(.watcher_routes);

/// POST /api/watcher/watch/:user/:repo - Add a repository to watch list
pub fn watchRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require admin authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    if (!user.is_admin) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Admin access required\"}");
        return;
    }

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

    // Get repository from database
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

    // Access watcher from context (would be added to Context struct)
    if (ctx.repo_watcher) |watcher| {
        watcher.watchRepo(username, reponame, repo.id) catch |err| {
            log.err("Failed to watch repository: {}", .{err});
            res.status = 500;
            try res.writer().writeAll("{\"error\":\"Failed to add repository to watch list\"}");
            return;
        };
    } else {
        res.status = 503;
        try res.writer().writeAll("{\"error\":\"Watcher service not available\"}");
        return;
    }

    var writer = res.writer();
    try writer.print("{{\"message\":\"Repository added to watch list\",\"repo\":\"{s}/{s}\"}}", .{ username, reponame });
}

/// DELETE /api/watcher/watch/:user/:repo - Remove a repository from watch list
pub fn unwatchRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require admin authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    if (!user.is_admin) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Admin access required\"}");
        return;
    }

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

    // Access watcher from context
    if (ctx.repo_watcher) |watcher| {
        watcher.unwatchRepo(username, reponame) catch |err| {
            log.err("Failed to unwatch repository: {}", .{err});
            res.status = 500;
            try res.writer().writeAll("{\"error\":\"Failed to remove repository from watch list\"}");
            return;
        };
    } else {
        res.status = 503;
        try res.writer().writeAll("{\"error\":\"Watcher service not available\"}");
        return;
    }

    var writer = res.writer();
    try writer.print("{{\"message\":\"Repository removed from watch list\",\"repo\":\"{s}/{s}\"}}", .{ username, reponame });
}

/// POST /api/watcher/sync/:user/:repo - Manually trigger sync for a repository
pub fn syncRepository(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication (repo owner or admin)
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

    // Get repository from database
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

    // Check permission (owner or admin)
    if (user.id != repo.user_id and !user.is_admin) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Forbidden: You don't have permission to sync this repository\"}");
        return;
    }

    // Trigger manual sync via watcher
    if (ctx.repo_watcher) |watcher| {
        // Find the watched repo and trigger sync
        const key = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ username, reponame });
        defer ctx.allocator.free(key);

        watcher.mutex.lock();
        defer watcher.mutex.unlock();

        if (watcher.watched_repos.get(key)) |watched_repo| {
            // Trigger immediate sync by setting debounce timer to 0
            watched_repo.debounce_timer = 0;

            var writer = res.writer();
            try writer.print("{{\"message\":\"Sync triggered for repository\",\"repo\":\"{s}/{s}\"}}", .{ username, reponame });
        } else {
            res.status = 404;
            try res.writer().writeAll("{\"error\":\"Repository not in watch list\"}");
        }
    } else {
        res.status = 503;
        try res.writer().writeAll("{\"error\":\"Watcher service not available\"}");
    }
}

/// GET /api/watcher/status - Get watcher service status
pub fn getWatcherStatus(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require admin authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    if (!user.is_admin) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Admin access required\"}");
        return;
    }

    if (ctx.repo_watcher) |watcher| {
        const running = watcher.running.load(.acquire);
        const watch_count = watcher.watched_repos.count();

        var writer = res.writer();
        try writer.print("{{\"running\":{s},\"watchedRepos\":{d}}}", .{
            if (running) "true" else "false",
            watch_count,
        });
    } else {
        try res.writer().writeAll("{\"running\":false,\"watchedRepos\":0}");
    }
}

/// GET /api/watcher/repos - List all watched repositories
pub fn listWatchedRepos(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require admin authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    if (!user.is_admin) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Admin access required\"}");
        return;
    }

    if (ctx.repo_watcher) |watcher| {
        watcher.mutex.lock();
        defer watcher.mutex.unlock();

        var writer = res.writer();
        try writer.writeAll("{\"repos\":[");

        var it = watcher.watched_repos.valueIterator();
        var first = true;
        while (it.next()) |repo| {
            if (!first) try writer.writeAll(",");
            first = false;

            try writer.print("{{\"user\":\"{s}\",\"repo\":\"{s}\",\"repoId\":{d}}}", .{
                repo.*.user,
                repo.*.repo,
                repo.*.repo_id,
            });
        }

        try writer.writeAll("]}");
    } else {
        try res.writer().writeAll("{\"repos\":[]}");
    }
}
