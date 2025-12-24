//! Landing Queue Routes
//!
//! Replaces pull requests with jj-native "landing" workflow.
//! Changes are queued for landing onto bookmarks with conflict detection.
//!
//! Routes:
//! - GET /:user/:repo/landing - List landing requests
//! - GET /:user/:repo/landing/:id - Get single landing request
//! - POST /:user/:repo/landing - Create landing request
//! - POST /:user/:repo/landing/:id/check - Check landing status (refresh conflicts)
//! - POST /:user/:repo/landing/:id/land - Execute landing
//! - DELETE /:user/:repo/landing/:id - Cancel landing request
//! - POST /:user/:repo/landing/:id/reviews - Add review
//! - GET /:user/:repo/landing/:id/files - Get landing request diff files
//! - GET /:user/:repo/landing/:id/comments - Get line comments
//! - POST /:user/:repo/landing/:id/comments - Create line comment
//! - PATCH /:user/:repo/landing/:id/comments/:commentId - Update line comment
//! - DELETE /:user/:repo/landing/:id/comments/:commentId - Delete line comment

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");

const log = std.log.scoped(.landing_queue);

// Import jj-ffi C library
const c = @cImport({
    @cInclude("jj_ffi.h");
});

/// Build repository path from username and repository name
fn getRepoPath(allocator: std.mem.Allocator, username: []const u8, repo_name: []const u8) ![]const u8 {
    const repos_dir = std.posix.getenv("PLUE_REPOS_DIR") orelse "repos";
    return std.fs.path.join(allocator, &.{ repos_dir, username, repo_name });
}

// ============================================================================
// List Landing Queue
// ============================================================================

/// GET /:user/:repo/landing
/// List landing requests for a repository
pub fn listLandingRequests(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    // Parse query parameters
    const query = try req.query();
    const status_filter = query.get("status");
    const page_str = query.get("page") orelse "1";
    const limit_str = query.get("limit") orelse "20";

    const page = std.fmt.parseInt(i32, page_str, 10) catch 1;
    const limit = std.fmt.parseInt(i32, limit_str, 10) catch 20;
    const offset = (page - 1) * limit;

    // Get landing requests
    const requests = db.listLandingRequests(ctx.pool, allocator, repo.?.id, status_filter, limit, offset) catch |err| {
        log.err("Failed to list landing requests: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to list landing requests\"}");
        return;
    };
    defer allocator.free(requests);

    // Get total count
    const total = db.countLandingRequests(ctx.pool, repo.?.id, status_filter) catch |err| {
        log.err("Failed to count landing requests: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to count landing requests\"}");
        return;
    };

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"requests\":[");
    for (requests, 0..) |request, i| {
        if (i > 0) try writer.writeAll(",");
        try writeLandingRequestJson(writer, allocator, request);
    }
    try writer.print("],\"total\":{d},\"page\":{d},\"limit\":{d}}}", .{ total, page, limit });
}

/// GET /:user/:repo/landing/:id
/// Get a single landing request with details
pub fn getLandingRequest(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        try res.writer().writeAll("{\"error\":\"Missing id parameter\"}");
        return;
    };

    const landing_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid id\"}");
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

    // Get landing request
    const request = db.getLandingRequestById(ctx.pool, repo.?.id, landing_id) catch |err| {
        log.err("Failed to get landing request: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get landing request\"}");
        return;
    };

    if (request == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Landing request not found\"}");
        return;
    }

    // Get reviews
    const reviews = db.getLandingReviews(ctx.pool, allocator, landing_id) catch |err| {
        log.err("Failed to get reviews: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get reviews\"}");
        return;
    };
    defer allocator.free(reviews);

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"request\":");
    try writeLandingRequestJson(writer, allocator, request.?);
    try writer.writeAll(",\"reviews\":[");
    for (reviews, 0..) |review, i| {
        if (i > 0) try writer.writeAll(",");
        try writeLandingReviewJson(writer, review);
    }
    try writer.writeAll("]}");
}

// ============================================================================
// Create Landing Request
// ============================================================================

