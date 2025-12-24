//! Changes routes - REST API for repository changes (jj-specific)
//!
//! Implements file viewing, comparison, and conflict resolution at specific changes.
//! Changes are jj's fundamental unit (stable IDs unlike git commits).

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");

const log = std.log.scoped(.changes_routes);

// Import jj-ffi C bindings
const c = @cImport({
    @cInclude("stddef.h");
    @cInclude("jj_ffi.h");
});

// =============================================================================
// Helper Functions
// =============================================================================

/// Get the repository path on disk
fn getRepoPath(allocator: std.mem.Allocator, username: []const u8, reponame: []const u8) ![]const u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    return std.fmt.allocPrint(allocator, "{s}/repos/{s}/{s}", .{ cwd, username, reponame });
}

/// Extract string value from simple JSON (avoids full JSON parser)
fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    var pattern_buf: [256]u8 = undefined;
    const pattern = std.fmt.bufPrint(&pattern_buf, "\"{s}\":\"", .{key}) catch return null;

    const start_idx = std.mem.indexOf(u8, json, pattern) orelse return null;
    const value_start = start_idx + pattern.len;

    const value_end = std.mem.indexOfPos(u8, json, value_start, "\"") orelse return null;

    return json[value_start..value_end];
}

/// Run a jj command and return stdout
fn runJjCommand(allocator: std.mem.Allocator, repo_path: []const u8, args: []const []const u8) ![]const u8 {
    var arg_list = std.ArrayList([]const u8){};
    defer arg_list.deinit(allocator);

    try arg_list.append(allocator, "jj");
    for (args) |arg| {
        try arg_list.append(allocator, arg);
    }

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = arg_list.items,
        .cwd = repo_path,
        .max_output_bytes = 10 * 1024 * 1024, // 10MB
    });
    defer allocator.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.JjCommandFailed;
    }

    return result.stdout;
}

/// Escape JSON string
fn escapeJson(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var escaped = std.ArrayList(u8){};
    errdefer escaped.deinit(allocator);

    for (input) |char| {
        switch (char) {
            '"' => try escaped.appendSlice(allocator, "\\\""),
            '\\' => try escaped.appendSlice(allocator, "\\\\"),
            '\n' => try escaped.appendSlice(allocator, "\\n"),
            '\r' => try escaped.appendSlice(allocator, "\\r"),
            '\t' => try escaped.appendSlice(allocator, "\\t"),
            else => try escaped.append(allocator, char),
        }
    }

    return escaped.toOwnedSlice(allocator);
}

// =============================================================================
// GET /:user/:repo/changes/:changeId/files - List files at change
// =============================================================================

pub fn getFilesAtChange(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId parameter\"}");
        return;
    };

    // Get path query parameter (optional, for subdirectories)
    const query_params = try req.query();
    const path_param = query_params.get("path") orelse "";

    // Get repository from database
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };
    _ = repo;

    // Get repository path on disk
    const repo_path = getRepoPath(allocator, username, reponame) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to access repository\"}");
        return;
    };
    defer allocator.free(repo_path);

    // Check if it's a jj workspace
    const repo_path_z = try allocator.dupeZ(u8, repo_path);
    defer allocator.free(repo_path_z);

    const is_jj = c.jj_is_jj_workspace(repo_path_z.ptr);

    var files: []const u8 = undefined;
    defer allocator.free(files);

    if (is_jj) {
        // Use jj-ffi to list files
        const workspace_result = c.jj_workspace_open(repo_path_z.ptr);
        defer {
            if (workspace_result.success) {
                c.jj_workspace_free(workspace_result.workspace);
            }
            if (workspace_result.error_message != null) {
                c.jj_string_free(workspace_result.error_message);
            }
        }

        if (!workspace_result.success) {
            res.status = 500;
            try res.writer().writeAll("{\"error\":\"Failed to open workspace\"}");
            return;
        }

        const change_id_z = try allocator.dupeZ(u8, change_id);
        defer allocator.free(change_id_z);

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
            res.status = 404;
            try res.writer().writeAll("{\"error\":\"Change not found or failed to list files\"}");
            return;
        }

        // Build JSON response
        var writer = res.writer();
        try writer.writeAll("{\"files\":[");

        const file_list = files_result.strings[0..files_result.len];
        var file_count: usize = 0;
        for (file_list) |file_ptr| {
            const file = std.mem.span(file_ptr);

            // Filter by path prefix if specified
            if (path_param.len > 0) {
                if (!std.mem.startsWith(u8, file, path_param)) {
                    continue;
                }
            }

            if (file_count > 0) try writer.writeAll(",");
            const escaped = try escapeJson(allocator, file);
            defer allocator.free(escaped);
            try writer.print("\"{s}\"", .{escaped});
            file_count += 1;
        }

        try writer.print("],\"path\":\"{s}\",\"total\":{d}}}", .{ path_param, file_count });
    } else {
        // Fallback: use jj CLI
        const args = if (path_param.len > 0)
            &[_][]const u8{ "file", "list", "-r", change_id, path_param }
        else
            &[_][]const u8{ "file", "list", "-r", change_id };

        files = runJjCommand(allocator, repo_path, args) catch {
            res.status = 500;
            try res.writer().writeAll("{\"error\":\"Failed to list files\"}");
            return;
        };

        // Build JSON response
        var writer = res.writer();
        try writer.writeAll("{\"files\":[");

        var lines = std.mem.splitScalar(u8, files, '\n');
        var file_count: usize = 0;
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;

            if (file_count > 0) try writer.writeAll(",");
            const escaped = try escapeJson(allocator, trimmed);
            defer allocator.free(escaped);
            try writer.print("\"{s}\"", .{escaped});
            file_count += 1;
        }

        try writer.print("],\"path\":\"{s}\",\"total\":{d}}}", .{ path_param, file_count });
    }
}

