//! Protected Bookmarks routes
//!
//! Handles bookmark protection rule management for repositories:
//! 1. GET /api/:user/:repo/settings/protection - List protection rules
//! 2. POST /api/:user/:repo/settings/protection - Create protection rule
//! 3. DELETE /api/:user/:repo/settings/protection/:id - Delete protection rule

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");

const log = std.log.scoped(.protected_bookmarks_routes);

// ============================================================================
// Protection Rules Routes
// ============================================================================

/// GET /api/:user/:repo/settings/protection
/// List protection rules for a repository
pub fn listProtectionRules(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
    const repo = db.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
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

    // List protection rules
    const rules = db.listProtectedBookmarks(ctx.pool, allocator, repo.?.id) catch |err| {
        log.err("Failed to list protection rules: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };
    defer allocator.free(rules);

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"rules\":[");
    for (rules, 0..) |rule, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":{d},"pattern":"{s}","requireReview":{s},"requiredApprovals":{d},"createdAt":{d}}}
        , .{
            rule.id,
            rule.pattern,
            if (rule.require_review) "true" else "false",
            rule.required_approvals,
            rule.created_at,
        });
    }
    try writer.writeAll("]}");
}

/// POST /api/:user/:repo/settings/protection
/// Create a new protection rule
pub fn createProtectionRule(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        pattern: []const u8,
        require_review: ?bool = null,
        required_approvals: ?i32 = null,
    }, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.pattern.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Pattern is required\"}");
        return;
    }

    // Validate pattern (basic validation - no special SQL injection characters)
    for (v.pattern) |c| {
        if (c == 0 or c == '\'' or c == '"' or c == ';') {
            res.status = 400;
            try res.writer().writeAll("{\"error\":\"Invalid characters in pattern\"}");
            return;
        }
    }

    // Get repository
    const repo = db.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
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

    // TODO: Check if user has permission to modify repository settings
    // For now, allow any authenticated user (should check repo ownership)

    const require_review = v.require_review orelse true;
    const required_approvals = v.required_approvals orelse 1;

    // Create protection rule
    const rule = db.createProtectedBookmark(
        ctx.pool,
        repo.?.id,
        v.pattern,
        require_review,
        required_approvals,
    ) catch |err| {
        // Check for unique constraint violation
        log.err("Failed to create protection rule: {}", .{err});
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Pattern already exists\"}");
        return;
    };

    // Return created rule
    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"pattern":"{s}","requireReview":{s},"requiredApprovals":{d},"createdAt":{d}}}
    , .{
        rule.id,
        rule.pattern,
        if (rule.require_review) "true" else "false",
        rule.required_approvals,
        rule.created_at,
    });
}

/// DELETE /api/:user/:repo/settings/protection/:id
/// Delete a protection rule
pub fn deleteProtectionRule(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const id_str = req.param("id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing rule ID parameter\"}");
        return;
    };

    const rule_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid rule ID\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByName(ctx.pool, username, repo_name) catch |err| {
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

    // TODO: Check if user has permission to modify repository settings

    // Delete protection rule
    const deleted = db.deleteProtectedBookmark(ctx.pool, repo.?.id, rule_id) catch |err| {
        log.err("Failed to delete protection rule: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to delete protection rule\"}");
        return;
    };

    if (!deleted) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Protection rule not found\"}");
        return;
    }

    try res.writer().writeAll("{\"success\":true}");
}
