//! Operations API Routes
//!
//! Provides access to jj's operation log for undo/redo functionality.
//! Every jj action is tracked as an operation that can be undone.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("../lib/db.zig");

const log = std.log.scoped(.operations_routes);

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

    // TODO: Get operations from jj using jj-ffi
    // For now, return operations from database cache
    var operations = db.getOperationsByRepository(ctx.pool, ctx.allocator, repository.?.id, limit) catch |err| {
        log.err("Failed to get operations: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve operations\"}");
        return;
    };
    defer operations.deinit();

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

    // Get operation from database
    const operation = db.getOperationById(ctx.pool, repository.?.id, operation_id) catch |err| {
        log.err("Failed to get operation: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to retrieve operation\"}");
        return;
    };

    if (operation == null) {
        // TODO: Try to find in jj op log using jj-ffi
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

    // TODO: Call jj undo operation using jj-ffi
    // For now, just record the undo in the database
    const timestamp = std.time.milliTimestamp();
    const undo_id = try std.fmt.allocPrint(ctx.allocator, "undo-{d}", .{timestamp});
    defer ctx.allocator.free(undo_id);

    db.createOperation(
        ctx.pool,
        repository.?.id,
        undo_id,
        "undo",
        "Undo last operation",
        timestamp,
    ) catch |err| {
        log.err("Failed to record undo operation: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to undo operation\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
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

    // Verify the target operation exists
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

    // TODO: Call jj restore operation using jj-ffi
    // For now, just mark intermediate operations as undone and record the restore
    db.markOperationsAsUndone(ctx.pool, repository.?.id, target_op.?.timestamp) catch |err| {
        log.err("Failed to mark operations as undone: {}", .{err});
        // Continue anyway, this is just cache management
    };

    const timestamp = std.time.milliTimestamp();
    const restore_id = try std.fmt.allocPrint(ctx.allocator, "restore-{d}", .{timestamp});
    defer ctx.allocator.free(restore_id);

    const description = try std.fmt.allocPrint(ctx.allocator, "Restore to operation {s}", .{operation_id});
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
        try res.writer().writeAll("{\"error\":\"Failed to restore operation\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}