// =============================================================================
// GET /:user/:repo/changes/:changeId/file/* - Get file content at change
// =============================================================================

pub fn getFileAtChange(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId parameter\"}");
        return;
    };

    // Extract file path from URL after /file/
    const path = req.url.path;
    const file_marker = "/file/";
    const file_start_idx = std.mem.indexOf(u8, path, file_marker) orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid file path\"}");
        return;
    };
    const file_path = path[file_start_idx + file_marker.len ..];

    if (file_path.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing file path\"}");
        return;
    }

    // Get repository from database
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };
    _ = repo;

    // Get repository path on disk
    const repo_path = getRepoPath(allocator, username, reponame) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to access repository\"}");
        return;
    };
    defer allocator.free(repo_path);

    // Check if it's a jj workspace
    const repo_path_z = try allocator.dupeZ(u8, repo_path);
    defer allocator.free(repo_path_z);

    const is_jj = c.jj_is_jj_workspace(repo_path_z.ptr);

    var content: []const u8 = undefined;
    defer allocator.free(content);

    if (is_jj) {
        // Use jj-ffi to get file content
        const workspace_result = c.jj_workspace_open(repo_path_z.ptr);
        defer {
            if (workspace_result.success) {
                c.jj_workspace_free(workspace_result.workspace);
            }
            if (workspace_result.error_message != null) {
                c.jj_string_free(workspace_result.error_message);
            }
        }

        if (!workspace_result.success) {
            res.status = 500;
            try res.writer().writeAll("{\"error\":\"Failed to open workspace\"}");
            return;
        }

        const change_id_z = try allocator.dupeZ(u8, change_id);
        defer allocator.free(change_id_z);

        const file_path_z = try allocator.dupeZ(u8, file_path);
        defer allocator.free(file_path_z);

        const content_result = c.jj_get_file_content(workspace_result.workspace, change_id_z.ptr, file_path_z.ptr);
        defer {
            if (content_result.string != null) {
                c.jj_string_free(content_result.string);
            }
            if (content_result.error_message != null) {
                c.jj_string_free(content_result.error_message);
            }
        }

        if (!content_result.success) {
            res.status = 404;
            try res.writer().writeAll("{\"error\":\"File not found\"}");
            return;
        }

        const file_content = std.mem.span(content_result.string);
        const escaped = try escapeJson(allocator, file_content);
        defer allocator.free(escaped);

        const escaped_path = try escapeJson(allocator, file_path);
        defer allocator.free(escaped_path);

        var writer = res.writer();
        try writer.print("{{\"content\":\"{s}\",\"path\":\"{s}\"}}", .{ escaped, escaped_path });
    } else {
        // Fallback: use jj CLI
        const args = &[_][]const u8{ "file", "show", "-r", change_id, file_path };
        content = runJjCommand(allocator, repo_path, args) catch {
            res.status = 404;
            try res.writer().writeAll("{\"error\":\"File not found\"}");
            return;
        };

        const escaped = try escapeJson(allocator, content);
        defer allocator.free(escaped);

        const escaped_path = try escapeJson(allocator, file_path);
        defer allocator.free(escaped_path);

        var writer = res.writer();
        try writer.print("{{\"content\":\"{s}\",\"path\":\"{s}\"}}", .{ escaped, escaped_path });
    }
}

// =============================================================================
// GET /:user/:repo/changes/:fromChangeId/compare/:toChangeId - Compare changes
// =============================================================================

