const std = @import("std");
const httpz = @import("httpz");
const Context = @import("main.zig").Context;
const middleware = @import("middleware/mod.zig");
const rate_limit = @import("middleware/rate_limit.zig");
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
const git_routes = @import("routes/git.zig");
const internal_routes = @import("routes/internal.zig");
const agent_routes = @import("routes/agent.zig");
const operations = @import("routes/operations.zig");
const metrics_routes = @import("routes/metrics.zig");

const log = std.log.scoped(.routes);

/// Helper function to validate CSRF token
/// Returns true if valid or not required, false if invalid (and sets error response)
fn validateCsrf(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
    const config = middleware.csrf_default;

    // Skip if CSRF is disabled
    if (!config.enabled) {
        return true;
    }

    // Safe methods don't need CSRF protection
    if (req.method != .POST and req.method != .PUT and req.method != .PATCH and req.method != .DELETE) {
        return true;
    }

    // Skip CSRF for Bearer token authentication if configured
    if (config.skip_bearer_auth) {
        const auth_header = req.headers.get("authorization");
        if (auth_header != null and std.mem.startsWith(u8, auth_header.?, "Bearer ")) {
            return true;
        }
    }

    // Get CSRF token from request header
    const token = req.headers.get("X-CSRF-Token") orelse {
        res.status = 403;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"CSRF token missing\"}");
        return false;
    };

    // Validate token against session
    if (!ctx.csrf_store.validateToken(token, ctx.session_key)) {
        res.status = 403;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Invalid CSRF token\"}");
        return false;
    }

    return true;
}

/// Helper function to apply input validation + auth + CSRF middleware to a handler
/// Use this wrapper for all POST/PUT/PATCH/DELETE routes that require auth
/// Input validation runs FIRST to reject malicious input before auth checks
fn withAuthAndCsrf(
    comptime handler: fn (*Context, *httpz.Request, *httpz.Response) anyerror!void,
) fn (*Context, *httpz.Request, *httpz.Response) anyerror!void {
    return struct {
        fn wrapped(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
            // Apply input validation FIRST (before auth)
            // This rejects null bytes and control characters with 400
            const validation_handler = middleware.validationMiddleware(middleware.validation_default);
            if (!try validation_handler(ctx, req, res)) {
                return; // Validation middleware already set 400 response
            }

            // Apply auth middleware (loads user if present)
            if (!try middleware.authMiddleware(ctx, req, res)) {
                return; // Auth middleware already set error response
            }

            // Check if user is actually authenticated
            // authMiddleware just loads user, it doesn't require auth
            if (ctx.user == null) {
                res.status = 401;
                res.content_type = .JSON;
                try res.writer().writeAll("{\"error\":\"Authentication required\"}");
                return;
            }

            // Apply CSRF validation (only for authenticated requests)
            if (!try validateCsrf(ctx, req, res)) {
                return; // CSRF validation already set error response
            }

            // Call the actual handler
            return handler(ctx, req, res);
        }
    }.wrapped;
}

/// Helper function to apply auth middleware to a handler
/// Use this wrapper for routes that require auth but not CSRF (e.g., GET routes)
fn withAuth(
    comptime handler: fn (*Context, *httpz.Request, *httpz.Response) anyerror!void,
) fn (*Context, *httpz.Request, *httpz.Response) anyerror!void {
    return struct {
        fn wrapped(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
            // Apply auth middleware
            if (!try middleware.authMiddleware(ctx, req, res)) {
                return; // Auth middleware already set error response
            }

            // Call the actual handler
            return handler(ctx, req, res);
        }
    }.wrapped;
}

