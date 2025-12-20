const std = @import("std");
const httpz = @import("httpz");
const Context = @import("main.zig").Context;
const pty_routes = @import("routes/pty.zig");
const auth_routes = @import("routes/auth.zig");
const ssh_keys = @import("routes/ssh_keys.zig");
const tokens = @import("routes/tokens.zig");
const users = @import("routes/users.zig");
const sessions = @import("routes/sessions.zig");
const messages = @import("routes/messages.zig");
const repo_routes = @import("routes/repositories.zig");
const workflows = @import("routes/workflows.zig");
const runners = @import("routes/runners.zig");
const issues = @import("routes/issues.zig");
const milestones = @import("routes/milestones.zig");
const landing_queue = @import("routes/landing_queue.zig");
const watcher_routes = @import("routes/watcher.zig");
const changes = @import("routes/changes.zig");
const agent_routes = @import("routes/agent.zig");
const operations = @import("routes/operations.zig");

const log = std.log.scoped(.routes);

pub fn configure(server: *httpz.Server(*Context)) !void {
    var router = try server.router(.{});

    // Health check
    router.get("/health", healthCheck, .{});

    // ElectricSQL shape proxy
    router.get("/shape", shapeProxy, .{});

    // API routes - auth (delegating to auth_routes module for consistency)
    router.get("/api/auth/siwe/nonce", auth_routes.getNonce, .{});
    router.post("/api/auth/siwe/verify", auth_routes.verify, .{});
    router.post("/api/auth/siwe/register", auth_routes.register, .{});
    router.post("/api/auth/logout", auth_routes.logout, .{});
    router.get("/api/auth/me", auth_routes.me, .{});
    router.post("/api/auth/refresh", auth_routes.refresh, .{});

    // API routes - users
    router.get("/api/users/search", users.search, .{});
    router.get("/api/users/:username", users.getProfile, .{});
    router.patch("/api/users/me", users.updateProfile, .{});

    // API routes - SSH keys
    router.get("/api/ssh-keys", ssh_keys.list, .{});
    router.post("/api/ssh-keys", ssh_keys.create, .{});
    router.delete("/api/ssh-keys/:id", ssh_keys.delete, .{});

    // API routes - access tokens
    router.get("/api/user/tokens", tokens.list, .{});
    router.post("/api/user/tokens", tokens.create, .{});
    router.delete("/api/user/tokens/:id", tokens.delete, .{});

    // API routes - repositories (stars, watches, topics)
    router.get("/api/:user/:repo/stargazers", repo_routes.getStargazers, .{});
    router.post("/api/:user/:repo/star", repo_routes.starRepository, .{});
    router.delete("/api/:user/:repo/star", repo_routes.unstarRepository, .{});
    router.post("/api/:user/:repo/watch", repo_routes.watchRepository, .{});
    router.delete("/api/:user/:repo/watch", repo_routes.unwatchRepository, .{});
    router.get("/api/:user/:repo/topics", repo_routes.getTopics, .{});
    router.put("/api/:user/:repo/topics", repo_routes.updateTopics, .{});

    // API routes - bookmarks (jj branches)
    router.get("/api/:user/:repo/bookmarks", repo_routes.listBookmarks, .{});
    router.get("/api/:user/:repo/bookmarks/:name", repo_routes.getBookmark, .{});
    router.post("/api/:user/:repo/bookmarks", repo_routes.createBookmark, .{});
    router.put("/api/:user/:repo/bookmarks/:name", repo_routes.updateBookmark, .{});
    router.post("/api/:user/:repo/bookmarks/:name/set-default", repo_routes.setDefaultBookmark, .{});
    router.delete("/api/:user/:repo/bookmarks/:name", repo_routes.deleteBookmark, .{});

    // API routes - changes (jj)
    router.get("/api/:user/:repo/changes", repo_routes.listChanges, .{});
    router.get("/api/:user/:repo/changes/:changeId", repo_routes.getChange, .{});
    router.get("/api/:user/:repo/changes/:changeId/diff", repo_routes.getChangeDiff, .{});
    router.get("/api/:user/:repo/changes/:changeId/files", changes.getFilesAtChange, .{});
    router.get("/api/:user/:repo/changes/:changeId/file/*", changes.getFileAtChange, .{});
    router.get("/api/:user/:repo/changes/:fromChangeId/compare/:toChangeId", changes.compareChanges, .{});
    router.get("/api/:user/:repo/changes/:changeId/conflicts", changes.getConflicts, .{});
    router.post("/api/:user/:repo/changes/:changeId/conflicts/:filePath/resolve", changes.resolveConflict, .{});

    // API routes - operations (jj operation log)
    router.get("/api/:user/:repo/operations", operations.listOperations, .{});
    router.get("/api/:user/:repo/operations/:operationId", operations.getOperation, .{});
    router.post("/api/:user/:repo/operations/undo", operations.undoOperation, .{});
    router.post("/api/:user/:repo/operations/:operationId/restore", operations.restoreOperation, .{});

    // API routes - issues
    router.get("/api/:user/:repo/issues", issues.listIssues, .{});
    router.get("/api/:user/:repo/issues/counts", issues.getIssueCounts, .{});
    router.get("/api/:user/:repo/issues/:number", issues.getIssue, .{});
    router.get("/api/:user/:repo/issues/:number/history", issues.getIssueHistory, .{});
    router.post("/api/:user/:repo/issues", issues.createIssue, .{});
    router.patch("/api/:user/:repo/issues/:number", issues.updateIssue, .{});
    router.post("/api/:user/:repo/issues/:number/close", issues.closeIssue, .{});
    router.post("/api/:user/:repo/issues/:number/reopen", issues.reopenIssue, .{});
    router.delete("/api/:user/:repo/issues/:number", issues.deleteIssue, .{});

    // API routes - issue comments
    router.get("/api/:user/:repo/issues/:number/comments", issues.getComments, .{});
    router.post("/api/:user/:repo/issues/:number/comments", issues.addComment, .{});
    router.patch("/api/:user/:repo/issues/:number/comments/:commentId", issues.updateComment, .{});
    router.delete("/api/:user/:repo/issues/:number/comments/:commentId", issues.deleteComment, .{});

    // API routes - labels
    router.get("/api/:user/:repo/labels", issues.getLabels, .{});
    router.post("/api/:user/:repo/labels", issues.createLabel, .{});
    router.patch("/api/:user/:repo/labels/:name", issues.updateLabel, .{});
    router.delete("/api/:user/:repo/labels/:name", issues.deleteLabel, .{});
    router.post("/api/:user/:repo/issues/:number/labels", issues.addLabelsToIssue, .{});
    router.delete("/api/:user/:repo/issues/:number/labels/:labelId", issues.removeLabelFromIssue, .{});

    // API routes - pin/unpin issues
    router.post("/api/:user/:repo/issues/:number/pin", issues.pinIssue, .{});
    router.post("/api/:user/:repo/issues/:number/unpin", issues.unpinIssue, .{});

    // API routes - reactions
    router.post("/api/:user/:repo/issues/:number/reactions", issues.addReactionToIssue, .{});
    router.delete("/api/:user/:repo/issues/:number/reactions/:emoji", issues.removeReactionFromIssue, .{});

    // API routes - comment reactions
    router.get("/api/:user/:repo/issues/:number/comments/:commentId/reactions", issues.getCommentReactions, .{});
    router.post("/api/:user/:repo/issues/:number/comments/:commentId/reactions", issues.addCommentReaction, .{});
    router.delete("/api/:user/:repo/issues/:number/comments/:commentId/reactions/:emoji", issues.removeCommentReaction, .{});

    // API routes - assignees
    router.post("/api/:user/:repo/issues/:number/assignees", issues.addAssigneeToIssue, .{});
    router.delete("/api/:user/:repo/issues/:number/assignees/:userId", issues.removeAssigneeFromIssue, .{});

    // API routes - dependencies
    router.post("/api/:user/:repo/issues/:number/dependencies", issues.addDependencyToIssue, .{});
    router.delete("/api/:user/:repo/issues/:number/dependencies/:blockedNumber", issues.removeDependencyFromIssue, .{});

    // API routes - due dates
    router.get("/api/:user/:repo/issues/:number/due-date", issues.getDueDate, .{});
    router.put("/api/:user/:repo/issues/:number/due-date", issues.setDueDate, .{});
    router.delete("/api/:user/:repo/issues/:number/due-date", issues.removeDueDate, .{});

    // API routes - milestones
    router.get("/api/:user/:repo/milestones", milestones.listMilestones, .{});
    router.get("/api/:user/:repo/milestones/:id", milestones.getMilestone, .{});
    router.post("/api/:user/:repo/milestones", milestones.createMilestone, .{});
    router.patch("/api/:user/:repo/milestones/:id", milestones.updateMilestone, .{});
    router.delete("/api/:user/:repo/milestones/:id", milestones.deleteMilestone, .{});

    // API routes - issue milestone assignment
    router.put("/api/:user/:repo/issues/:number/milestone", milestones.assignMilestoneToIssue, .{});
    router.delete("/api/:user/:repo/issues/:number/milestone", milestones.removeMilestoneFromIssue, .{});

    // API routes - landing queue (jj-native PR replacement)
    router.get("/api/:user/:repo/landing", landing_queue.listLandingRequests, .{});
    router.get("/api/:user/:repo/landing/:id", landing_queue.getLandingRequest, .{});
    router.post("/api/:user/:repo/landing", landing_queue.createLandingRequest, .{});
    router.post("/api/:user/:repo/landing/:id/check", landing_queue.checkLandingStatus, .{});
    router.post("/api/:user/:repo/landing/:id/land", landing_queue.executeLanding, .{});
    router.delete("/api/:user/:repo/landing/:id", landing_queue.cancelLandingRequest, .{});
    router.post("/api/:user/:repo/landing/:id/reviews", landing_queue.addReview, .{});
    router.get("/api/:user/:repo/landing/:id/files", landing_queue.getLandingFiles, .{});
    router.get("/api/:user/:repo/landing/:id/comments", landing_queue.getLineComments, .{});
    router.post("/api/:user/:repo/landing/:id/comments", landing_queue.createLineComment, .{});
    router.patch("/api/:user/:repo/landing/:id/comments/:commentId", landing_queue.updateLineComment, .{});
    router.delete("/api/:user/:repo/landing/:id/comments/:commentId", landing_queue.deleteLineComment, .{});

    // PTY routes
    router.post("/pty", pty_routes.create, .{});
    router.get("/pty", pty_routes.list, .{});
    router.get("/pty/:id", pty_routes.get, .{});
    router.delete("/pty/:id", pty_routes.close, .{});
    router.post("/pty/:id/resize", pty_routes.resize, .{});
    router.get("/pty/:id/ws", pty_routes.websocket, .{});

    // API routes - sessions (agent sessions)
    router.get("/api/sessions", sessions.listSessions, .{});
    router.post("/api/sessions", sessions.createSession, .{});
    router.get("/api/sessions/:sessionId", sessions.getSession, .{});
    router.patch("/api/sessions/:sessionId", sessions.updateSession, .{});
    router.delete("/api/sessions/:sessionId", sessions.deleteSession, .{});
    router.post("/api/sessions/:sessionId/abort", sessions.abortSession, .{});
    router.get("/api/sessions/:sessionId/diff", sessions.getSessionDiff, .{});
    router.get("/api/sessions/:sessionId/changes", sessions.getSessionChanges, .{});
    router.get("/api/sessions/:sessionId/changes/:changeId", sessions.getSpecificChange, .{});
    router.get("/api/sessions/:sessionId/changes/:fromChangeId/compare/:toChangeId", sessions.compareChanges, .{});
    router.get("/api/sessions/:sessionId/changes/:changeId/files", sessions.getFilesAtChange, .{});
    router.get("/api/sessions/:sessionId/changes/:changeId/file/*", sessions.getFileAtChange, .{});
    router.get("/api/sessions/:sessionId/conflicts", sessions.getSessionConflicts, .{});
    router.get("/api/sessions/:sessionId/operations", sessions.getSessionOperations, .{});
    router.post("/api/sessions/:sessionId/operations/undo", sessions.undoLastOperation, .{});
    router.post("/api/sessions/:sessionId/operations/:operationId/restore", sessions.restoreOperation, .{});
    router.post("/api/sessions/:sessionId/fork", sessions.forkSession, .{});
    router.post("/api/sessions/:sessionId/revert", sessions.revertSession, .{});
    router.post("/api/sessions/:sessionId/unrevert", sessions.unrevertSession, .{});
    router.post("/api/sessions/:sessionId/undo", sessions.undoTurns, .{});

    // API routes - messages (agent messages and parts)
    router.get("/api/sessions/:sessionId/messages", messages.listMessages, .{});
    router.post("/api/sessions/:sessionId/messages", messages.createMessage, .{});
    router.get("/api/sessions/:sessionId/messages/:messageId", messages.getMessage, .{});
    router.patch("/api/sessions/:sessionId/messages/:messageId", messages.updateMessage, .{});
    router.delete("/api/sessions/:sessionId/messages/:messageId", messages.deleteMessage, .{});
    router.get("/api/sessions/:sessionId/messages/:messageId/parts", messages.listParts, .{});
    router.post("/api/sessions/:sessionId/messages/:messageId/parts", messages.createPart, .{});
    router.patch("/api/sessions/:sessionId/messages/:messageId/parts/:partId", messages.updatePart, .{});
    router.delete("/api/sessions/:sessionId/messages/:messageId/parts/:partId", messages.deletePart, .{});

    // API routes - AI agent
    router.post("/api/sessions/:sessionId/run", agent_routes.runAgentHandler, .{});
    router.get("/api/agents", agent_routes.listAgentsHandler, .{});
    router.get("/api/agents/:name", agent_routes.getAgentHandler, .{});
    router.get("/api/tools", agent_routes.listToolsHandler, .{});

    // API routes - workflows
    router.get("/api/:user/:repo/workflows/runs", workflows.listRuns, .{});
    router.get("/api/:user/:repo/workflows/runs/:runId", workflows.getRun, .{});
    router.post("/api/:user/:repo/workflows/runs", workflows.createRun, .{});
    router.patch("/api/:user/:repo/workflows/runs/:runId", workflows.updateRun, .{});
    router.post("/api/:user/:repo/workflows/runs/:runId/cancel", workflows.cancelRun, .{});
    router.get("/api/:user/:repo/workflows/runs/:runId/jobs", workflows.getJobs, .{});
    router.get("/api/:user/:repo/workflows/runs/:runId/logs", workflows.getLogs, .{});

    // API routes - runners
    router.post("/api/runners/register", runners.register, .{});
    router.post("/api/runners/heartbeat", runners.heartbeat, .{});
    router.get("/api/runners/tasks/fetch", runners.fetchTask, .{});
    router.post("/api/runners/tasks/:taskId/status", runners.updateTaskStatus, .{});
    router.post("/api/runners/tasks/:taskId/logs", runners.appendLogs, .{});

    // API routes - repository watcher
    router.get("/api/watcher/status", watcher_routes.getWatcherStatus, .{});
    router.get("/api/watcher/repos", watcher_routes.listWatchedRepos, .{});
    router.post("/api/watcher/watch/:user/:repo", watcher_routes.watchRepository, .{});
    router.delete("/api/watcher/watch/:user/:repo", watcher_routes.unwatchRepository, .{});
    router.post("/api/watcher/sync/:user/:repo", watcher_routes.syncRepository, .{});

    log.info("Routes configured", .{});
}

