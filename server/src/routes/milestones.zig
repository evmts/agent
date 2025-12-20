//! Milestone routes
//!
//! Handles milestone management for repositories:
//! 1. GET /:user/:repo/milestones - List milestones
//! 2. GET /:user/:repo/milestones/:id - Get milestone
//! 3. POST /:user/:repo/milestones - Create milestone
//! 4. PATCH /:user/:repo/milestones/:id - Update milestone
//! 5. DELETE /:user/:repo/milestones/:id - Delete milestone
//! 6. PUT /:user/:repo/issues/:number/milestone - Assign milestone to issue
//! 7. DELETE /:user/:repo/issues/:number/milestone - Remove milestone from issue

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db_issues = @import("../lib/db_issues.zig");

const log = std.log.scoped(.milestone_routes);

// ============================================================================
// Milestone Routes
// ============================================================================

/// GET /:user/:repo/milestones
/// List milestones for a repository
pub fn listMilestones(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const query_params = try req.query();
    const state = query_params.get("state") orelse "open";

    // List milestones
    const milestones = db_issues.listMilestones(ctx.pool, allocator, repo.?.id, state) catch |err| {
        log.err("Failed to list milestones: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };
    defer allocator.free(milestones);

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"milestones\":[");
    for (milestones, 0..) |milestone, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\{{"id":{d},"title":"{s}","description":{s},"dueDate":{s},"state":"{s}","openIssues":{d},"closedIssues":{d},"createdAt":{d},"updatedAt":{d},"closedAt":{s}}}
        , .{
            milestone.id,
            milestone.title,
            if (milestone.description) |d| try std.fmt.allocPrint(allocator, "\"{s}\"", .{d}) else "null",
            if (milestone.due_date) |dd| try std.fmt.allocPrint(allocator, "{d}", .{dd}) else "null",
            milestone.state,
            milestone.open_issues,
            milestone.closed_issues,
            milestone.created_at,
            milestone.updated_at,
            if (milestone.closed_at) |ca| try std.fmt.allocPrint(allocator, "{d}", .{ca}) else "null",
        });
    }
    try writer.writeAll("]}");
}

/// GET /:user/:repo/milestones/:id
/// Get a single milestone with issue counts
pub fn getMilestone(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const id_str = req.param("id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing milestone ID parameter\"}");
        return;
    };

    const milestone_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid milestone ID\"}");
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

    // Get milestone
    const milestone = db_issues.getMilestone(ctx.pool, repo.?.id, milestone_id) catch |err| {
        log.err("Failed to get milestone: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (milestone == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Milestone not found\"}");
        return;
    }

    // Build JSON response
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"title":"{s}","description":{s},"dueDate":{s},"state":"{s}","openIssues":{d},"closedIssues":{d},"createdAt":{d},"updatedAt":{d},"closedAt":{s}}}
    , .{
        milestone.?.id,
        milestone.?.title,
        if (milestone.?.description) |d| try std.fmt.allocPrint(allocator, "\"{s}\"", .{d}) else "null",
        if (milestone.?.due_date) |dd| try std.fmt.allocPrint(allocator, "{d}", .{dd}) else "null",
        milestone.?.state,
        milestone.?.open_issues,
        milestone.?.closed_issues,
        milestone.?.created_at,
        milestone.?.updated_at,
        if (milestone.?.closed_at) |ca| try std.fmt.allocPrint(allocator, "{d}", .{ca}) else "null",
    });
}