/// Helper function to apply rate limiting to a handler
/// Use this wrapper for auth endpoints to prevent brute force attacks
fn withRateLimit(
    comptime config: rate_limit.RateLimitConfig,
    comptime key_prefix: []const u8,
    comptime handler: fn (*Context, *httpz.Request, *httpz.Response) anyerror!void,
) fn (*Context, *httpz.Request, *httpz.Response) anyerror!void {
    return struct {
        fn wrapped(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
            // Apply rate limiting middleware
            const rate_limit_handler = rate_limit.rateLimitMiddleware(config, key_prefix);
            if (!try rate_limit_handler(ctx, req, res)) {
                return; // Rate limit middleware already set 429 response
            }

            // Call the actual handler
            return handler(ctx, req, res);
        }
    }.wrapped;
}

pub fn configure(server: *httpz.Server(*Context)) !void {
    var router = try server.router(.{});

    // Health check
    router.get("/health", healthCheck, .{});

    // Prometheus metrics endpoint
    router.get("/metrics", metrics_routes.getMetrics, .{});

    // API routes - auth (delegating to auth_routes module for consistency)
    // Note: Login/register don't require auth (user isn't authenticated yet)
    // but DO require rate limiting to prevent brute force attacks
    router.get("/api/auth/siwe/nonce", auth_routes.getNonce, .{});
    router.post("/api/auth/siwe/verify", withRateLimit(rate_limit.presets.login, "login", auth_routes.verify), .{});
    router.post("/api/auth/siwe/register", withRateLimit(rate_limit.presets.register, "register", auth_routes.register), .{});
    router.post("/api/auth/logout", withAuthAndCsrf(auth_routes.logout), .{});
    router.get("/api/auth/me", auth_routes.me, .{});
    router.post("/api/auth/refresh", withAuthAndCsrf(auth_routes.refresh), .{});

    // API routes - users
    router.get("/api/users/search", users.search, .{});
    router.get("/api/users/:username", users.getProfile, .{});
    router.patch("/api/users/me", withAuthAndCsrf(users.updateProfile), .{});

    // API routes - SSH keys (CSRF protected)
    router.get("/api/ssh-keys", ssh_keys.list, .{});
    router.post("/api/ssh-keys", withAuthAndCsrf(ssh_keys.create), .{});
    router.delete("/api/ssh-keys/:id", withAuthAndCsrf(ssh_keys.delete), .{});

    // API routes - access tokens (CSRF protected)
    router.get("/api/user/tokens", tokens.list, .{});
    router.post("/api/user/tokens", withAuthAndCsrf(tokens.create), .{});
    router.delete("/api/user/tokens/:id", withAuthAndCsrf(tokens.delete), .{});

    // API routes - repositories (CSRF protected)
    router.post("/api/repos", withAuthAndCsrf(repo_routes.createRepository), .{});

    // API routes - repositories (stars, watches, topics) - CSRF protected
    router.get("/api/:user/:repo/stargazers", repo_routes.getStargazers, .{});
    router.post("/api/:user/:repo/star", withAuthAndCsrf(repo_routes.starRepository), .{});
    router.delete("/api/:user/:repo/star", withAuthAndCsrf(repo_routes.unstarRepository), .{});
    router.post("/api/:user/:repo/watch", withAuthAndCsrf(repo_routes.watchRepository), .{});
    router.delete("/api/:user/:repo/watch", withAuthAndCsrf(repo_routes.unwatchRepository), .{});
    router.get("/api/:user/:repo/topics", repo_routes.getTopics, .{});
    router.put("/api/:user/:repo/topics", withAuthAndCsrf(repo_routes.updateTopics), .{});

    // API routes - bookmarks (jj branches) - CSRF protected
    router.get("/api/:user/:repo/bookmarks", repo_routes.listBookmarks, .{});
    router.get("/api/:user/:repo/bookmarks/:name", repo_routes.getBookmark, .{});
    router.post("/api/:user/:repo/bookmarks", withAuthAndCsrf(repo_routes.createBookmark), .{});
    router.put("/api/:user/:repo/bookmarks/:name", withAuthAndCsrf(repo_routes.updateBookmark), .{});
    router.post("/api/:user/:repo/bookmarks/:name/set-default", withAuthAndCsrf(repo_routes.setDefaultBookmark), .{});
    router.delete("/api/:user/:repo/bookmarks/:name", withAuthAndCsrf(repo_routes.deleteBookmark), .{});

    // API routes - git content with SHA-based caching
    router.get("/api/:owner/:repo/refs/:ref", git_routes.resolveRef, .{});
    router.get("/api/:owner/:repo/tree/:sha", git_routes.getTreeBySha, .{});
    router.get("/api/:owner/:repo/tree/:sha/*", git_routes.getTreeBySha, .{});
    router.get("/api/:owner/:repo/blob/:sha/*", git_routes.getBlobBySha, .{});

    // Internal API routes - for runner pods (not exposed externally)
    router.post("/internal/runners/register", internal_routes.registerRunner, .{});
    router.post("/internal/runners/:pod_name/heartbeat", internal_routes.runnerHeartbeat, .{});
    router.post("/internal/tasks/:task_id/stream", internal_routes.streamTaskEvent, .{});
    router.post("/internal/tasks/:task_id/complete", internal_routes.completeTask, .{});

    // API routes - changes (jj)
    router.get("/api/:user/:repo/changes", repo_routes.listChanges, .{});
    router.get("/api/:user/:repo/changes/:changeId", repo_routes.getChange, .{});
    router.get("/api/:user/:repo/changes/:changeId/diff", repo_routes.getChangeDiff, .{});
    router.get("/api/:user/:repo/changes/:changeId/files", changes.getFilesAtChange, .{});
    router.get("/api/:user/:repo/changes/:changeId/file/*", changes.getFileAtChange, .{});
    router.get("/api/:user/:repo/changes/:fromChangeId/compare/:toChangeId", changes.compareChanges, .{});
    router.get("/api/:user/:repo/changes/:changeId/conflicts", changes.getConflicts, .{});
    router.post("/api/:user/:repo/changes/:changeId/conflicts/:filePath/resolve", withAuthAndCsrf(changes.resolveConflict), .{});

    // API routes - operations (jj operation log) - CSRF protected
    router.get("/api/:user/:repo/operations", operations.listOperations, .{});
    router.get("/api/:user/:repo/operations/:operationId", operations.getOperation, .{});
    router.post("/api/:user/:repo/operations/undo", withAuthAndCsrf(operations.undoOperation), .{});
    router.post("/api/:user/:repo/operations/:operationId/restore", withAuthAndCsrf(operations.restoreOperation), .{});

    // API routes - issues - CSRF protected
    router.get("/api/:user/:repo/issues", issues.listIssues, .{});
    router.get("/api/:user/:repo/issues/counts", issues.getIssueCounts, .{});
    router.get("/api/:user/:repo/issues/:number", issues.getIssue, .{});
    router.get("/api/:user/:repo/issues/:number/history", issues.getIssueHistory, .{});
    router.post("/api/:user/:repo/issues", withAuthAndCsrf(issues.createIssue), .{});
    router.patch("/api/:user/:repo/issues/:number", withAuthAndCsrf(issues.updateIssue), .{});
    router.post("/api/:user/:repo/issues/:number/close", withAuthAndCsrf(issues.closeIssue), .{});
    router.post("/api/:user/:repo/issues/:number/reopen", withAuthAndCsrf(issues.reopenIssue), .{});
    router.delete("/api/:user/:repo/issues/:number", withAuthAndCsrf(issues.deleteIssue), .{});

    // API routes - issue comments - CSRF protected
    router.get("/api/:user/:repo/issues/:number/comments", issues.getComments, .{});
    router.post("/api/:user/:repo/issues/:number/comments", withAuthAndCsrf(issues.addComment), .{});
    router.patch("/api/:user/:repo/issues/:number/comments/:commentId", withAuthAndCsrf(issues.updateComment), .{});
    router.delete("/api/:user/:repo/issues/:number/comments/:commentId", withAuthAndCsrf(issues.deleteComment), .{});

    // API routes - labels - CSRF protected
    router.get("/api/:user/:repo/labels", issues.getLabels, .{});
    router.post("/api/:user/:repo/labels", withAuthAndCsrf(issues.createLabel), .{});
    router.patch("/api/:user/:repo/labels/:name", withAuthAndCsrf(issues.updateLabel), .{});
    router.delete("/api/:user/:repo/labels/:name", withAuthAndCsrf(issues.deleteLabel), .{});
    router.post("/api/:user/:repo/issues/:number/labels", withAuthAndCsrf(issues.addLabelsToIssue), .{});
    router.delete("/api/:user/:repo/issues/:number/labels/:labelId", withAuthAndCsrf(issues.removeLabelFromIssue), .{});

    // API routes - pin/unpin issues - CSRF protected
    router.post("/api/:user/:repo/issues/:number/pin", withAuthAndCsrf(issues.pinIssue), .{});
    router.post("/api/:user/:repo/issues/:number/unpin", withAuthAndCsrf(issues.unpinIssue), .{});

    // API routes - reactions - CSRF protected
    router.post("/api/:user/:repo/issues/:number/reactions", withAuthAndCsrf(issues.addReactionToIssue), .{});
    router.delete("/api/:user/:repo/issues/:number/reactions/:emoji", withAuthAndCsrf(issues.removeReactionFromIssue), .{});

    // API routes - comment reactions - CSRF protected
    router.get("/api/:user/:repo/issues/:number/comments/:commentId/reactions", issues.getCommentReactions, .{});
    router.post("/api/:user/:repo/issues/:number/comments/:commentId/reactions", withAuthAndCsrf(issues.addCommentReaction), .{});
    router.delete("/api/:user/:repo/issues/:number/comments/:commentId/reactions/:emoji", withAuthAndCsrf(issues.removeCommentReaction), .{});

    // API routes - assignees - CSRF protected
    router.post("/api/:user/:repo/issues/:number/assignees", withAuthAndCsrf(issues.addAssigneeToIssue), .{});
    router.delete("/api/:user/:repo/issues/:number/assignees/:userId", withAuthAndCsrf(issues.removeAssigneeFromIssue), .{});

    // API routes - dependencies - CSRF protected
    router.post("/api/:user/:repo/issues/:number/dependencies", withAuthAndCsrf(issues.addDependencyToIssue), .{});
    router.delete("/api/:user/:repo/issues/:number/dependencies/:blockedNumber", withAuthAndCsrf(issues.removeDependencyFromIssue), .{});

    // API routes - due dates - CSRF protected
    router.get("/api/:user/:repo/issues/:number/due-date", issues.getDueDate, .{});
    router.put("/api/:user/:repo/issues/:number/due-date", withAuthAndCsrf(issues.setDueDate), .{});
    router.delete("/api/:user/:repo/issues/:number/due-date", withAuthAndCsrf(issues.removeDueDate), .{});

    // API routes - milestones - CSRF protected
    router.get("/api/:user/:repo/milestones", milestones.listMilestones, .{});
    router.get("/api/:user/:repo/milestones/:id", milestones.getMilestone, .{});
    router.post("/api/:user/:repo/milestones", withAuthAndCsrf(milestones.createMilestone), .{});
    router.patch("/api/:user/:repo/milestones/:id", withAuthAndCsrf(milestones.updateMilestone), .{});
    router.delete("/api/:user/:repo/milestones/:id", withAuthAndCsrf(milestones.deleteMilestone), .{});

    // API routes - issue milestone assignment - CSRF protected
    router.put("/api/:user/:repo/issues/:number/milestone", withAuthAndCsrf(milestones.assignMilestoneToIssue), .{});
    router.delete("/api/:user/:repo/issues/:number/milestone", withAuthAndCsrf(milestones.removeMilestoneFromIssue), .{});

    // API routes - landing queue (jj-native PR replacement) - CSRF protected
    router.get("/api/:user/:repo/landing", landing_queue.listLandingRequests, .{});
    router.get("/api/:user/:repo/landing/:id", landing_queue.getLandingRequest, .{});
    router.post("/api/:user/:repo/landing", withAuthAndCsrf(landing_queue.createLandingRequest), .{});
    router.post("/api/:user/:repo/landing/:id/check", withAuthAndCsrf(landing_queue.checkLandingStatus), .{});
    router.post("/api/:user/:repo/landing/:id/land", withAuthAndCsrf(landing_queue.executeLanding), .{});
    router.delete("/api/:user/:repo/landing/:id", withAuthAndCsrf(landing_queue.cancelLandingRequest), .{});
    router.post("/api/:user/:repo/landing/:id/reviews", withAuthAndCsrf(landing_queue.addReview), .{});
    router.get("/api/:user/:repo/landing/:id/files", landing_queue.getLandingFiles, .{});
    router.get("/api/:user/:repo/landing/:id/comments", landing_queue.getLineComments, .{});
    router.post("/api/:user/:repo/landing/:id/comments", withAuthAndCsrf(landing_queue.createLineComment), .{});
    router.patch("/api/:user/:repo/landing/:id/comments/:commentId", withAuthAndCsrf(landing_queue.updateLineComment), .{});
    router.delete("/api/:user/:repo/landing/:id/comments/:commentId", withAuthAndCsrf(landing_queue.deleteLineComment), .{});

    // PTY routes - CSRF protected
    router.post("/pty", withAuthAndCsrf(pty_routes.create), .{});
    router.get("/pty", pty_routes.list, .{});
    router.get("/pty/:id", pty_routes.get, .{});
    router.delete("/pty/:id", withAuthAndCsrf(pty_routes.close), .{});
    router.post("/pty/:id/resize", withAuthAndCsrf(pty_routes.resize), .{});
    router.get("/pty/:id/ws", pty_routes.websocket, .{});

    // API routes - sessions (agent sessions) - CSRF protected
    router.get("/api/sessions", sessions.listSessions, .{});
    router.post("/api/sessions", withAuthAndCsrf(sessions.createSession), .{});
    router.get("/api/sessions/:sessionId", sessions.getSession, .{});
    router.patch("/api/sessions/:sessionId", withAuthAndCsrf(sessions.updateSession), .{});
    router.delete("/api/sessions/:sessionId", withAuthAndCsrf(sessions.deleteSession), .{});
    router.post("/api/sessions/:sessionId/abort", withAuthAndCsrf(sessions.abortSession), .{});
    router.get("/api/sessions/:sessionId/diff", sessions.getSessionDiff, .{});
    router.get("/api/sessions/:sessionId/changes", sessions.getSessionChanges, .{});
    router.get("/api/sessions/:sessionId/changes/:changeId", sessions.getSpecificChange, .{});
    router.get("/api/sessions/:sessionId/changes/:fromChangeId/compare/:toChangeId", sessions.compareChanges, .{});
    router.get("/api/sessions/:sessionId/changes/:changeId/files", sessions.getFilesAtChange, .{});
    router.get("/api/sessions/:sessionId/changes/:changeId/file/*", sessions.getFileAtChange, .{});
    router.get("/api/sessions/:sessionId/conflicts", sessions.getSessionConflicts, .{});
    router.get("/api/sessions/:sessionId/operations", sessions.getSessionOperations, .{});
    router.post("/api/sessions/:sessionId/operations/undo", withAuthAndCsrf(sessions.undoLastOperation), .{});
    router.post("/api/sessions/:sessionId/operations/:operationId/restore", withAuthAndCsrf(sessions.restoreOperation), .{});
    router.post("/api/sessions/:sessionId/fork", withAuthAndCsrf(sessions.forkSession), .{});
    router.post("/api/sessions/:sessionId/revert", withAuthAndCsrf(sessions.revertSession), .{});
    router.post("/api/sessions/:sessionId/unrevert", withAuthAndCsrf(sessions.unrevertSession), .{});
    router.post("/api/sessions/:sessionId/undo", withAuthAndCsrf(sessions.undoTurns), .{});

    // API routes - messages (agent messages and parts) - CSRF protected
    router.get("/api/sessions/:sessionId/messages", messages.listMessages, .{});
    router.post("/api/sessions/:sessionId/messages", withAuthAndCsrf(messages.createMessage), .{});
    router.get("/api/sessions/:sessionId/messages/:messageId", messages.getMessage, .{});
    router.patch("/api/sessions/:sessionId/messages/:messageId", withAuthAndCsrf(messages.updateMessage), .{});
    router.delete("/api/sessions/:sessionId/messages/:messageId", withAuthAndCsrf(messages.deleteMessage), .{});
    router.get("/api/sessions/:sessionId/messages/:messageId/parts", messages.listParts, .{});
    router.post("/api/sessions/:sessionId/messages/:messageId/parts", withAuthAndCsrf(messages.createPart), .{});
    router.patch("/api/sessions/:sessionId/messages/:messageId/parts/:partId", withAuthAndCsrf(messages.updatePart), .{});
    router.delete("/api/sessions/:sessionId/messages/:messageId/parts/:partId", withAuthAndCsrf(messages.deletePart), .{});

    // API routes - AI agent - CSRF protected
    router.post("/api/sessions/:sessionId/run", withAuthAndCsrf(agent_routes.runAgentHandler), .{});
    router.get("/api/sessions/:sessionId/ws", sessions.websocket, .{});  // WebSocket streaming
    router.get("/api/agents", agent_routes.listAgentsHandler, .{});
    router.get("/api/agents/:name", agent_routes.getAgentHandler, .{});
    router.get("/api/tools", agent_routes.listToolsHandler, .{});

    // API routes - workflows - CSRF protected
    router.get("/api/:user/:repo/workflows/runs", workflows.listRuns, .{});
    router.get("/api/:user/:repo/workflows/runs/:runId", workflows.getRun, .{});
    router.post("/api/:user/:repo/workflows/runs", withAuthAndCsrf(workflows.createRun), .{});
    router.patch("/api/:user/:repo/workflows/runs/:runId", withAuthAndCsrf(workflows.updateRun), .{});
    router.post("/api/:user/:repo/workflows/runs/:runId/cancel", withAuthAndCsrf(workflows.cancelRun), .{});
    router.get("/api/:user/:repo/workflows/runs/:runId/jobs", workflows.getJobs, .{});
    router.get("/api/:user/:repo/workflows/runs/:runId/logs", workflows.getLogs, .{});

    // API routes - runners - CSRF protected
    router.post("/api/runners/register", withAuthAndCsrf(runners.register), .{});
    router.post("/api/runners/heartbeat", withAuthAndCsrf(runners.heartbeat), .{});
    router.get("/api/runners/tasks/fetch", runners.fetchTask, .{});
    router.post("/api/runners/tasks/:taskId/status", withAuthAndCsrf(runners.updateTaskStatus), .{});
    router.post("/api/runners/tasks/:taskId/logs", withAuthAndCsrf(runners.appendLogs), .{});

    // API routes - repository watcher - CSRF protected
    router.get("/api/watcher/status", watcher_routes.getWatcherStatus, .{});
    router.get("/api/watcher/repos", watcher_routes.listWatchedRepos, .{});
    router.post("/api/watcher/watch/:user/:repo", withAuthAndCsrf(watcher_routes.watchRepository), .{});
    router.delete("/api/watcher/watch/:user/:repo", withAuthAndCsrf(watcher_routes.unwatchRepository), .{});
    router.post("/api/watcher/sync/:user/:repo", withAuthAndCsrf(watcher_routes.syncRepository), .{});

    log.info("Routes configured", .{});
}

fn healthCheck(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.content_type = .JSON;
    try res.writer().writeAll("{\"status\":\"ok\"}");
}

// NOTE: Auth handlers (getNonce, verify, register, logout, me) have been moved to
// routes/auth.zig to consolidate authentication logic in one place.
// This module now delegates to auth_routes for all authentication endpoints.
