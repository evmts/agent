//! Issue routes
//!
//! Handles issue tracking for repositories:
//! 1. GET /:user/:repo/issues - List issues
//! 2. GET /:user/:repo/issues/:number - Get issue
//! 3. POST /:user/:repo/issues - Create issue
//! 4. PATCH /:user/:repo/issues/:number - Update issue
//! 5. POST /:user/:repo/issues/:number/close - Close issue
//! 6. POST /:user/:repo/issues/:number/reopen - Reopen issue
//! 7. GET /:user/:repo/issues/:number/comments - Get comments
//! 8. POST /:user/:repo/issues/:number/comments - Add comment
//! 9. PATCH /:user/:repo/issues/:number/comments/:commentId - Update comment
//! 10. DELETE /:user/:repo/issues/:number/comments/:commentId - Delete comment
//! 11. GET /:user/:repo/labels - Get labels
//! 12. POST /:user/:repo/labels - Create label
//! 13. POST /:user/:repo/issues/:number/labels - Add labels to issue
//! 14. DELETE /:user/:repo/issues/:number/labels/:labelId - Remove label from issue
//! 15. POST /:user/:repo/issues/:number/pin - Pin issue
//! 16. POST /:user/:repo/issues/:number/unpin - Unpin issue
//! 17. POST /:user/:repo/issues/:number/reactions - Add reaction to issue
//! 18. DELETE /:user/:repo/issues/:number/reactions/:emoji - Remove reaction from issue
//! 19. GET /:user/:repo/issues/:number/comments/:commentId/reactions - Get comment reactions
//! 20. POST /:user/:repo/issues/:number/comments/:commentId/reactions - Add comment reaction
//! 21. DELETE /:user/:repo/issues/:number/comments/:commentId/reactions/:emoji - Remove comment reaction
//! 22. POST /:user/:repo/issues/:number/assignees - Add assignee to issue
//! 23. DELETE /:user/:repo/issues/:number/assignees/:userId - Remove assignee from issue
//! 24. POST /:user/:repo/issues/:number/dependencies - Add dependency (blocker)
//! 25. DELETE /:user/:repo/issues/:number/dependencies/:blockedNumber - Remove dependency

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db_issues = @import("../lib/db_issues.zig");
const db = @import("../lib/db.zig");

const log = std.log.scoped(.issue_routes);

// ============================================================================
// Issue Routes
// ============================================================================

/// GET /:user/:repo/issues
/// List issues for a repository
pub fn listIssues(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    const state = req.url.query.get("state") orelse "open";

    // List issues
    const issues = db_issues.listIssues(ctx.pool, allocator, repo.?.id, state) catch |err| {
        log.err("Failed to list issues: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };
    defer allocator.free(issues);

    // Get counts
    const counts = db_issues.getIssueCounts(ctx.pool, repo.?.id) catch |err| {
        log.err("Failed to get issue counts: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"issues\":[");
    for (issues, 0..) |issue, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":{d},"number":{d},"title":"{s}","body":{s},"state":"{s}","createdAt":{d},"updatedAt":{d}}}
        , .{
            issue.id,
            issue.issue_number,
            issue.title,
            if (issue.body) |b| try std.fmt.allocPrint(allocator, "\"{s}\"", .{b}) else "null",
            issue.state,
            issue.created_at,
            issue.updated_at,
        });
    }
    try writer.print("],\"counts\":{{\"open\":{d},\"closed\":{d}}},\"total\":{d}}}", .{ counts.open, counts.closed, issues.len });
}

/// GET /:user/:repo/issues/:number
/// Get a single issue with comments
pub fn getIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Get comments
    const comments = db_issues.getComments(ctx.pool, allocator, issue.?.id) catch |err| {
        log.err("Failed to get comments: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };
    defer allocator.free(comments);

    // Build JSON response
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"number":{d},"title":"{s}","body":{s},"state":"{s}","createdAt":{d},"updatedAt":{d},"comments":[
    , .{
        issue.?.id,
        issue.?.issue_number,
        issue.?.title,
        if (issue.?.body) |b| try std.fmt.allocPrint(allocator, "\"{s}\"", .{b}) else "null",
        issue.?.state,
        issue.?.created_at,
        issue.?.updated_at,
    });

    for (comments, 0..) |comment, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":{d},"body":"{s}","authorId":{d},"createdAt":{d},"edited":{s}}}
        , .{
            comment.id,
            comment.body,
            comment.author_id,
            comment.created_at,
            if (comment.edited) "true" else "false",
        });
    }
    try writer.writeAll("]}}");
}

