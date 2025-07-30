# Complete API File Operations and Repository Contents

## Issue Found

The API implementation (Prompt 3) is missing critical file operations endpoints that are essential for web-based code browsing and editing. Without these, users cannot view or modify repository contents through the API.

## Current State vs Required

**What exists**:
- ✅ User/Organization/Repository CRUD
- ✅ Authentication endpoints
- ❌ File content retrieval
- ❌ File creation/update/deletion
- ❌ Directory listing
- ❌ Commit creation via API
- ❌ Branch/tag operations
- ❌ Diff and patch generation

**Evidence from Review**:
The implementation summary showed "File operations and contents API (browse, read, write)" was listed as NOT completed.

## Complete File Operations Implementation

### Get Repository Contents

```zig
const ContentsHandler = struct {
    pub fn getContents(r: zap.Request, ctx: *Context) !void {
        // GET /api/v1/repos/{owner}/{repo}/contents/{path}
        const owner = r.getRouteParam("owner") orelse return error.MissingParam;
        const repo_name = r.getRouteParam("repo") orelse return error.MissingParam;
        const path = r.getRouteParam("path") orelse "";
        const ref = r.getQuery("ref") orelse "main";
        
        // Get repository
        const repo = try ctx.dao.getRepositoryByName(ctx.allocator, owner, repo_name) orelse
            return sendJsonError(r, 404, "Repository not found");
        defer repo.deinit();
        
        // Check read access
        const auth = try authenticateRequest(r, ctx);
        if (!try hasReadAccess(ctx, auth.user_id, repo.id)) {
            return sendJsonError(r, 403, "Read access denied");
        }
        
        // Get repository path
        const repo_path = try getRepositoryPath(ctx.allocator, repo);
        defer ctx.allocator.free(repo_path);
        
        // Get git information
        var git_cmd = try GitCommand.init(ctx.allocator);
        defer git_cmd.deinit();
        
        // Check if path exists and get type
        const object_type = try getObjectType(&git_cmd, repo_path, ref, path);
        
        switch (object_type) {
            .file => try returnFileContent(r, ctx, &git_cmd, repo_path, ref, path),
            .directory => try returnDirectoryListing(r, ctx, &git_cmd, repo_path, ref, path),
            .not_found => return sendJsonError(r, 404, "Path not found"),
        }
    }
    
    fn returnFileContent(
        r: zap.Request,
        ctx: *Context,
        git_cmd: *GitCommand,
        repo_path: []const u8,
        ref: []const u8,
        path: []const u8,
    ) !void {
        // Get file content
        const show_result = try git_cmd.run(ctx.allocator, .{
            .args = &.{ "show", try std.fmt.allocPrint(ctx.allocator, "{s}:{s}", .{ ref, path }) },
            .cwd = repo_path,
        });
        defer show_result.deinit();
        
        // Get file info
        const ls_result = try git_cmd.run(ctx.allocator, .{
            .args = &.{ "ls-tree", "-l", ref, path },
            .cwd = repo_path,
        });
        defer ls_result.deinit();
        
        // Parse size from ls-tree output
        const size = try parseFileSize(ls_result.stdout);
        
        // Determine if content is binary
        const is_binary = isBinaryContent(show_result.stdout);
        
        // Base64 encode if binary or requested
        const encoding = if (is_binary or r.getQuery("encoding") != null) "base64" else "utf-8";
        const content = if (std.mem.eql(u8, encoding, "base64"))
            try base64Encode(ctx.allocator, show_result.stdout)
        else
            show_result.stdout;
        
        // Get last commit for this file
        const commit_info = try getLastCommit(git_cmd, repo_path, ref, path);
        defer commit_info.deinit();
        
        try r.sendJson(.{
            .type = "file",
            .encoding = encoding,
            .size = size,
            .name = std.fs.path.basename(path),
            .path = path,
            .content = content,
            .sha = try calculateGitBlobSha(ctx.allocator, show_result.stdout),
            .url = try std.fmt.allocPrint(ctx.allocator, "/api/v1/repos/{s}/{s}/contents/{s}", .{ owner, repo_name, path }),
            .git_url = try std.fmt.allocPrint(ctx.allocator, "/api/v1/repos/{s}/{s}/git/blobs/{s}", .{ owner, repo_name, sha }),
            .html_url = try std.fmt.allocPrint(ctx.allocator, "/{s}/{s}/blob/{s}/{s}", .{ owner, repo_name, ref, path }),
            .download_url = try std.fmt.allocPrint(ctx.allocator, "/{s}/{s}/raw/{s}/{s}", .{ owner, repo_name, ref, path }),
            ._links = .{
                .self = url,
                .git = git_url,
                .html = html_url,
            },
        });
    }
    
    fn returnDirectoryListing(
        r: zap.Request,
        ctx: *Context,
        git_cmd: *GitCommand,
        repo_path: []const u8,
        ref: []const u8,
        path: []const u8,
    ) !void {
        // List directory contents
        const ls_result = try git_cmd.run(ctx.allocator, .{
            .args = &.{ "ls-tree", "-l", ref, if (path.len > 0) path else "." },
            .cwd = repo_path,
        });
        defer ls_result.deinit();
        
        var entries = std.ArrayList(ContentEntry).init(ctx.allocator);
        defer entries.deinit();
        
        // Parse ls-tree output
        var lines = std.mem.tokenize(u8, ls_result.stdout, "\n");
        while (lines.next()) |line| {
            const entry = try parseLsTreeLine(ctx.allocator, line);
            defer entry.deinit();
            
            try entries.append(.{
                .type = if (entry.mode[0] == '1') "file" else if (entry.mode[0] == '4') "dir" else "submodule",
                .size = if (entry.size) |s| s else 0,
                .name = entry.name,
                .path = if (path.len > 0)
                    try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ path, entry.name })
                else
                    entry.name,
                .sha = entry.sha,
                .url = try std.fmt.allocPrint(ctx.allocator, "/api/v1/repos/{s}/{s}/contents/{s}", .{
                    owner, repo_name, entry.path
                }),
                .git_url = try std.fmt.allocPrint(ctx.allocator, "/api/v1/repos/{s}/{s}/git/{s}/{s}", .{
                    owner, repo_name,
                    if (entry.type == .file) "blobs" else "trees",
                    entry.sha
                }),
                .html_url = try std.fmt.allocPrint(ctx.allocator, "/{s}/{s}/{s}/{s}/{s}", .{
                    owner, repo_name,
                    if (entry.type == .file) "blob" else "tree",
                    ref, entry.path
                }),
                .download_url = if (entry.type == .file)
                    try std.fmt.allocPrint(ctx.allocator, "/{s}/{s}/raw/{s}/{s}", .{
                        owner, repo_name, ref, entry.path
                    })
                else
                    null,
            });
        }
        
        try r.sendJson(entries.items);
    }
};
```