pub fn compareChanges(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const from_change_id = req.param("fromChangeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing fromChangeId parameter\"}");
        return;
    };

    const to_change_id = req.param("toChangeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing toChangeId parameter\"}");
        return;
    };

    // Get repository from database
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };
    _ = repo;

    // Get repository path on disk
    const repo_path = getRepoPath(allocator, username, reponame) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to access repository\"}");
        return;
    };
    defer allocator.free(repo_path);

    // Use jj CLI to get diff between changes
    const args = &[_][]const u8{ "diff", "--from", from_change_id, "--to", to_change_id, "--stat" };
    const diff_output = runJjCommand(allocator, repo_path, args) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to compare changes\"}");
        return;
    };
    defer allocator.free(diff_output);

    const escaped = try escapeJson(allocator, diff_output);
    defer allocator.free(escaped);

    var writer = res.writer();
    try writer.print("{{\"comparison\":{{\"from\":\"{s}\",\"to\":\"{s}\",\"diff\":\"{s}\"}}}}", .{
        from_change_id,
        to_change_id,
        escaped,
    });
}

// =============================================================================
// GET /:user/:repo/changes/:changeId/conflicts - List conflicts for a change
// =============================================================================

pub fn getConflicts(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId parameter\"}");
        return;
    };

    // Get repository from database (validate it exists)
    _ = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Get repository path on disk
    const repo_path = getRepoPath(allocator, username, reponame) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to access repository\"}");
        return;
    };
    defer allocator.free(repo_path);

    // Use jj CLI to list conflicts
    const args = &[_][]const u8{ "resolve", "--list", "-r", change_id };
    const conflicts_output = runJjCommand(allocator, repo_path, args) catch {
        // No conflicts or command failed - return empty list
        try res.writer().writeAll("{\"conflicts\":[]}");
        return;
    };
    defer allocator.free(conflicts_output);

    // Parse conflicts output and check DB for resolution status
    var conflicts_array = std.ArrayList(u8){};
    defer conflicts_array.deinit(allocator);

    var writer = conflicts_array.writer(allocator);
    try writer.writeAll("[");

    var lines = std.mem.splitScalar(u8, conflicts_output, '\n');
    var conflict_count: usize = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        // Parse conflict line (format varies but typically includes file path)
        // For now, treat each line as a conflicted file path
        if (conflict_count > 0) try writer.writeAll(",");

        const escaped_path = try escapeJson(allocator, trimmed);
        defer allocator.free(escaped_path);

        // Check DB for resolution status
        const row = ctx.pool.row(
            \\SELECT resolved, resolution_method, resolved_by
            \\FROM conflicts
            \\WHERE change_id = $1 AND file_path = $2
        , .{ change_id, trimmed }) catch null;

        if (row) |r| {
            const resolved = r.get(bool, 0);
            const method = r.get(?[]const u8, 1) orelse "unknown";
            const resolved_by = r.get(?i64, 2);

            try writer.print(
                \\{{"filePath":"{s}","resolved":{s},"resolutionMethod":"{s}","resolvedBy":{d}}}
            , .{ escaped_path, if (resolved) "true" else "false", method, resolved_by orelse 0 });
        } else {
            try writer.print(
                \\{{"filePath":"{s}","resolved":false}}
            , .{escaped_path});
        }

        conflict_count += 1;
    }

    try writer.writeAll("]");

    var response_writer = res.writer();
    try response_writer.print("{{\"conflicts\":{s}}}", .{conflicts_array.items});
}

// =============================================================================
// POST /:user/:repo/changes/:changeId/conflicts/:filePath/resolve - Resolve conflict
// =============================================================================

pub fn resolveConflict(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Unauthorized\"}");
        return;
    };

    const username = req.param("user") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing user parameter\"}");
        return;
    };

    const reponame = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const change_id = req.param("changeId") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing changeId parameter\"}");
        return;
    };

    const file_path = req.param("filePath") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing filePath parameter\"}");
        return;
    };

    // Parse body for resolution method
    const body = req.body() orelse "{\"method\":\"manual\"}";
    const method = extractJsonString(body, "method") orelse "manual";

    // Get repository from database
    const repo = db.getRepositoryByUserAndName(ctx.pool, username, reponame) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Record resolution in database
    _ = ctx.pool.exec(
        \\INSERT INTO conflicts (
        \\  repository_id, change_id, file_path, conflict_type,
        \\  resolved, resolved_by, resolution_method, resolved_at
        \\)
        \\VALUES ($1, $2, $3, 'content', true, $4, $5, NOW())
        \\ON CONFLICT (change_id, file_path) DO UPDATE SET
        \\  resolved = true,
        \\  resolved_by = EXCLUDED.resolved_by,
        \\  resolution_method = EXCLUDED.resolution_method,
        \\  resolved_at = EXCLUDED.resolved_at
    , .{ repo.id, change_id, file_path, user.id, method }) catch |err| {
        log.err("Failed to record conflict resolution: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to record resolution\"}");
        return;
    };

    try res.writer().writeAll("{\"success\":true}");
}