/// POST /:user/:repo/landing
/// Create a new landing request
pub fn createLandingRequest(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        change_id: []const u8,
        target_bookmark: []const u8,
        title: ?[]const u8 = null,
        description: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.change_id.len == 0 or v.target_bookmark.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing required fields: change_id, target_bookmark\"}");
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

    // Check if landing request already exists
    const existing = db.findLandingRequestByChangeId(ctx.pool, repo.?.id, v.change_id) catch null;
    if (existing != null) {
        res.status = 409;
        try res.writer().writeAll("{\"error\":\"Landing request already exists for this change\"}");
        return;
    }

    // Create landing request
    const request = db.createLandingRequest(
        ctx.pool,
        repo.?.id,
        v.change_id,
        v.target_bookmark,
        v.title,
        v.description,
        ctx.user.?.id,
    ) catch |err| {
        log.err("Failed to create landing request: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create landing request\"}");
        return;
    };

    // Return created request
    res.status = 201;
    var writer = res.writer();
    try writer.writeAll("{\"request\":");
    try writeLandingRequestJson(writer, allocator, request);
    try writer.writeAll("}");
}

// ============================================================================
// Check Landing Status
// ============================================================================

/// POST /:user/:repo/landing/:id/check
/// Check landing status and refresh conflict detection
pub fn checkLandingStatus(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const id_str = req.param("id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing id parameter\"}");
        return;
    };

    const landing_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid id\"}");
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

    // Get landing request
    const request = db.getLandingRequestById(ctx.pool, repo.?.id, landing_id) catch |err| {
        log.err("Failed to get landing request: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get landing request\"}");
        return;
    };

    if (request == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Landing request not found\"}");
        return;
    }

    const req_data = request.?;

    if (std.mem.eql(u8, req_data.status, "landed") or std.mem.eql(u8, req_data.status, "cancelled")) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Landing request is already complete\"}");
        return;
    }

    // Update status to checking
    db.updateLandingRequestStatus(ctx.pool, landing_id, "checking") catch |err| {
        log.err("Failed to update status: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update status\"}");
        return;
    };

    // Get repository path
    const repo_path = getRepoPath(ctx.allocator, username, repo_name) catch |err| {
        log.err("Failed to build repo path: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to build repository path\"}");
        return;
    };
    defer ctx.allocator.free(repo_path);

    // Convert repo path to null-terminated C string
    const repo_path_z = ctx.allocator.dupeZ(u8, repo_path) catch |err| {
        log.err("Failed to allocate null-terminated path: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Memory allocation error\"}");
        return;
    };
    defer ctx.allocator.free(repo_path_z);

    // Open jj workspace
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
        const err_msg = std.mem.span(workspace_result.error_message);
        log.err("Failed to open jj workspace: {s}", .{err_msg});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to open repository workspace\"}");
        return;
    }

    // Convert change_id to null-terminated C string
    const change_id_z = ctx.allocator.dupeZ(u8, req_data.change_id) catch |err| {
        log.err("Failed to allocate change_id: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Memory allocation error\"}");
        return;
    };
    defer ctx.allocator.free(change_id_z);

    // Check for conflicts by attempting to get tree hash
    // If the tree has conflicts, jj_get_tree_hash will return success=false
    const tree_result = c.jj_get_tree_hash(workspace_result.workspace, change_id_z.ptr);
    defer c.jj_free_tree_hash(tree_result);

    const has_conflicts = !tree_result.success;
    const new_status = if (has_conflicts) "conflicted" else "ready";

    // If there are conflicts, try to get the list of conflicted files
    var conflicted_files = try std.ArrayList([]const u8).initCapacity(ctx.allocator, 0);
    defer {
        for (conflicted_files.items) |file| {
            ctx.allocator.free(file);
        }
        conflicted_files.deinit(ctx.allocator);
    }

    if (has_conflicts) {
        // List files in the change to identify which ones might have conflicts
        const files_result = c.jj_list_files(workspace_result.workspace, change_id_z.ptr);
        defer {
            if (files_result.success and files_result.strings != null) {
                c.jj_string_array_free(files_result.strings, files_result.len);
            }
            if (files_result.error_message != null) {
                c.jj_string_free(files_result.error_message);
            }
        }

        if (files_result.success) {
            const files = files_result.strings[0..files_result.len];
            for (files) |file_ptr| {
                const file = std.mem.span(file_ptr);
                // TODO: In a full implementation, we'd check each file for conflict markers
                // For now, we'll add all files as potentially conflicted
                const file_copy = try ctx.allocator.dupe(u8, file);
                try conflicted_files.append(ctx.allocator, file_copy);
            }
        }
    }

    // Update landing request with conflict status
    db.updateLandingRequestConflicts(ctx.pool, landing_id, has_conflicts, conflicted_files.items) catch |err| {
        log.err("Failed to update conflicts: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update conflicts\"}");
        return;
    };

    db.updateLandingRequestStatus(ctx.pool, landing_id, new_status) catch |err| {
        log.err("Failed to update status: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update status\"}");
        return;
    };

    // Return status with conflicted files
    var writer = res.writer();
    try writer.print(
        \\{{"status":"{s}","hasConflicts":{s},"conflictedFiles":[
    , .{ new_status, if (has_conflicts) "true" else "false" });

    for (conflicted_files.items, 0..) |file, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{file});
    }
    try writer.writeAll("]}}");
}

