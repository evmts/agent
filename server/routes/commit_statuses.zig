//! Commit Status Routes
//!
//! API routes for managing commit/change statuses (CI check results).
//!
//! Routes:
//! - GET /:user/:repo/changes/:changeId/statuses - Get statuses for a change
//! - POST /:user/:repo/changes/:changeId/statuses - Create/update a status

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");

const log = std.log.scoped(.commit_statuses);

// =============================================================================
// Get Statuses for a Change
// =============================================================================

/// GET /:user/:repo/changes/:changeId/statuses
/// Returns all commit statuses for a given change (by commit SHA)
pub fn getStatuses(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId parameter\"}");
        return;
    };

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, repo_name) catch |err| {
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

    // For jj changes, we need to resolve the change_id to a commit SHA
    // The change_id may be a short form, so we try to get the full commit info
    const change = db.getChangeById(ctx.pool, repo.?.id, change_id) catch null;

    // Use commit_id if available, otherwise use change_id as the SHA
    // (For git repos, change_id might be the commit SHA directly)
    const commit_sha = if (change) |c| (c.commit_id orelse change_id) else change_id;

    // Get commit statuses
    const statuses = db.getCommitStatusesByCommit(ctx.pool, allocator, repo.?.id, commit_sha) catch |err| {
        log.err("Failed to get commit statuses: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get commit statuses\"}");
        return;
    };
    defer allocator.free(statuses);

    // Get aggregated state
    const aggregated_state = db.getCommitStatusAggregatedState(ctx.pool, repo.?.id, commit_sha) catch null;

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"statuses\":[");
    for (statuses, 0..) |status, i| {
        if (i > 0) try writer.writeAll(",");
        try writeStatusJson(writer, status);
    }
    try writer.writeAll("],\"aggregatedState\":");
    if (aggregated_state) |state| {
        try writer.print("\"{s}\"", .{state});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll("}");
}

// =============================================================================
// Create/Update Status
// =============================================================================

/// POST /:user/:repo/changes/:changeId/statuses
/// Create or update a commit status
pub fn createStatus(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId parameter\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        context: []const u8,
        state: []const u8,
        description: ?[]const u8 = null,
        target_url: ?[]const u8 = null,
        workflow_run_id: ?i64 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    // Validate required fields
    if (v.context.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing required field: context\"}");
        return;
    }

    // Validate state
    if (!std.mem.eql(u8, v.state, "pending") and
        !std.mem.eql(u8, v.state, "success") and
        !std.mem.eql(u8, v.state, "failure") and
        !std.mem.eql(u8, v.state, "error"))
    {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid state. Must be: pending, success, failure, or error\"}");
        return;
    }

    // Get repository
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, repo_name) catch |err| {
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

    // Resolve change_id to commit SHA
    const change = db.getChangeById(ctx.pool, repo.?.id, change_id) catch null;
    const commit_sha = if (change) |c| (c.commit_id orelse change_id) else change_id;

    // Create/update status
    const status = db.upsertCommitStatus(
        ctx.pool,
        repo.?.id,
        commit_sha,
        v.context,
        v.state,
        v.description,
        v.target_url,
        v.workflow_run_id,
    ) catch |err| {
        log.err("Failed to upsert commit status: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create/update status\"}");
        return;
    };

    // Return created/updated status
    res.status = 201;
    var writer = res.writer();
    try writer.writeAll("{\"status\":");
    try writeStatusJson(writer, status);
    try writer.writeAll("}");
}

// =============================================================================
// Helper Functions
// =============================================================================

fn writeStatusJson(writer: anytype, status: db.CommitStatus) !void {
    try writer.print(
        \\{{"id":{d},"repositoryId":{d},"commitSha":"{s}","context":"{s}","state":"{s}","description":
    , .{
        status.id,
        status.repository_id,
        status.commit_sha,
        status.context,
        status.state,
    });

    if (status.description) |desc| {
        try writer.print("\"{s}\"", .{desc});
    } else {
        try writer.writeAll("null");
    }

    try writer.writeAll(",\"targetUrl\":");
    if (status.target_url) |url| {
        try writer.print("\"{s}\"", .{url});
    } else {
        try writer.writeAll("null");
    }

    try writer.writeAll(",\"workflowRunId\":");
    if (status.workflow_run_id) |run_id| {
        try writer.print("{d}", .{run_id});
    } else {
        try writer.writeAll("null");
    }

    try writer.print(",\"createdAt\":{d},\"updatedAt\":{d}}}", .{
        status.created_at,
        status.updated_at,
    });
}