/// POST /:user/:repo/milestones
/// Create a new milestone
pub fn createMilestone(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        description: ?[]const u8 = null,
        due_date: ?i64 = null,
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

    // Create milestone
    const milestone = db_issues.createMilestone(ctx.pool, repo.?.id, v.title, v.description, v.due_date) catch |err| {
        log.err("Failed to create milestone: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create milestone\"}");
        return;
    };

    // Return created milestone
    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"title":"{s}","description":{s},"dueDate":{s},"state":"{s}","openIssues":0,"closedIssues":0,"createdAt":{d},"updatedAt":{d},"closedAt":null}}
    , .{
        milestone.id,
        milestone.title,
        if (milestone.description) |d| try std.fmt.allocPrint(allocator, "\"{s}\"", .{d}) else "null",
        if (milestone.due_date) |dd| try std.fmt.allocPrint(allocator, "{d}", .{dd}) else "null",
        milestone.state,
        milestone.created_at,
        milestone.updated_at,
    });
}

/// PATCH /:user/:repo/milestones/:id
/// Update a milestone
pub fn updateMilestone(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const id_str = req.param("id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing milestone ID parameter\"}");
        return;
    };

    const milestone_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid milestone ID\"}");
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
        description: ?[]const u8 = null,
        due_date: ?i64 = null,
        state: ?[]const u8 = null,
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

    // Update milestone
    const milestone = db_issues.updateMilestone(
        ctx.pool,
        repo.?.id,
        milestone_id,
        v.title,
        v.description,
        v.due_date,
        v.state,
    ) catch |err| {
        log.err("Failed to update milestone: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update milestone\"}");
        return;
    };

    if (milestone == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Milestone not found\"}");
        return;
    }

    // Return updated milestone
    var writer = res.writer();
    try writer.print(
        \\{{"id":{d},"title":"{s}","description":{s},"dueDate":{s},"state":"{s}","openIssues":{d},"closedIssues":{d},"createdAt":{d},"updatedAt":{d},"closedAt":{s}}}
    , .{
        milestone.?.id,
        milestone.?.title,
        if (milestone.?.description) |d| try std.fmt.allocPrint(allocator, "\"{s}\"", .{d}) else "null",
        if (milestone.?.due_date) |dd| try std.fmt.allocPrint(allocator, "{d}", .{dd}) else "null",
        milestone.?.state,
        milestone.?.open_issues,
        milestone.?.closed_issues,
        milestone.?.created_at,
        milestone.?.updated_at,
        if (milestone.?.closed_at) |ca| try std.fmt.allocPrint(allocator, "{d}", .{ca}) else "null",
    });
}

/// DELETE /:user/:repo/milestones/:id
/// Delete a milestone
pub fn deleteMilestone(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        try res.writer().writeAll("{\"error\":\"Missing milestone ID parameter\"}");
        return;
    };

    const milestone_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid milestone ID\"}");
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

    // Delete milestone
    const deleted = db_issues.deleteMilestone(ctx.pool, repo.?.id, milestone_id) catch |err| {
        log.err("Failed to delete milestone: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to delete milestone\"}");
        return;
    };

    if (!deleted) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Milestone not found\"}");
        return;
    }

    try res.writer().writeAll("{\"success\":true}");
}

// ============================================================================
// Issue Milestone Assignment Routes
// ============================================================================

/// PUT /:user/:repo/issues/:number/milestone
/// Assign milestone to an issue
pub fn assignMilestoneToIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        milestone_id: i64,
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

    // Verify milestone exists and belongs to this repository
    const milestone = db_issues.getMilestone(ctx.pool, repo.?.id, v.milestone_id) catch |err| {
        log.err("Failed to get milestone: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Database error\"}");
        return;
    };

    if (milestone == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Milestone not found\"}");
        return;
    }

    // Assign milestone to issue
    db_issues.assignMilestoneToIssue(ctx.pool, repo.?.id, issue_number, v.milestone_id) catch |err| {
        log.err("Failed to assign milestone to issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to assign milestone\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

/// DELETE /:user/:repo/issues/:number/milestone
/// Remove milestone from an issue
pub fn removeMilestoneFromIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    // Remove milestone from issue
    db_issues.removeMilestoneFromIssue(ctx.pool, repo.?.id, issue_number) catch |err| {
        log.err("Failed to remove milestone from issue: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to remove milestone\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}