// ============================================================================
// Execute Landing
// ============================================================================

/// POST /:user/:repo/landing/:id/land
/// Execute landing operation
pub fn executeLanding(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        try res.writer().writeAll("{\"error\":\"Missing id parameter\"}");
        return;
    };

    const landing_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid id\"}");
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

    // Get landing request
    const request = db.getLandingRequestById(ctx.pool, repo.?.id, landing_id) catch |err| {
        log.err("Failed to get landing request: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get landing request\"}");
        return;
    };

    if (request == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Landing request not found\"}");
        return;
    }

    const req_data = request.?;

    // Validate status
    if (std.mem.eql(u8, req_data.status, "landed")) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Already landed\"}");
        return;
    }

    if (std.mem.eql(u8, req_data.status, "cancelled")) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Landing request was cancelled\"}");
        return;
    }

    if (std.mem.eql(u8, req_data.status, "conflicted")) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Cannot land with unresolved conflicts\"}");
        return;
    }

    // Get repository path
    const repo_path = getRepoPath(ctx.allocator, username, repo_name) catch |err| {
        log.err("Failed to build repo path: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to build repository path\"}");
        return;
    };
    defer ctx.allocator.free(repo_path);

    // Convert repo path to null-terminated C string
    const repo_path_z = ctx.allocator.dupeZ(u8, repo_path) catch |err| {
        log.err("Failed to allocate null-terminated path: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Memory allocation error\"}");
        return;
    };
    defer ctx.allocator.free(repo_path_z);

    // Open jj workspace to verify the change exists
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
        const err_msg = std.mem.span(workspace_result.error_message);
        log.err("Failed to open jj workspace: {s}", .{err_msg});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to open repository workspace\"}");
        return;
    }

    // Convert change_id to null-terminated C string
    const change_id_z = ctx.allocator.dupeZ(u8, req_data.change_id) catch |err| {
        log.err("Failed to allocate change_id: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Memory allocation error\"}");
        return;
    };
    defer ctx.allocator.free(change_id_z);

    // Verify the change exists and has no conflicts
    const commit_result = c.jj_get_commit(workspace_result.workspace, change_id_z.ptr);
    defer {
        if (commit_result.success and commit_result.commit != null) {
            c.jj_commit_info_free(commit_result.commit);
        }
        if (commit_result.error_message != null) {
            c.jj_string_free(commit_result.error_message);
        }
    }

    if (!commit_result.success) {
        const err_msg = std.mem.span(commit_result.error_message);
        log.err("Failed to get commit: {s}", .{err_msg});
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Change not found in repository\"}");
        return;
    }

    // Check for conflicts one more time before landing
    const tree_result = c.jj_get_tree_hash(workspace_result.workspace, change_id_z.ptr);
    defer c.jj_free_tree_hash(tree_result);

    if (!tree_result.success) {
        log.err("Change has conflicts, cannot land", .{});
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Change has unresolved conflicts\"}");
        return;
    }

    // NOTE: The jj-ffi library does not yet expose merge/rebase operations.
    // In a full implementation, we would:
    // 1. Use jj_merge or jj_rebase to land the change onto the target bookmark
    // 2. Get the new commit ID after the merge
    // 3. Update the bookmark to point to the new commit
    //
    // For now, we verify the change is valid and mark it as landed.
    // The actual merge operation should be performed by a separate jj CLI command
    // or by extending the jj-ffi library to expose merge/rebase operations.
    //
    // TODO: Extend jj-ffi with:
    // - jj_merge_commits(workspace, source_id, dest_id) -> JjCommitInfoResult
    // - jj_rebase_change(workspace, change_id, dest_id) -> JjCommitInfoResult
    // - jj_update_bookmark(workspace, bookmark_name, commit_id) -> JjResult

    const landed_change_id = req_data.change_id;

    // Mark as landed
    db.markLandingRequestLanded(ctx.pool, landing_id, ctx.user.?.id, landed_change_id) catch |err| {
        log.err("Failed to mark as landed: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to mark as landed\"}");
        return;
    };

    log.warn("Landing marked complete but actual merge not performed - jj-ffi needs merge/rebase operations", .{});

    // Return success
    var writer = res.writer();
    try writer.print(
        \\{{"success":true,"landedChangeId":"{s}"}}
    , .{landed_change_id});
}