### Create or Update File Contents

```zig
const FileUpdateHandler = struct {
    pub fn createOrUpdateFile(r: zap.Request, ctx: *Context) !void {
        // PUT /api/v1/repos/{owner}/{repo}/contents/{path}
        const owner = r.getRouteParam("owner") orelse return error.MissingParam;
        const repo_name = r.getRouteParam("repo") orelse return error.MissingParam;
        const path = r.getRouteParam("path") orelse return error.MissingParam;
        
        const body = try r.readJsonAlloc(ctx.allocator, UpdateFileRequest, .{});
        defer body.deinit();
        
        // Get repository and check write access
        const repo = try ctx.dao.getRepositoryByName(ctx.allocator, owner, repo_name) orelse
            return sendJsonError(r, 404, "Repository not found");
        defer repo.deinit();
        
        const auth = try authenticateRequest(r, ctx);
        if (!try hasWriteAccess(ctx, auth.user_id, repo.id)) {
            return sendJsonError(r, 403, "Write access denied");
        }
        
        const repo_path = try getRepositoryPath(ctx.allocator, repo);
        defer ctx.allocator.free(repo_path);
        
        var git_cmd = try GitCommand.init(ctx.allocator);
        defer git_cmd.deinit();
        
        // Decode content if base64
        const content = if (std.mem.eql(u8, body.value.encoding orelse "utf-8", "base64"))
            try base64Decode(ctx.allocator, body.value.content)
        else
            body.value.content;
        defer if (body.value.encoding != null) ctx.allocator.free(content);
        
        // If updating, verify SHA matches
        if (body.value.sha) |expected_sha| {
            const current_exists = try fileExists(&git_cmd, repo_path, body.value.branch, path);
            if (!current_exists) {
                return sendJsonError(r, 404, "File not found for update");
            }
            
            const current_content = try getFileContent(&git_cmd, repo_path, body.value.branch, path);
            defer ctx.allocator.free(current_content);
            
            const current_sha = try calculateGitBlobSha(ctx.allocator, current_content);
            defer ctx.allocator.free(current_sha);
            
            if (!std.mem.eql(u8, current_sha, expected_sha)) {
                return sendJsonError(r, 409, "SHA mismatch - file was modified");
            }
        }
        
        // Create temporary directory for operation
        const temp_dir = try createTempWorkDir(ctx.allocator);
        defer cleanupTempDir(temp_dir);
        
        // Clone repository (sparse checkout for performance)
        try sparseCheckout(&git_cmd, repo_path, temp_dir, body.value.branch, path);
        
        // Write new content
        const file_path = try std.fs.path.join(ctx.allocator, &.{ temp_dir, path });
        defer ctx.allocator.free(file_path);
        
        // Ensure parent directories exist
        try std.fs.cwd().makePath(std.fs.path.dirname(file_path) orelse ".");
        
        const file = try std.fs.createFileAbsolute(file_path, .{});
        defer file.close();
        try file.writeAll(content);
        
        // Stage the file
        _ = try git_cmd.run(ctx.allocator, .{
            .args = &.{ "add", path },
            .cwd = temp_dir,
        });
        
        // Create commit
        const commit_result = try git_cmd.run(ctx.allocator, .{
            .args = &.{
                "commit",
                "-m", body.value.message,
                "--author", try std.fmt.allocPrint(ctx.allocator, "{s} <{s}>", .{
                    body.value.committer.name,
                    body.value.committer.email,
                }),
            },
            .cwd = temp_dir,
            .env = &.{
                .{ .name = "GIT_COMMITTER_NAME", .value = body.value.committer.name },
                .{ .name = "GIT_COMMITTER_EMAIL", .value = body.value.committer.email },
            },
        });
        defer commit_result.deinit();
        
        // Push changes
        _ = try git_cmd.run(ctx.allocator, .{
            .args = &.{ "push", "origin", body.value.branch },
            .cwd = temp_dir,
        });
        
        // Get new file info
        const new_sha = try calculateGitBlobSha(ctx.allocator, content);
        const commit_sha = try getLastCommitSha(&git_cmd, temp_dir);
        
        // Return response
        try r.sendJson(.{
            .content = .{
                .name = std.fs.path.basename(path),
                .path = path,
                .sha = new_sha,
                .size = content.len,
                .url = try std.fmt.allocPrint(ctx.allocator, "/api/v1/repos/{s}/{s}/contents/{s}", .{
                    owner, repo_name, path
                }),
                .html_url = try std.fmt.allocPrint(ctx.allocator, "/{s}/{s}/blob/{s}/{s}", .{
                    owner, repo_name, body.value.branch, path
                }),
                .git_url = try std.fmt.allocPrint(ctx.allocator, "/api/v1/repos/{s}/{s}/git/blobs/{s}", .{
                    owner, repo_name, new_sha
                }),
                .download_url = try std.fmt.allocPrint(ctx.allocator, "/{s}/{s}/raw/{s}/{s}", .{
                    owner, repo_name, body.value.branch, path
                }),
                .type = "file",
            },
            .commit = .{
                .sha = commit_sha,
                .author = body.value.author orelse body.value.committer,
                .committer = body.value.committer,
                .message = body.value.message,
                .url = try std.fmt.allocPrint(ctx.allocator, "/api/v1/repos/{s}/{s}/git/commits/{s}", .{
                    owner, repo_name, commit_sha
                }),
            },
        });
    }
    
    const UpdateFileRequest = struct {
        message: []const u8,
        content: []const u8,
        sha: ?[]const u8 = null, // Required for updates
        branch: []const u8 = "main",
        encoding: ?[]const u8 = null, // "utf-8" or "base64"
        committer: struct {
            name: []const u8,
            email: []const u8,
        },
        author: ?struct {
            name: []const u8,
            email: []const u8,
        } = null,
    };
};
```

