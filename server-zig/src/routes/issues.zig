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