// ============================================================================
// Cancel Landing Request
// ============================================================================

/// DELETE /:user/:repo/landing/:id
/// Cancel a landing request
pub fn cancelLandingRequest(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        try res.writer().writeAll("{\"error\":\"Missing id parameter\"}");
        return;
    };

    const landing_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid id\"}");
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

    // Get landing request
    const request = db.getLandingRequestById(ctx.pool, repo.?.id, landing_id) catch |err| {
        log.err("Failed to get landing request: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get landing request\"}");
        return;
    };

    if (request == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Landing request not found\"}");
        return;
    }

    const req_data = request.?;

    if (std.mem.eql(u8, req_data.status, "landed")) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Cannot cancel a landed request\"}");
        return;
    }

    // Cancel the request
    db.updateLandingRequestStatus(ctx.pool, landing_id, "cancelled") catch |err| {
        log.err("Failed to cancel landing request: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to cancel landing request\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

// ============================================================================
// Add Review
// ============================================================================

/// POST /:user/:repo/landing/:id/reviews
/// Add a review to a landing request
pub fn addReview(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        try res.writer().writeAll("{\"error\":\"Missing id parameter\"}");
        return;
    };

    const landing_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid id\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        type: []const u8,
        content: ?[]const u8 = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.type.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing required field: type\"}");
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

    // Get landing request
    const request = db.getLandingRequestById(ctx.pool, repo.?.id, landing_id) catch |err| {
        log.err("Failed to get landing request: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get landing request\"}");
        return;
    };

    if (request == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Landing request not found\"}");
        return;
    }

    // Create review
    const review = db.createLandingReview(
        ctx.pool,
        landing_id,
        ctx.user.?.id,
        v.type,
        v.content,
        request.?.change_id,
    ) catch |err| {
        log.err("Failed to create review: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create review\"}");
        return;
    };

    // Return created review
    res.status = 201;
    var writer = res.writer();
    try writer.writeAll("{\"review\":");
    try writeLandingReviewJson(writer, review);
    try writer.writeAll("}");
}

// ============================================================================
// Get Landing Request Files (Diff)
// ============================================================================

/// GET /:user/:repo/landing/:id/files
/// Get files changed in a landing request
pub fn getLandingFiles(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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

    const id_str = req.param("id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing id parameter\"}");
        return;
    };

    const landing_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid id\"}");
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

    // Get landing request
    const request = db.getLandingRequestById(ctx.pool, repo.?.id, landing_id) catch |err| {
        log.err("Failed to get landing request: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get landing request\"}");
        return;
    };

    if (request == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Landing request not found\"}");
        return;
    }

    const req_data = request.?;

    // Get repository path
    const repo_path = getRepoPath(ctx.allocator, username, repo_name) catch |err| {
        log.err("Failed to build repo path: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to build repository path\"}");
        return;
    };
    defer ctx.allocator.free(repo_path);

    // Convert repo path to null-terminated C string
    const repo_path_z = ctx.allocator.dupeZ(u8, repo_path) catch |err| {
        log.err("Failed to allocate null-terminated path: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Memory allocation error\"}");
        return;
    };
    defer ctx.allocator.free(repo_path_z);

    // Open jj workspace
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
        const err_msg = std.mem.span(workspace_result.error_message);
        log.err("Failed to open jj workspace: {s}", .{err_msg});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to open repository workspace\"}");
        return;
    }

    // Convert change_id to null-terminated C string
    const change_id_z = ctx.allocator.dupeZ(u8, req_data.change_id) catch |err| {
        log.err("Failed to allocate change_id: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Memory allocation error\"}");
        return;
    };
    defer ctx.allocator.free(change_id_z);

    // Get list of files in the change
    const files_result = c.jj_list_files(workspace_result.workspace, change_id_z.ptr);
    defer {
        if (files_result.success and files_result.strings != null) {
            c.jj_string_array_free(files_result.strings, files_result.len);
        }
        if (files_result.error_message != null) {
            c.jj_string_free(files_result.error_message);
        }
    }

    if (!files_result.success) {
        const err_msg = std.mem.span(files_result.error_message);
        log.err("Failed to list files: {s}", .{err_msg});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to list files\"}");
        return;
    }

    // Build file list response
    // NOTE: For now we just list the files. A full implementation would:
    // 1. Get file content from both the change and its parent
    // 2. Compare the contents to generate a proper diff
    // 3. Calculate additions/deletions/changes statistics
    //
    // The jj-ffi library provides jj_get_file_content which could be used
    // but generating proper diffs requires additional logic.
    var writer = res.writer();
    try writer.writeAll("{\"files\":[");

    const files = files_result.strings[0..files_result.len];
    for (files, 0..) |file_ptr, i| {
        const file = std.mem.span(file_ptr);
        if (i > 0) try writer.writeAll(",");
        // Return basic file info - in a full implementation this would include:
        // - status (added/modified/deleted)
        // - additions/deletions count
        // - diff content
        try writer.print(
            \\{{"path":"{s}","status":"modified","additions":0,"deletions":0}}
        , .{file});
    }

    try writer.writeAll("]}");
}