/// POST /:user/:repo/issues
/// Create a new issue
pub fn createIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        title: []const u8,
        body: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.title.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Title is required\"}");
        return;
    }

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Create issue
    const issue = db_issues.createIssue(ctx.pool, repo.?.id, ctx.user.?.id, v.title, v.body) catch |err| {
        log.err("Failed to create issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create issue\"}");
        return;
    };

    // Return created issue
    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"number":{d},"title":"{s}","body":{s},"state":"{s}","createdAt":{d},"updatedAt":{d}}}
    , .{
        issue.id,
        issue.issue_number,
        issue.title,
        if (issue.body) |b| try std.fmt.allocPrint(allocator, "\"{s}\"", .{b}) else "null",
        issue.state,
        issue.created_at,
        issue.updated_at,
    });
}

/// PATCH /:user/:repo/issues/:number
/// Update an issue
pub fn updateIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        title: ?[]const u8 = null,
        body: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Update issue
    const issue = db_issues.updateIssue(ctx.pool, repo.?.id, issue_number, v.title, v.body) catch |err| {
        log.err("Failed to update issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update issue\"}");
        return;
    };

    // Return updated issue
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"number":{d},"title":"{s}","body":{s},"state":"{s}","createdAt":{d},"updatedAt":{d}}}
    , .{
        issue.id,
        issue.issue_number,
        issue.title,
        if (issue.body) |b| try std.fmt.allocPrint(allocator, "\"{s}\"", .{b}) else "null",
        issue.state,
        issue.created_at,
        issue.updated_at,
    });
}

/// POST /:user/:repo/issues/:number/close
/// Close an issue
pub fn closeIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Close issue
    db_issues.closeIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to close issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to close issue\"}");
        return;
    };

    // Get updated issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue) |iss| {
        var writer = res.writer();
        try writer.print(
            \\{{"id":{d},"number":{d},"title":"{s}","body":{s},"state":"{s}","createdAt":{d},"updatedAt":{d}}}
        , .{
            iss.id,
            iss.issue_number,
            iss.title,
            if (iss.body) |b| try std.fmt.allocPrint(allocator, "\"{s}\"", .{b}) else "null",
            iss.state,
            iss.created_at,
            iss.updated_at,
        });
    } else {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
    }
}

/// POST /:user/:repo/issues/:number/reopen
/// Reopen an issue
pub fn reopenIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Reopen issue
    db_issues.reopenIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to reopen issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to reopen issue\"}");
        return;
    };

    // Get updated issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue) |iss| {
        var writer = res.writer();
        try writer.print(
            \\{{"id":{d},"number":{d},"title":"{s}","body":{s},"state":"{s}","createdAt":{d},"updatedAt":{d}}}
        , .{
            iss.id,
            iss.issue_number,
            iss.title,
            if (iss.body) |b| try std.fmt.allocPrint(allocator, "\"{s}\"", .{b}) else "null",
            iss.state,
            iss.created_at,
            iss.updated_at,
        });
    } else {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
    }
}

// ============================================================================
// Comment Routes
// ============================================================================

/// GET /:user/:repo/issues/:number/comments
/// Get comments for an issue
pub fn getComments(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Get comments
    const comments = db_issues.getComments(ctx.pool, allocator, issue.?.id) catch |err| {
        log.err("Failed to get comments: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };
    defer allocator.free(comments);

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"comments\":[");
    for (comments, 0..) |comment, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":{d},"body":"{s}","authorId":{d},"createdAt":{d},"edited":{s}}}
        , .{
            comment.id,
            comment.body,
            comment.author_id,
            comment.created_at,
            if (comment.edited) "true" else "false",
        });
    }
    try writer.writeAll("]}");
}

/// POST /:user/:repo/issues/:number/comments
/// Add a comment to an issue
pub fn addComment(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        body: []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.body.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Comment body is required\"}");
        return;
    }

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Add comment
    const comment = db_issues.addComment(ctx.pool, issue.?.id, ctx.user.?.id, v.body) catch |err| {
        log.err("Failed to add comment: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to add comment\"}");
        return;
    };

    // Return created comment
    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"body":"{s}","authorId":{d},"createdAt":{d},"edited":{s}}}
    , .{
        comment.id,
        comment.body,
        comment.author_id,
        comment.created_at,
        if (comment.edited) "true" else "false",
    });
}

