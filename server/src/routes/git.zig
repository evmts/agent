//! Git routes - REST API for SHA-based content serving with HTTP caching
//!
//! Implements content-addressable git content serving with proper cache headers:
//! - Refs (branches, tags) resolve to commit SHAs with short cache (5s)
//! - Trees and blobs by SHA are immutable (cache forever)

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("../lib/db.zig");

const log = std.log.scoped(.git_routes);

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

/// Set immutable cache headers for SHA-based content
fn setImmutableCacheHeaders(res: *httpz.Response, sha: []const u8) void {
    res.headers.add("Cache-Control", "public, max-age=31536000, immutable");
    res.headers.add("ETag", sha);
}

/// Set short cache headers for mutable refs
fn setRefCacheHeaders(res: *httpz.Response) void {
    res.headers.add("Cache-Control", "public, max-age=5");
}

/// Check if request has matching ETag (304 Not Modified)
fn checkEtagMatch(req: *httpz.Request, sha: []const u8) bool {
    if (req.headers.get("If-None-Match")) |etag| {
        // Handle quoted ETags
        const unquoted = if (etag.len >= 2 and etag[0] == '"' and etag[etag.len - 1] == '"')
            etag[1 .. etag.len - 1]
        else
            etag;
        return std.mem.eql(u8, unquoted, sha);
    }
    return false;
}

// =============================================================================
// GET /api/:owner/:repo/refs/:ref - Resolve ref to commit SHA
// =============================================================================

pub fn resolveRef(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const owner = req.param("owner") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing owner parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const ref = req.param("ref") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing ref parameter\"}");
        return;
    };

    // Validate repository exists in database
    _ = db.getRepositoryByUserAndName(ctx.pool, owner, repo_name) catch |err| {
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
    const repo_path = getRepoPath(allocator, owner, repo_name) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to access repository\"}");
        return;
    };
    defer allocator.free(repo_path);

    const repo_path_z = try allocator.dupeZ(u8, repo_path);
    defer allocator.free(repo_path_z);

    // Open workspace and resolve ref
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

    const ref_z = try allocator.dupeZ(u8, ref);
    defer allocator.free(ref_z);

    // Use jj to resolve the ref to a commit
    const commit_result = c.jj_get_commit(workspace_result.workspace, ref_z.ptr);
    defer {
        if (commit_result.success) {
            c.jj_commit_info_free(commit_result.commit);
        }
        if (commit_result.error_message != null) {
            c.jj_string_free(commit_result.error_message);
        }
    }

    if (!commit_result.success) {
        // Try fallback with jj CLI
        const args = &[_][]const u8{ "log", "-r", ref, "--no-graph", "-T", "commit_id", "-l", "1" };
        const output = runJjCommand(allocator, repo_path, args) catch {
            res.status = 404;
            try res.writer().writeAll("{\"error\":\"Ref not found\"}");
            return;
        };
        defer allocator.free(output);

        const trimmed = std.mem.trim(u8, output, &std.ascii.whitespace);
        if (trimmed.len == 0) {
            res.status = 404;
            try res.writer().writeAll("{\"error\":\"Ref not found\"}");
            return;
        }

        // Set short cache for refs (they're mutable)
        setRefCacheHeaders(res);

        const escaped = try escapeJson(allocator, trimmed);
        defer allocator.free(escaped);
        try res.writer().print("{{\"commit\":\"{s}\"}}", .{escaped});
        return;
    }

    // Set short cache for refs (they're mutable)
    setRefCacheHeaders(res);

    const commit_id = std.mem.span(commit_result.commit.*.id);
    const escaped = try escapeJson(allocator, commit_id);
    defer allocator.free(escaped);
    try res.writer().print("{{\"commit\":\"{s}\"}}", .{escaped});
}

// =============================================================================
// GET /api/:owner/:repo/tree/:sha/:path? - Get tree by commit SHA
// =============================================================================