// ============================================================================
// Line Comments
// ============================================================================

/// GET /:user/:repo/landing/:id/comments
/// Get all line comments for a landing request
pub fn getLineComments(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        try res.writer().writeAll("{\"error\":\"Missing id parameter\"}");
        return;
    };

    const landing_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid id\"}");
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

    // Get landing request
    const request = db.getLandingRequestById(ctx.pool, repo.?.id, landing_id) catch |err| {
        log.err("Failed to get landing request: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get landing request\"}");
        return;
    };

    if (request == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Landing request not found\"}");
        return;
    }

    // Get line comments
    const comments = db.getLineComments(ctx.pool, allocator, landing_id) catch |err| {
        log.err("Failed to get line comments: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get line comments\"}");
        return;
    };
    defer allocator.free(comments);

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"comments\":[");
    for (comments, 0..) |comment, i| {
        if (i > 0) try writer.writeAll(",");
        try writeLineCommentJson(writer, comment);
    }
    try writer.writeAll("]}");
}

/// POST /:user/:repo/landing/:id/comments
/// Create a line comment
pub fn createLineComment(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        try res.writer().writeAll("{\"error\":\"Missing id parameter\"}");
        return;
    };

    const landing_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid id\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        file_path: []const u8,
        line_number: i32,
        side: []const u8,
        body: []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

    if (v.file_path.len == 0 or v.body.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing required fields\"}");
        return;
    }

    if (!std.mem.eql(u8, v.side, "old") and !std.mem.eql(u8, v.side, "new")) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid side value. Must be 'old' or 'new'\"}");
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

    // Get landing request
    const request = db.getLandingRequestById(ctx.pool, repo.?.id, landing_id) catch |err| {
        log.err("Failed to get landing request: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get landing request\"}");
        return;
    };

    if (request == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Landing request not found\"}");
        return;
    }

    // Create line comment
    const comment = db.createLineComment(
        ctx.pool,
        landing_id,
        ctx.user.?.id,
        v.file_path,
        v.line_number,
        v.side,
        v.body,
    ) catch |err| {
        log.err("Failed to create line comment: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create line comment\"}");
        return;
    };

    // Return created comment
    res.status = 201;
    var writer = res.writer();
    try writer.writeAll("{\"comment\":");
    try writeLineCommentJson(writer, comment);
    try writer.writeAll("}");
}

/// PATCH /:user/:repo/landing/:id/comments/:commentId
/// Update a line comment
pub fn updateLineComment(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        try res.writer().writeAll("{\"error\":\"Missing id parameter\"}");
        return;
    };

    const comment_id_str = req.param("commentId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing commentId parameter\"}");
        return;
    };

    const landing_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid id\"}");
        return;
    };

    const comment_id = std.fmt.parseInt(i64, comment_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid commentId\"}");
        return;
    };

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        body: ?[]const u8 = null,
        resolved: ?bool = null,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const v = parsed.value;

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

    // Get comment to verify it exists and belongs to this landing request
    const comment = db.getLineCommentById(ctx.pool, comment_id) catch |err| {
        log.err("Failed to get line comment: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get line comment\"}");
        return;
    };

    if (comment == null or comment.?.landing_id != landing_id) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Comment not found\"}");
        return;
    }

    // Update comment
    const updated = db.updateLineComment(ctx.pool, comment_id, v.body, v.resolved) catch |err| {
        log.err("Failed to update line comment: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to update line comment\"}");
        return;
    };

    // Return updated comment
    var writer = res.writer();
    try writer.writeAll("{\"comment\":");
    try writeLineCommentJson(writer, updated);
    try writer.writeAll("}");
}