fn healthCheck(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.content_type = .JSON;
    try res.writer().writeAll("{\"status\":\"ok\"}");
}

fn shapeProxy(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = ctx.allocator;

    // Build Electric URL with /v1/shape path
    var electric_url = std.ArrayList(u8).initCapacity(allocator, ctx.config.electric_url.len + 256) catch |err| {
        log.err("Failed to allocate URL buffer: {}", .{err});
        res.status = 500;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    };
    defer electric_url.deinit(allocator);

    try electric_url.appendSlice(allocator, ctx.config.electric_url);
    try electric_url.appendSlice(allocator, "/v1/shape");

    // Forward all query parameters from the request
    // Query parameters include: table, offset, live, handle, where, etc.
    const query_string = req.url.query;
    if (query_string.len > 0) {
        try electric_url.append(allocator, '?');
        try electric_url.appendSlice(allocator, query_string);
    }

    const url = try electric_url.toOwnedSlice(allocator);
    defer allocator.free(url);

    log.debug("Proxying shape request to: {s}", .{url});

    // Parse the Electric URL
    const uri = std.Uri.parse(url) catch |err| {
        log.err("Failed to parse Electric URL: {}", .{err});
        res.status = 500;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Invalid Electric URL configuration\"}");
        return;
    };

    // Create HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Create a buffer to store the response body
    var body_buffer = std.ArrayList(u8){};
    defer body_buffer.deinit(allocator);

    // Create a writer for the response
    var response_writer = body_buffer.writer(allocator);

    // Prepare fetch options
    const fetch_options = std.http.Client.FetchOptions{
        .location = .{ .uri = uri },
        .method = .GET,
        .response_writer = @ptrCast(&response_writer),
    };

    // Make the request
    const fetch_result = client.fetch(fetch_options) catch |err| {
        log.err("Failed to fetch from Electric: {}", .{err});
        res.status = 503;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Electric service unavailable\"}");
        return;
    };

    // Set response status from Electric
    res.status = @intFromEnum(fetch_result.status);

    // Set content-type to JSON (Electric shape responses are JSON)
    res.content_type = .JSON;

    // Note: Zig 0.15.1 fetch() doesn't provide access to response headers
    // In production, you may want to use a lower-level HTTP client to forward headers
    // like electric-offset, electric-handle, etc. For now, we just proxy the body.

    // Write the response body
    try res.writer().writeAll(body_buffer.items);
    log.debug("Shape proxy completed: status={d}, body_size={d}", .{ res.status, body_buffer.items.len });
}

// NOTE: Auth handlers (getNonce, verify, register, logout, me) have been moved to
// routes/auth.zig to consolidate authentication logic in one place.
// This module now delegates to auth_routes for all authentication endpoints.