pub fn getTreeBySha(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const owner = req.param("owner") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing owner parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const sha = req.param("sha") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sha parameter\"}");
        return;
    };

    // Extract optional path from URL (after /tree/:sha/)
    const url_path = req.url.path;
    var path: []const u8 = "";

    // Find /tree/:sha/ pattern and extract path after it
    if (std.mem.indexOf(u8, url_path, "/tree/")) |tree_idx| {
        const after_tree = url_path[tree_idx + 6 ..]; // Skip "/tree/"
        // Find the next / after the SHA
        if (std.mem.indexOf(u8, after_tree, "/")) |slash_idx| {
            path = after_tree[slash_idx + 1 ..];
        }
    }

    // Validate repository exists
    _ = db.getRepositoryByUserAndName(ctx.pool, owner, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Check ETag for 304 response BEFORE doing any work
    if (checkEtagMatch(req, sha)) {
        res.status = 304;
        setImmutableCacheHeaders(res, sha);
        return;
    }

    // Get repository path
    const repo_path = getRepoPath(allocator, owner, repo_name) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to access repository\"}");
        return;
    };
    defer allocator.free(repo_path);

    const repo_path_z = try allocator.dupeZ(u8, repo_path);
    defer allocator.free(repo_path_z);

    // Open workspace
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

    const sha_z = try allocator.dupeZ(u8, sha);
    defer allocator.free(sha_z);

    // List files at the commit SHA
    const files_result = c.jj_list_files(workspace_result.workspace, sha_z.ptr);
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
        try res.writer().writeAll("{\"error\":\"Commit not found\"}");
        return;
    }

    // Set immutable cache headers - SHA-based content never changes
    setImmutableCacheHeaders(res, sha);

    // Build tree entries from file list
    var writer = res.writer();
    try writer.writeAll("{\"entries\":[");

    const file_list = files_result.strings[0..files_result.len];
    var entry_count: usize = 0;

    // Build a set of directories we've seen at this path level
    var seen_dirs = std.StringHashMap(void).init(allocator);
    defer seen_dirs.deinit();

    for (file_list) |file_ptr| {
        const file = std.mem.span(file_ptr);

        // Filter by path prefix if specified
        if (path.len > 0) {
            if (!std.mem.startsWith(u8, file, path)) {
                continue;
            }
        }

        // Get the relative path after the prefix
        const relative = if (path.len > 0 and std.mem.startsWith(u8, file, path))
            file[path.len..]
        else
            file;

        // Skip leading slash
        const clean_relative = if (relative.len > 0 and relative[0] == '/')
            relative[1..]
        else
            relative;

        if (clean_relative.len == 0) continue;

        // Check if this is a direct child or in a subdirectory
        if (std.mem.indexOf(u8, clean_relative, "/")) |slash_idx| {
            // This is in a subdirectory - add the directory entry
            const dir_name = clean_relative[0..slash_idx];
            if (!seen_dirs.contains(dir_name)) {
                try seen_dirs.put(dir_name, {});

                if (entry_count > 0) try writer.writeAll(",");
                const escaped_name = try escapeJson(allocator, dir_name);
                defer allocator.free(escaped_name);
                try writer.print("{{\"name\":\"{s}\",\"type\":\"tree\",\"path\":\"{s}{s}{s}\"}}", .{
                    escaped_name,
                    path,
                    if (path.len > 0 and path[path.len - 1] != '/') "/" else "",
                    escaped_name,
                });
                entry_count += 1;
            }
        } else {
            // This is a direct file
            if (entry_count > 0) try writer.writeAll(",");
            const escaped_name = try escapeJson(allocator, clean_relative);
            defer allocator.free(escaped_name);
            try writer.print("{{\"name\":\"{s}\",\"type\":\"blob\",\"path\":\"{s}\"}}", .{
                escaped_name,
                file,
            });
            entry_count += 1;
        }
    }

    try writer.print("],\"path\":\"{s}\",\"sha\":\"{s}\",\"total\":{d}}}", .{ path, sha, entry_count });
}

// =============================================================================
// GET /api/:owner/:repo/blob/:sha/:path - Get blob by commit SHA
// =============================================================================

pub fn getBlobBySha(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const owner = req.param("owner") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing owner parameter\"}");
        return;
    };

    const repo_name = req.param("repo") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repo parameter\"}");
        return;
    };

    const sha = req.param("sha") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing sha parameter\"}");
        return;
    };

    // Extract file path from URL (after /blob/:sha/)
    const url_path = req.url.path;
    const blob_marker = "/blob/";
    const blob_start_idx = std.mem.indexOf(u8, url_path, blob_marker) orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid blob path\"}");
        return;
    };

    const after_blob = url_path[blob_start_idx + blob_marker.len ..];
    // Skip the SHA and get the file path
    const file_path = if (std.mem.indexOf(u8, after_blob, "/")) |slash_idx|
        after_blob[slash_idx + 1 ..]
    else
        "";

    if (file_path.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing file path\"}");
        return;
    }

    // Validate repository exists
    _ = db.getRepositoryByUserAndName(ctx.pool, owner, repo_name) catch |err| {
        log.err("Failed to get repository: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal server error\"}");
        return;
    } orelse {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"Repository not found\"}");
        return;
    };

    // Check ETag for 304 response BEFORE doing any work
    if (checkEtagMatch(req, sha)) {
        res.status = 304;
        setImmutableCacheHeaders(res, sha);
        return;
    }

    // Get repository path
    const repo_path = getRepoPath(allocator, owner, repo_name) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to access repository\"}");
        return;
    };
    defer allocator.free(repo_path);

    const repo_path_z = try allocator.dupeZ(u8, repo_path);
    defer allocator.free(repo_path_z);

    // Open workspace
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

    const sha_z = try allocator.dupeZ(u8, sha);
    defer allocator.free(sha_z);

    const file_path_z = try allocator.dupeZ(u8, file_path);
    defer allocator.free(file_path_z);

    // Get file content
    const content_result = c.jj_get_file_content(workspace_result.workspace, sha_z.ptr, file_path_z.ptr);
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

    // Set immutable cache headers - SHA-based content never changes
    setImmutableCacheHeaders(res, sha);

    const file_content = std.mem.span(content_result.string);
    const escaped_content = try escapeJson(allocator, file_content);
    defer allocator.free(escaped_content);

    const escaped_path = try escapeJson(allocator, file_path);
    defer allocator.free(escaped_path);

    var writer = res.writer();
    try writer.print("{{\"content\":\"{s}\",\"path\":\"{s}\",\"sha\":\"{s}\"}}", .{
        escaped_content,
        escaped_path,
        sha,
    });
}
