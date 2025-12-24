//! Operations API Routes
//!
//! Provides access to jj's operation log for undo/redo functionality.
//! Every jj action is tracked as an operation that can be undone.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");

const log = std.log.scoped(.operations_routes);

// Import jj-ffi C library
const c = @cImport({
    @cInclude("jj_ffi.h");
});

// =============================================================================
// Helper Functions
// =============================================================================

fn getRepoPath(allocator: std.mem.Allocator, username: []const u8, repo_name: []const u8) ![]const u8 {
    // TODO: Make this configurable
    const base_path = "/tmp/plue/repos";
    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ base_path, username, repo_name });
}

// =============================================================================
// List Operations
// =============================================================================

/// GET /api/:user/:repo/operations
/// List operations for a repository
pub fn listOperations(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const user = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const repo = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Parse limit query parameter (default: 20)
    const query_params = try req.query();
    const limit_str = query_params.get("limit") orelse "20";
    const limit = std.fmt.parseInt(i32, limit_str, 10) catch 20;

    // Get repository
    const repository = db.getRepositoryByUserAndName(ctx.pool, user, repo) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve repository\"}");
        return;
    };

    if (repository == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Get repository path for jj operations
    const repo_path = try getRepoPath(ctx.allocator, user, repo);
    defer ctx.allocator.free(repo_path);

    // Convert to null-terminated C string
    const repo_path_z = try ctx.allocator.dupeZ(u8, repo_path);
    defer ctx.allocator.free(repo_path_z);

    // Try to get current operation from jj-ffi
    // NOTE: Full operation log listing requires jj_list_operations FFI function
    // which needs to be added to jj-ffi/src/lib.rs
    if (c.jj_is_jj_workspace(repo_path_z.ptr)) {
        const workspace_result = c.jj_workspace_open(repo_path_z.ptr);
        defer {
            if (workspace_result.success and workspace_result.workspace != null) {
                c.jj_workspace_free(workspace_result.workspace);
            }
            if (workspace_result.error_message != null) {
                c.jj_string_free(workspace_result.error_message);
            }
        }

        if (workspace_result.success and workspace_result.workspace != null) {
            const op_result = c.jj_get_current_operation(workspace_result.workspace);
            defer {
                if (op_result.success and op_result.operation != null) {
                    c.jj_operation_info_free(op_result.operation);
                }
                if (op_result.error_message != null) {
                    c.jj_string_free(op_result.error_message);
                }
            }

            if (op_result.success and op_result.operation != null) {
                const op = op_result.operation.*;
                const op_id = std.mem.span(op.id);
                const op_desc = std.mem.span(op.description);

                // Store current operation in cache
                db.createOperation(
                    ctx.pool,
                    repository.?.id,
                    op_id,
                    "current",
                    op_desc,
                    op.timestamp,
                ) catch |err| {
                    log.warn("Failed to cache operation: {}", .{err});
                };
            }
        }
    }

    // Return operations from database cache
    // TODO: Once jj_list_operations is added to FFI, fetch directly from jj
    var operations = db.getOperationsByRepository(ctx.pool, ctx.allocator, repository.?.id, limit) catch |err| {
        log.err("Failed to get operations: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve operations\"}");
        return;
    };
    defer operations.deinit(ctx.allocator);

    var writer = res.writer();
    try writer.writeAll("{\"operations\":[");

    for (operations.items, 0..) |op, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.writeAll("{");
        try writer.print("\"operationId\":\"{s}\",", .{op.operation_id});
        try writer.print("\"type\":\"{s}\",", .{op.operation_type});
        try writer.print("\"description\":\"{s}\",", .{op.description});
        try writer.print("\"timestamp\":{d}", .{op.timestamp});
        if (op.is_undone) {
            try writer.writeAll(",\"isUndone\":true");
        }
        try writer.writeAll("}");
    }

    try writer.writeAll("]}");
}

// =============================================================================
// Get Single Operation
// =============================================================================