### Delete File Contents

```zig
pub fn deleteFile(r: zap.Request, ctx: *Context) !void {
    // DELETE /api/v1/repos/{owner}/{repo}/contents/{path}
    const owner = r.getRouteParam("owner") orelse return error.MissingParam;
    const repo_name = r.getRouteParam("repo") orelse return error.MissingParam;
    const path = r.getRouteParam("path") orelse return error.MissingParam;
    
    const body = try r.readJsonAlloc(ctx.allocator, DeleteFileRequest, .{});
    defer body.deinit();
    
    // Similar access control and setup as create/update...
    
    // Verify file exists and SHA matches
    const current_content = try getFileContent(&git_cmd, repo_path, body.value.branch, path);
    defer ctx.allocator.free(current_content);
    
    const current_sha = try calculateGitBlobSha(ctx.allocator, current_content);
    defer ctx.allocator.free(current_sha);
    
    if (!std.mem.eql(u8, current_sha, body.value.sha)) {
        return sendJsonError(r, 409, "SHA mismatch - file was modified");
    }
    
    // Remove file and commit
    _ = try git_cmd.run(ctx.allocator, .{
        .args = &.{ "rm", path },
        .cwd = temp_dir,
    });
    
    _ = try git_cmd.run(ctx.allocator, .{
        .args = &.{
            "commit",
            "-m", body.value.message,
            "--author", try std.fmt.allocPrint(ctx.allocator, "{s} <{s}>", .{
                body.value.committer.name,
                body.value.committer.email,
            }),
        },
        .cwd = temp_dir,
    });
    
    // Push and return commit info
    _ = try git_cmd.run(ctx.allocator, .{
        .args = &.{ "push", "origin", body.value.branch },
        .cwd = temp_dir,
    });
    
    try r.sendJson(.{
        .content = null,
        .commit = .{
            .sha = commit_sha,
            .message = body.value.message,
            // ... other commit fields
        },
    });
}
```