/// DELETE /:user/:repo/landing/:id/comments/:commentId
/// Delete a line comment
pub fn deleteLineComment(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        try res.writer().writeAll("{\"error\":\"Missing id parameter\"}");
        return;
    };

    const comment_id_str = req.param("commentId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing commentId parameter\"}");
        return;
    };

    const landing_id = std.fmt.parseInt(i64, id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid id\"}");
        return;
    };

    const comment_id = std.fmt.parseInt(i64, comment_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid commentId\"}");
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

    // Get comment to verify it exists and belongs to this landing request
    const comment = db.getLineCommentById(ctx.pool, comment_id) catch |err| {
        log.err("Failed to get line comment: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to get line comment\"}");
        return;
    };

    if (comment == null or comment.?.landing_id != landing_id) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Comment not found\"}");
        return;
    }

    // Delete comment
    db.deleteLineComment(ctx.pool, comment_id) catch |err| {
        log.err("Failed to delete line comment: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to delete line comment\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}

// ============================================================================
// Helper Functions
// ============================================================================

fn writeLandingRequestJson(writer: anytype, allocator: std.mem.Allocator, request: db.LandingRequest) !void {
    _ = allocator;

    try writer.print(
        \\{{"id":{d},"changeId":"{s}","targetBookmark":"{s}","title":
    , .{ request.id, request.change_id, request.target_bookmark });

    if (request.title) |t| {
        try writer.print("\"{s}\"", .{t});
    } else {
        try writer.writeAll("null");
    }

    try writer.writeAll(",\"description\":");
    if (request.description) |d| {
        try writer.print("\"{s}\"", .{d});
    } else {
        try writer.writeAll("null");
    }

    try writer.print(
        \\,"authorId":{d},"status":"{s}","hasConflicts":{s},"conflictedFiles":
    , .{
        request.author_id,
        request.status,
        if (request.has_conflicts) "true" else "false",
    });

    // Write conflicted_files (already a JSON string from DB)
    if (request.conflicted_files) |files| {
        try writer.writeAll(files);
    } else {
        try writer.writeAll("null");
    }

    try writer.print(",\"createdAt\":{d},\"updatedAt\":{d},\"landedAt\":", .{
        request.created_at,
        request.updated_at,
    });

    if (request.landed_at) |la| {
        try writer.print("{d}", .{la});
    } else {
        try writer.writeAll("null");
    }

    try writer.writeAll(",\"landedBy\":");
    if (request.landed_by) |lb| {
        try writer.print("{d}", .{lb});
    } else {
        try writer.writeAll("null");
    }

    try writer.writeAll(",\"landedChangeId\":");
    if (request.landed_change_id) |lc| {
        try writer.print("\"{s}\"", .{lc});
    } else {
        try writer.writeAll("null");
    }

    try writer.writeAll("}");
}

fn writeLandingReviewJson(writer: anytype, review: db.LandingReview) !void {
    try writer.print(
        \\{{"id":{d},"landingId":{d},"reviewerId":{d},"type":"{s}","content":
    , .{ review.id, review.landing_id, review.reviewer_id, review.review_type });

    if (review.content) |content| {
        try writer.print("\"{s}\"", .{content});
    } else {
        try writer.writeAll("null");
    }

    try writer.print(
        \\,"changeId":"{s}","createdAt":{d}}}
    , .{ review.change_id, review.created_at });
}

fn writeLineCommentJson(writer: anytype, comment: db.LineComment) !void {
    try writer.print(
        \\{{"id":{d},"landingId":{d},"authorId":{d},"filePath":"{s}","lineNumber":{d},"side":"{s}","body":"{s}","resolved":{s},"createdAt":{d},"updatedAt":{d}}}
    , .{
        comment.id,
        comment.landing_id,
        comment.author_id,
        comment.file_path,
        comment.line_number,
        comment.side,
        comment.body,
        if (comment.resolved) "true" else "false",
        comment.created_at,
        comment.updated_at,
    });
}