/// GET /api/:user/:repo/operations/:operationId
/// Get a single operation by ID
pub fn getOperation(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const user = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const repo = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const operation_id = req.param("operationId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing operationId parameter\"}");
        return;
    };

    // Get repository
    const repository = db.getRepositoryByUserAndName(ctx.pool, user, repo) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve repository\"}");
        return;
    };

    if (repository == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // Try to get operation from jj-ffi first
    const repo_path = try getRepoPath(ctx.allocator, user, repo);
    defer ctx.allocator.free(repo_path);

    // Convert to null-terminated C string
    const repo_path_z = try ctx.allocator.dupeZ(u8, repo_path);
    defer ctx.allocator.free(repo_path_z);

    var found_in_jj = false;

    if (c.jj_is_jj_workspace(repo_path_z.ptr)) {
        const workspace_result = c.jj_workspace_open(repo_path_z.ptr);
        defer {
            if (workspace_result.success and workspace_result.workspace != null) {
                c.jj_workspace_free(workspace_result.workspace);
            }
            if (workspace_result.error_message != null) {
                c.jj_string_free(workspace_result.error_message);
            }
        }

        if (workspace_result.success and workspace_result.workspace != null) {
            const op_result = c.jj_get_current_operation(workspace_result.workspace);
            defer {
                if (op_result.success and op_result.operation != null) {
                    c.jj_operation_info_free(op_result.operation);
                }
                if (op_result.error_message != null) {
                    c.jj_string_free(op_result.error_message);
                }
            }

            if (op_result.success and op_result.operation != null) {
                const op = op_result.operation.*;
                const op_id = std.mem.span(op.id);

                // Check if this is the operation we're looking for
                if (std.mem.eql(u8, op_id, operation_id)) {
                    found_in_jj = true;
                    const op_desc = std.mem.span(op.description);

                    var writer = res.writer();
                    try writer.writeAll("{\"operation\":{");
                    try writer.print("\"operationId\":\"{s}\",", .{op_id});
                    try writer.print("\"type\":\"current\",", .{});
                    try writer.print("\"description\":\"{s}\",", .{op_desc});
                    try writer.print("\"timestamp\":{d}", .{op.timestamp});
                    try writer.writeAll("}}");
                    return;
                }
            }
        }
    }

    // Fall back to database cache
    // NOTE: Full operation retrieval by ID requires jj_get_operation FFI function
    const operation = db.getOperationById(ctx.pool, repository.?.id, operation_id) catch |err| {
        log.err("Failed to get operation: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve operation\"}");
        return;
    };

    if (operation == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Operation not found\"}");
        return;
    }

    const op = operation.?;
    var writer = res.writer();
    try writer.writeAll("{\"operation\":{");
    try writer.print("\"operationId\":\"{s}\",", .{op.operation_id});
    try writer.print("\"type\":\"{s}\",", .{op.operation_type});
    try writer.print("\"description\":\"{s}\",", .{op.description});
    try writer.print("\"timestamp\":{d}", .{op.timestamp});
    if (op.is_undone) {
        try writer.writeAll(",\"isUndone\":true");
    }
    try writer.writeAll("}}");
}

// =============================================================================
// Undo Last Operation
// =============================================================================