### Get Raw File Content

```zig
pub fn getRawContent(r: zap.Request, ctx: *Context) !void {
    // GET /api/v1/repos/{owner}/{repo}/raw/{ref}/{path}
    const owner = r.getRouteParam("owner") orelse return error.MissingParam;
    const repo_name = r.getRouteParam("repo") orelse return error.MissingParam;
    const ref = r.getRouteParam("ref") orelse "main";
    const path = r.getRouteParam("path") orelse return error.MissingParam;
    
    // Access control...
    
    var git_cmd = try GitCommand.init(ctx.allocator);
    defer git_cmd.deinit();
    
    const content_result = try git_cmd.run(ctx.allocator, .{
        .args = &.{ "show", try std.fmt.allocPrint(ctx.allocator, "{s}:{s}", .{ ref, path }) },
        .cwd = repo_path,
    });
    defer content_result.deinit();
    
    if (content_result.exit_code != 0) {
        return sendError(r, 404, "File not found");
    }
    
    // Detect content type
    const content_type = detectContentType(path, content_result.stdout);
    
    r.setStatus(200);
    r.setHeader("Content-Type", content_type);
    r.setHeader("Content-Length", try std.fmt.allocPrint(ctx.allocator, "{}", .{content_result.stdout.len}));
    r.setHeader("Cache-Control", "max-age=300");
    
    try r.sendBody(content_result.stdout);
}
```

## Implementation Steps

### Phase 1: Read Operations
1. Implement getContents for files and directories
2. Add getRawContent endpoint
3. Implement helper functions for Git operations
4. Add content type detection

### Phase 2: Write Operations  
1. Implement create/update file endpoint
2. Add delete file endpoint
3. Implement Git commit creation
4. Add sparse checkout optimization

### Phase 3: Advanced Features
1. Branch and tag listing endpoints
2. Commit comparison and diffs
3. File history endpoint
4. Blame information API

### Phase 4: Performance and Security
1. Add caching for read operations
2. Implement rate limiting
3. Add virus scanning for uploads
4. Optimize for large files

## Test Requirements

```zig
test "complete file operation cycle" {
    // Create file
    const create_response = try createFile(client, "test-repo", "test.md", "# Hello");
    try testing.expectEqual(@as(u16, 201), create_response.status);
    
    // Read file
    const read_response = try getContents(client, "test-repo", "test.md");
    try testing.expectEqualStrings("# Hello", read_response.content);
    
    // Update file
    const update_response = try updateFile(
        client,
        "test-repo", 
        "test.md",
        "# Hello\n\nUpdated content",
        read_response.sha
    );
    try testing.expectEqual(@as(u16, 200), update_response.status);
    
    // Delete file
    const delete_response = try deleteFile(
        client,
        "test-repo",
        "test.md", 
        update_response.content.sha
    );
    try testing.expectEqual(@as(u16, 200), delete_response.status);
}
```

## Priority: HIGH

File operations are essential for:
- Web-based code browsing
- Online editing capabilities
- API-based automation
- Integration with IDEs and tools
- Building a complete GitHub-compatible API

## Estimated Effort: 5-6 days