/// PATCH /:user/:repo/issues/:number/comments/:commentId
/// Update a comment
pub fn updateComment(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const comment_id_str = req.param("commentId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing comment ID parameter\"}");
        return;
    };

    const comment_id = std.fmt.parseInt(i64, comment_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid comment ID\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        body: []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.body.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Comment body is required\"}");
        return;
    }

    // Update comment
    const comment = db_issues.updateComment(ctx.pool, comment_id, v.body) catch |err| {
        log.err("Failed to update comment: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update comment\"}");
        return;
    };

    // Return updated comment
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"body":"{s}","authorId":{d},"createdAt":{d},"edited":{s}}}
    , .{
        comment.id,
        comment.body,
        comment.author_id,
        comment.created_at,
        if (comment.edited) "true" else "false",
    });
}

/// DELETE /:user/:repo/issues/:number/comments/:commentId
/// Delete a comment
pub fn deleteComment(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const comment_id_str = req.param("commentId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing comment ID parameter\"}");
        return;
    };

    const comment_id = std.fmt.parseInt(i64, comment_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid comment ID\"}");
        return;
    };

    // Delete comment
    db_issues.deleteComment(ctx.pool, comment_id) catch |err| {
        log.err("Failed to delete comment: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to delete comment\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

// ============================================================================
// Label Routes
// ============================================================================

/// GET /:user/:repo/labels
/// Get available labels for a repository
pub fn getLabels(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get labels
    const labels = db_issues.getLabels(ctx.pool, allocator, repo.?.id) catch |err| {
        log.err("Failed to get labels: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };
    defer allocator.free(labels);

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"labels\":[");
    for (labels, 0..) |label, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":{d},"name":"{s}","color":"{s}","description":{s}}}
        , .{
            label.id,
            label.name,
            label.color,
            if (label.description) |d| try std.fmt.allocPrint(allocator, "\"{s}\"", .{d}) else "null",
        });
    }
    try writer.writeAll("]}");
}

/// POST /:user/:repo/labels
/// Create a new label
pub fn createLabel(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        name: []const u8,
        color: []const u8,
        description: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.name.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Label name is required\"}");
        return;
    }

    if (v.color.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Label color is required\"}");
        return;
    }

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Create label
    const label = db_issues.createLabel(ctx.pool, repo.?.id, v.name, v.color, v.description) catch |err| {
        log.err("Failed to create label: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create label\"}");
        return;
    };

    // Return created label
    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"name":"{s}","color":"{s}","description":{s}}}
    , .{
        label.id,
        label.name,
        label.color,
        if (label.description) |d| try std.fmt.allocPrint(allocator, "\"{s}\"", .{d}) else "null",
    });
}

/// POST /:user/:repo/issues/:number/labels
/// Add labels to an issue
pub fn addLabelsToIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        labels: [][]const u8,
    }, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Add each label
    for (v.labels) |label_name| {
        const label = db_issues.getLabelByName(ctx.pool, repo.?.id, label_name) catch |err| {
            log.err("Failed to get label: {}", .{err});
            continue;
        };

        if (label) |lbl| {
            db_issues.addLabelToIssue(ctx.pool, issue.?.id, lbl.id) catch |err| {
                log.err("Failed to add label to issue: {}", .{err});
                continue;
            };
        }
    }

    try res.writer().writeAll("{\"success\":true}");
}