/// POST /api/:user/:repo/operations/undo
/// Undo the last jj operation
pub fn undoOperation(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const user = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const repo = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    // Get repository
    const repository = db.getRepositoryByUserAndName(ctx.pool, user, repo) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve repository\"}");
        return;
    };

    if (repository == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // NOTE: This requires jj_undo FFI function to be added to jj-ffi/src/lib.rs
    // The FFI function should call jj's operation undo functionality
    // For now, we return an error indicating the feature is not yet available

    const repo_path = try getRepoPath(ctx.allocator, user, repo);
    defer ctx.allocator.free(repo_path);

    // Convert to null-terminated C string
    const repo_path_z = try ctx.allocator.dupeZ(u8, repo_path);
    defer ctx.allocator.free(repo_path_z);

    // Verify it's a jj workspace
    if (!c.jj_is_jj_workspace(repo_path_z.ptr)) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Repository is not a jj workspace\"}");
        return;
    }

    // TODO: Once jj_undo is implemented in FFI, call it here
    // Example implementation would be:
    // const workspace_result = c.jj_workspace_open(repo_path.ptr);
    // defer cleanup...
    // const undo_result = c.jj_undo(workspace_result.workspace);
    // if (!undo_result.success) { return error }

    log.warn("Undo operation requested but jj_undo FFI not yet implemented", .{});

    // For now, record the undo request in the database for tracking
    const timestamp = std.time.milliTimestamp();
    const undo_id = try std.fmt.allocPrint(ctx.allocator, "undo-{d}", .{timestamp});
    defer ctx.allocator.free(undo_id);

    db.createOperation(
        ctx.pool,
        repository.?.id,
        undo_id,
        "undo",
        "Undo operation (pending FFI implementation)",
        timestamp,
    ) catch |err| {
        log.err("Failed to record undo operation: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to record undo operation\"}");
        return;
    };

    res.status = 501; // Not Implemented
    try res.writer().writeAll("{\"error\":\"Undo operation requires jj_undo FFI function\",\"status\":\"not_implemented\"}");
}

// =============================================================================
// Restore to Specific Operation
// =============================================================================

/// POST /api/:user/:repo/operations/:operationId/restore
/// Restore repository to a specific operation
pub fn restoreOperation(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    const user = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const repo = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const operation_id = req.param("operationId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing operationId parameter\"}");
        return;
    };

    // Get repository
    const repository = db.getRepositoryByUserAndName(ctx.pool, user, repo) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve repository\"}");
        return;
    };

    if (repository == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    }

    // NOTE: This requires jj_restore_operation FFI function to be added to jj-ffi/src/lib.rs
    // The FFI function should call jj's operation restore functionality

    const repo_path = try getRepoPath(ctx.allocator, user, repo);
    defer ctx.allocator.free(repo_path);

    // Convert to null-terminated C string
    const repo_path_z = try ctx.allocator.dupeZ(u8, repo_path);
    defer ctx.allocator.free(repo_path_z);

    // Verify it's a jj workspace
    if (!c.jj_is_jj_workspace(repo_path_z.ptr)) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Repository is not a jj workspace\"}");
        return;
    }

    // Verify the target operation exists in database cache
    const target_op = db.getOperationById(ctx.pool, repository.?.id, operation_id) catch |err| {
        log.err("Failed to get target operation: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve operation\"}");
        return;
    };

    if (target_op == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Operation not found\"}");
        return;
    }

    // TODO: Once jj_restore_operation is implemented in FFI, call it here
    // Example implementation would be:
    // const workspace_result = c.jj_workspace_open(repo_path.ptr);
    // defer cleanup...
    // const restore_result = c.jj_restore_operation(workspace_result.workspace, operation_id.ptr);
    // if (!restore_result.success) { return error }

    log.warn("Restore operation requested but jj_restore_operation FFI not yet implemented", .{});

    // For now, mark intermediate operations as undone in cache and record the restore
    db.markOperationsAsUndone(ctx.pool, repository.?.id, target_op.?.timestamp) catch |err| {
        log.err("Failed to mark operations as undone: {}", .{err});
        // Continue anyway, this is just cache management
    };

    const timestamp = std.time.milliTimestamp();
    const restore_id = try std.fmt.allocPrint(ctx.allocator, "restore-{d}", .{timestamp});
    defer ctx.allocator.free(restore_id);

    const description = try std.fmt.allocPrint(ctx.allocator, "Restore to operation {s} (pending FFI implementation)", .{operation_id});
    defer ctx.allocator.free(description);

    db.createOperation(
        ctx.pool,
        repository.?.id,
        restore_id,
        "restore",
        description,
        timestamp,
    ) catch |err| {
        log.err("Failed to record restore operation: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to record restore operation\"}");
        return;
    };

    res.status = 501; // Not Implemented
    try res.writer().writeAll("{\"error\":\"Restore operation requires jj_restore_operation FFI function\",\"status\":\"not_implemented\"}");
}