/// DELETE /:user/:repo/issues/:number/labels/:labelId
/// Remove a label from an issue
pub fn removeLabelFromIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    const label_id_str = req.param("labelId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing label ID parameter\"}");
        return;
    };

    const label_id = std.fmt.parseInt(i64, label_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid label ID\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Remove label
    db_issues.removeLabelFromIssue(ctx.pool, issue.?.id, label_id) catch |err| {
        log.err("Failed to remove label from issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to remove label\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

// ============================================================================
// Pin/Unpin Routes
// ============================================================================

/// POST /:user/:repo/issues/:number/pin
/// Pin an issue
pub fn pinIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Pin the issue
    db_issues.pinIssue(ctx.pool, repo.?.id, issue.?.id, ctx.user.?.id) catch |err| {
        if (err == error.MaxPinnedIssuesReached) {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Maximum of 3 pinned issues reached\"}");
            return;
        }
        log.err("Failed to pin issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to pin issue\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

/// POST /:user/:repo/issues/:number/unpin
/// Unpin an issue
pub fn unpinIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Unpin the issue
    db_issues.unpinIssue(ctx.pool, issue.?.id) catch |err| {
        log.err("Failed to unpin issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to unpin issue\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

// ============================================================================
// Reaction Routes
// ============================================================================

/// POST /:user/:repo/issues/:number/reactions
/// Add a reaction to an issue
pub fn addReactionToIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        emoji: []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.emoji.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Emoji is required\"}");
        return;
    }

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Add reaction (use issue_number as target_id for compatibility with TS)
    const reaction = db_issues.addReaction(ctx.pool, ctx.user.?.id, "issue", issue_number, v.emoji) catch |err| {
        log.err("Failed to add reaction: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to add reaction\"}");
        return;
    };

    if (reaction) |r| {
        res.status = 201;
        var writer = res.writer();
        try writer.print(
            \\{{"id":{d},"userId":{d},"emoji":"{s}","createdAt":{d}}}
        , .{ r.id, r.user_id, r.emoji, r.created_at });
    } else {
        try res.writer().writeAll("{\"message\":\"Reaction already exists\"}");
    }
}

/// DELETE /:user/:repo/issues/:number/reactions/:emoji
/// Remove a reaction from an issue
pub fn removeReactionFromIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    const emoji = req.param("emoji") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing emoji parameter\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue to verify it exists
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Remove reaction (use issue_number as target_id for compatibility with TS)
    db_issues.removeReaction(ctx.pool, ctx.user.?.id, "issue", issue_number, emoji) catch |err| {
        log.err("Failed to remove reaction: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to remove reaction\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

// ============================================================================
// Comment Reaction Routes
// ============================================================================

/// GET /:user/:repo/issues/:number/comments/:commentId/reactions
/// List reactions for a comment
pub fn getCommentReactions(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    const comment_id_str = req.param("commentId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing comment ID parameter\"}");
        return;
    };

    const comment_id = std.fmt.parseInt(i64, comment_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid comment ID\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue to verify it exists
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Get reactions for the comment
    const reactions = db_issues.getReactions(ctx.pool, allocator, "comment", comment_id) catch |err| {
        log.err("Failed to get comment reactions: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };
    defer allocator.free(reactions);

    // Group by emoji (like TypeScript implementation)
    var grouped = std.StringHashMap(struct {
        emoji: []const u8,
        count: usize,
        users: std.ArrayList(struct { id: i64, username: []const u8 }),
    }).init(allocator);
    defer {
        var it = grouped.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.users.deinit();
        }
        grouped.deinit();
    }

    for (reactions) |r| {
        if (grouped.getPtr(r.emoji)) |group| {
            group.count += 1;
            try group.users.append(.{ .id = r.user_id, .username = r.username });
        } else {
            var users = std.ArrayList(struct { id: i64, username: []const u8 }).init(allocator);
            try users.append(.{ .id = r.user_id, .username = r.username });
            try grouped.put(r.emoji, .{
                .emoji = r.emoji,
                .count = 1,
                .users = users,
            });
        }
    }

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"reactions\":[");

    var first = true;
    var it = grouped.iterator();
    while (it.next()) |entry| {
        if (!first) try writer.writeAll(",");
        first = false;

        try writer.print("{{\"emoji\":\"{s}\",\"count\":{d},\"users\":[", .{ entry.value_ptr.emoji, entry.value_ptr.count });

        for (entry.value_ptr.users.items, 0..) |user, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{{\"id\":{d},\"username\":\"{s}\"}}", .{ user.id, user.username });
        }

        try writer.writeAll("]}");
    }

    try writer.writeAll("]}");
}

/// POST /:user/:repo/issues/:number/comments/:commentId/reactions
/// Add a reaction to a comment
pub fn addCommentReaction(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    const comment_id_str = req.param("commentId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing comment ID parameter\"}");
        return;
    };

    const comment_id = std.fmt.parseInt(i64, comment_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid comment ID\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        emoji: []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.emoji.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Emoji is required\"}");
        return;
    }

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue to verify it exists
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Add reaction to comment
    const reaction = db_issues.addReaction(ctx.pool, ctx.user.?.id, "comment", comment_id, v.emoji) catch |err| {
        log.err("Failed to add comment reaction: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to add reaction\"}");
        return;
    };

    if (reaction) |r| {
        res.status = 201;
        var writer = res.writer();
        try writer.print(
            \\{{"id":{d},"userId":{d},"emoji":"{s}","createdAt":{d}}}
        , .{ r.id, r.user_id, r.emoji, r.created_at });
    } else {
        try res.writer().writeAll("{\"message\":\"Reaction already exists\"}");
    }
}

/// DELETE /:user/:repo/issues/:number/comments/:commentId/reactions/:emoji
/// Remove a reaction from a comment
pub fn removeCommentReaction(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    const comment_id_str = req.param("commentId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing comment ID parameter\"}");
        return;
    };

    const comment_id = std.fmt.parseInt(i64, comment_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid comment ID\"}");
        return;
    };

    const emoji = req.param("emoji") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing emoji parameter\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue to verify it exists
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Remove reaction from comment
    db_issues.removeReaction(ctx.pool, ctx.user.?.id, "comment", comment_id, emoji) catch |err| {
        log.err("Failed to remove comment reaction: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to remove reaction\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

// ============================================================================
// Assignee Routes
// ============================================================================

/// POST /:user/:repo/issues/:number/assignees
/// Add an assignee to an issue
pub fn addAssigneeToIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        user_id: i64,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Add assignee
    db_issues.addAssignee(ctx.pool, issue.?.id, v.user_id) catch |err| {
        log.err("Failed to add assignee: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to add assignee\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

/// DELETE /:user/:repo/issues/:number/assignees/:userId
/// Remove an assignee from an issue
pub fn removeAssigneeFromIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    const user_id_str = req.param("userId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user ID parameter\"}");
        return;
    };

    const user_id = std.fmt.parseInt(i64, user_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid user ID\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get issue
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Remove assignee
    db_issues.removeAssignee(ctx.pool, issue.?.id, user_id) catch |err| {
        log.err("Failed to remove assignee: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to remove assignee\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

// ============================================================================
// Dependency Routes
// ============================================================================

/// POST /:user/:repo/issues/:number/dependencies
/// Add a dependency (this issue blocks another)
pub fn addDependencyToIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        blocks: i64,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get blocker issue (this issue)
    const blocker_issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get blocker issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (blocker_issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Get blocked issue
    const blocked_issue = db_issues.getIssue(ctx.pool, repo.?.id, v.blocks) catch |err| {
        log.err("Failed to get blocked issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (blocked_issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Blocked issue not found\"}");
        return;
    }

    // Add dependency
    db_issues.addDependency(ctx.pool, repo.?.id, blocker_issue.?.id, blocked_issue.?.id) catch |err| {
        log.err("Failed to add dependency: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to add dependency\"}");
        return;
    };

    res.status = 201;
    try res.writer().writeAll("{\"success\":true}");
}

/// DELETE /:user/:repo/issues/:number/dependencies/:blockedNumber
/// Remove a dependency (this issue no longer blocks another)
pub fn removeDependencyFromIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    const blocked_number_str = req.param("blockedNumber") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing blocked issue number parameter\"}");
        return;
    };

    const blocked_number = std.fmt.parseInt(i64, blocked_number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid blocked issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get blocker issue
    const blocker_issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get blocker issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (blocker_issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Get blocked issue
    const blocked_issue = db_issues.getIssue(ctx.pool, repo.?.id, blocked_number) catch |err| {
        log.err("Failed to get blocked issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (blocked_issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Blocked issue not found\"}");
        return;
    }

    // Remove dependency
    db_issues.removeDependency(ctx.pool, blocker_issue.?.id, blocked_issue.?.id) catch |err| {
        log.err("Failed to remove dependency: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to remove dependency\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}
// Additional issue route handlers

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db_issues = @import("../lib/db_issues.zig");

const log = std.log.scoped(.issue_routes_new);

/// DELETE /:user/:repo/issues/:number
/// Delete an issue
pub fn deleteIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Check if issue exists
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Delete issue
    db_issues.deleteIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to delete issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to delete issue\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

/// PATCH /:user/:repo/labels/:name
/// Update a label
pub fn updateLabel(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const old_name = req.param("name") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing label name parameter\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        name: []const u8,
        color: []const u8,
        description: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.name.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Label name is required\"}");
        return;
    }

    if (v.color.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Label color is required\"}");
        return;
    }

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Update label
    const label = db_issues.updateLabel(ctx.pool, repo.?.id, old_name, v.name, v.color, v.description) catch |err| {
        log.err("Failed to update label: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update label\"}");
        return;
    };

    // Return updated label
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"name":"{s}","color":"{s}","description":{s}}}
    , .{
        label.id,
        label.name,
        label.color,
        if (label.description) |d| try std.fmt.allocPrint(allocator, "\"{s}\"", .{d}) else "null",
    });
}

/// DELETE /:user/:repo/labels/:name
/// Delete a label
pub fn deleteLabel(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const label_name = req.param("name") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing label name parameter\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Check if label exists
    const label = db_issues.getLabelByName(ctx.pool, repo.?.id, label_name) catch |err| {
        log.err("Failed to get label: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (label == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Label not found\"}");
        return;
    }

    // Delete label
    db_issues.deleteLabel(ctx.pool, repo.?.id, label_name) catch |err| {
        log.err("Failed to delete label: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to delete label\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

/// GET /:user/:repo/issues/:number/history
/// Get issue history/timeline
pub fn getIssueHistory(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Check if issue exists
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Get history
    const history = db_issues.getIssueHistory(ctx.pool, allocator, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue history: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };
    defer allocator.free(history);

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"history\":[");
    for (history, 0..) |event, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":{d},"actorId":{s},"eventType":"{s}","metadata":{s},"createdAt":{d}}}
        , .{
            event.id,
            if (event.actor_id) |aid| try std.fmt.allocPrint(allocator, "{d}", .{aid}) else "null",
            event.event_type,
            event.metadata,
            event.created_at,
        });
    }
    try writer.writeAll("]}");
}

/// GET /:user/:repo/issues/counts
/// Get issue counts (open/closed)
pub fn getIssueCounts(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get counts
    const counts = db_issues.getIssueCounts(ctx.pool, repo.?.id) catch |err| {
        log.err("Failed to get issue counts: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    // Return counts
    var writer = res.writer();
    try writer.print("{{\"open\":{d},\"closed\":{d}}}", .{ counts.open, counts.closed });
}
// Due date route handlers

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db_issues = @import("../lib/db_issues.zig");

const log = std.log.scoped(.issue_routes_due_date);

/// GET /:user/:repo/issues/:number/due-date
/// Get issue due date
pub fn getDueDate(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Check if issue exists
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Get due date
    const due_date = db_issues.getDueDate(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get due date: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    // Return due date
    var writer = res.writer();
    if (due_date) |dd| {
        try writer.print("{{\"dueDate\":{d}}}", .{dd});
    } else {
        try writer.writeAll("{\"dueDate\":null}");
    }
}

/// PUT /:user/:repo/issues/:number/due-date
/// Set issue due date
pub fn setDueDate(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        due_date: i64,
    }, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Check if issue exists
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Set due date
    db_issues.setDueDate(ctx.pool, repo.?.id, issue_number, v.due_date) catch |err| {
        log.err("Failed to set due date: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to set due date\"}");
        return;
    };

    // Return updated issue
    const updated_issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get updated issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (updated_issue) |iss| {
        var writer = res.writer();
        try writer.print(
            \\{{"id":{d},"number":{d},"title":"{s}","body":{s},"state":"{s}","createdAt":{d},"updatedAt":{d}}}
        , .{
            iss.id,
            iss.issue_number,
            iss.title,
            if (iss.body) |b| try std.fmt.allocPrint(allocator, "\"{s}\"", .{b}) else "null",
            iss.state,
            iss.created_at,
            iss.updated_at,
        });
    }
}

/// DELETE /:user/:repo/issues/:number/due-date
/// Remove issue due date
pub fn removeDueDate(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    }

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const number_str = req.param("number") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue number parameter\"}");
        return;
    };

    const issue_number = std.fmt.parseInt(i64, number_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid issue number\"}");
        return;
    };

    // Get repository
    const repo = db_issues.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (repo == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Check if issue exists
    const issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (issue == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Issue not found\"}");
        return;
    }

    // Remove due date
    db_issues.removeDueDate(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to remove due date: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to remove due date\"}");
        return;
    };

    // Return updated issue
    const updated_issue = db_issues.getIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to get updated issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (updated_issue) |iss| {
        var writer = res.writer();
        try writer.print(
            \\{{"id":{d},"number":{d},"title":"{s}","body":{s},"state":"{s}","createdAt":{d},"updatedAt":{d}}}
        , .{
            iss.id,
            iss.issue_number,
            iss.title,
            if (iss.body) |b| try std.fmt.allocPrint(allocator, "\"{s}\"", .{b}) else "null",
            iss.state,
            iss.created_at,
            iss.updated_at,
        });
    }
}
