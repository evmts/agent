const std = @import("std");
const zap = @import("zap");
const server = @import("../server.zig");
const json = @import("../utils/json.zig");
const auth = @import("../utils/auth.zig");
const GitCommand = @import("../../git/command.zig").GitCommand;

const Context = server.Context;
const Repository = server.DataAccessObject.Repository;

// Content entry structure for directory listings
const ContentEntry = struct {
    type: []const u8, // "file", "dir", "submodule"
    size: u64,
    name: []const u8,
    path: []const u8,
    sha: []const u8,
    url: []const u8,
    git_url: []const u8,
    html_url: []const u8,
    download_url: ?[]const u8,
    _links: struct {
        self: []const u8,
        git: []const u8,
        html: []const u8,
    },
};

// File content response structure
const FileContent = struct {
    type: []const u8,
    encoding: []const u8,
    size: u64,
    name: []const u8,
    path: []const u8,
    content: []const u8,
    sha: []const u8,
    url: []const u8,
    git_url: []const u8,
    html_url: []const u8,
    download_url: []const u8,
    _links: struct {
        self: []const u8,
        git: []const u8,
        html: []const u8,
    },
};

const ObjectType = enum {
    file,
    directory,
    not_found,
};

const LsTreeEntry = struct {
    mode: []const u8,
    type: []const u8,
    sha: []const u8,
    size: ?u64,
    name: []const u8,
    
    pub fn deinit(self: *LsTreeEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.mode);
        allocator.free(self.type);
        allocator.free(self.sha);
        allocator.free(self.name);
    }
};

// Request/Response types for file operations
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

const DeleteFileRequest = struct {
    message: []const u8,
    sha: []const u8, // Required for deletes
    branch: []const u8 = "main",
    committer: struct {
        name: []const u8,
        email: []const u8,
    },
    author: ?struct {
        name: []const u8,
        email: []const u8,
    } = null,
};

const CreateFileResponse = struct {
    content: struct {
        name: []const u8,
        path: []const u8,
        sha: []const u8,
        size: u64,
        url: []const u8,
        html_url: []const u8,
        git_url: []const u8,
        download_url: []const u8,
        type: []const u8,
    },
    commit: struct {
        sha: []const u8,
        author: struct {
            name: []const u8,
            email: []const u8,
        },
        committer: struct {
            name: []const u8,
            email: []const u8,
        },
        message: []const u8,
        url: []const u8,
    },
};

const DeleteFileResponse = struct {
    content: ?struct {} = null,
    commit: struct {
        sha: []const u8,
        author: struct {
            name: []const u8,
            email: []const u8,
        },
        committer: struct {
            name: []const u8,
            email: []const u8,
        },
        message: []const u8,
        url: []const u8,
    },
};

// GET /repos/{owner}/{repo}/contents/{path}
pub fn getContentsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Parse path parameters
    const path = r.path orelse return error.NoPath;
    var parts = try parseContentsPath(allocator, path);
    defer parts.deinit(allocator);
    
    const owner_name = parts.owner;
    const repo_name = parts.repo;
    const file_path = parts.file_path;
    const ref = "main"; // TODO: Parse query parameters properly
    
    // Get repository
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check read access (for now, assume public repos are readable)
    // TODO: Implement proper access control based on repository visibility
    
    // Get repository path
    const repo_path = try getRepositoryPath(allocator, &repo);
    defer allocator.free(repo_path);
    
    // Initialize git command
    const git_exe_path = ctx.config.repository.git_executable_path;
    var git_cmd = try GitCommand.init(allocator, git_exe_path);
    defer git_cmd.deinit(allocator);
    
    // Check if path exists and determine type
    const object_type = try getObjectType(allocator, &git_cmd, repo_path, ref, file_path);
    
    switch (object_type) {
        .file => try returnFileContent(r, ctx, &git_cmd, repo_path, ref, file_path, owner_name, repo_name),
        .directory => try returnDirectoryListing(r, ctx, &git_cmd, repo_path, ref, file_path, owner_name, repo_name),
        .not_found => {
            try json.writeError(r, allocator, .not_found, "Path not found");
            return;
        },
    }
}

// GET /repos/{owner}/{repo}/raw/{ref}/{path}
pub fn getRawContentHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Parse path parameters
    const path = r.path orelse return error.NoPath;
    var parts = try parseRawPath(allocator, path);
    defer parts.deinit(allocator);
    
    const owner_name = parts.owner;
    const repo_name = parts.repo;
    const ref = parts.ref;
    const file_path = parts.file_path;
    
    // Get repository (similar access control as above)
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        r.setStatus(.internal_server_error);
        try r.sendBody("Database error");
        return;
    } orelse {
        r.setStatus(.not_found);
        try r.sendBody("Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        r.setStatus(.internal_server_error);
        try r.sendBody("Database error");
        return;
    } orelse {
        r.setStatus(.not_found);
        try r.sendBody("Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get repository path
    const repo_path = try getRepositoryPath(allocator, &repo);
    defer allocator.free(repo_path);
    
    // Initialize git command
    const git_exe_path = ctx.config.repository.git_executable_path;
    var git_cmd = try GitCommand.init(allocator, git_exe_path);
    defer git_cmd.deinit(allocator);
    
    // Get file content
    const git_ref_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ref, file_path });
    defer allocator.free(git_ref_path);
    
    var result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "show", git_ref_path },
        .cwd = repo_path,
    });
    defer result.deinit(allocator);
    
    if (result.exit_code != 0) {
        r.setStatus(.not_found);
        try r.sendBody("File not found");
        return;
    }
    
    // Detect content type
    const content_type = detectContentType(file_path, result.stdout);
    
    r.setStatus(.ok);
    r.setHeader("Content-Type", content_type) catch {};
    r.setHeader("Content-Length", try std.fmt.allocPrint(allocator, "{}", .{result.stdout.len})) catch {};
    r.setHeader("Cache-Control", "max-age=300") catch {};
    
    try r.sendBody(result.stdout);
}

// PUT /repos/{owner}/{repo}/contents/{path}
pub fn createOrUpdateFileHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Parse path parameters
    const path = r.path orelse return error.NoPath;
    var parts = try parseContentsPath(allocator, path);
    defer parts.deinit(allocator);
    
    const owner_name = parts.owner;
    const repo_name = parts.repo;
    const file_path = parts.file_path;
    
    // Parse request body
    const body_text = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    var parsed = std.json.parseFromSlice(UpdateFileRequest, allocator, body_text, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    const body = parsed.value;
    
    // Get repository and check write access
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // TODO: Check write access based on authentication
    // For now, assume access is allowed for basic functionality
    
    // Get repository path
    const repo_path = try getRepositoryPath(allocator, &repo);
    defer allocator.free(repo_path);
    
    // Initialize git command
    const git_exe_path = ctx.config.repository.git_executable_path;
    var git_cmd = try GitCommand.init(allocator, git_exe_path);
    defer git_cmd.deinit(allocator);
    
    // Decode content if base64
    const content = if (body.encoding) |enc| blk: {
        if (std.mem.eql(u8, enc, "base64")) {
            break :blk try base64Decode(allocator, body.content);
        } else {
            break :blk try allocator.dupe(u8, body.content);
        }
    } else try allocator.dupe(u8, body.content);
    defer allocator.free(content);
    
    // If updating, verify SHA matches current file
    const is_update = body.sha != null;
    if (is_update) {
        const current_exists = try fileExists(&git_cmd, repo_path, body.branch, file_path);
        if (!current_exists) {
            try json.writeError(r, allocator, .not_found, "File not found for update");
            return;
        }
        
        const current_content = try getFileContent(&git_cmd, repo_path, body.branch, file_path);
        defer allocator.free(current_content);
        
        const current_sha = try calculateGitBlobSha(allocator, current_content);
        defer allocator.free(current_sha);
        
        if (!std.mem.eql(u8, current_sha, body.sha.?)) {
            try json.writeError(r, allocator, .conflict, "SHA mismatch - file was modified");
            return;
        }
    }
    
    // Create temporary working directory
    const temp_dir = try std.fmt.allocPrint(allocator, "/tmp/plue_edit_{}", .{std.time.timestamp()});
    defer allocator.free(temp_dir);
    defer std.fs.cwd().deleteTree(temp_dir) catch {};
    
    // Clone repository to temp directory
    try cloneRepositoryForEdit(&git_cmd, repo_path, temp_dir, body.branch);
    
    // Write new content to file
    const full_file_path = try std.fs.path.join(allocator, &.{ temp_dir, file_path });
    defer allocator.free(full_file_path);
    
    // Ensure parent directories exist
    if (std.fs.path.dirname(full_file_path)) |parent_dir| {
        try std.fs.cwd().makePath(parent_dir);
    }
    
    const file = try std.fs.cwd().createFile(full_file_path, .{});
    defer file.close();
    try file.writeAll(content);
    
    // Stage the file
    var stage_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "add", file_path },
        .cwd = temp_dir,
    });
    defer stage_result.deinit(allocator);
    
    if (stage_result.exit_code != 0) {
        std.log.err("Failed to stage file: {s}", .{stage_result.stderr});
        try json.writeError(r, allocator, .internal_server_error, "Failed to stage file");
        return;
    }
    
    // Create commit
    const commit_message = body.message;
    const author_name = body.author.?.name;
    const author_email = body.author.?.email;
    const committer_name = body.committer.name;
    const committer_email = body.committer.email;
    
    var commit_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{
            "commit",
            "-m", commit_message,
            "--author", try std.fmt.allocPrint(allocator, "{s} <{s}>", .{ author_name, author_email }),
        },
        .cwd = temp_dir,
        .env = &.{
            .{ .name = "GIT_COMMITTER_NAME", .value = committer_name },
            .{ .name = "GIT_COMMITTER_EMAIL", .value = committer_email },
        },
    });
    defer commit_result.deinit(allocator);
    
    if (commit_result.exit_code != 0) {
        std.log.err("Failed to create commit: {s}", .{commit_result.stderr});
        try json.writeError(r, allocator, .internal_server_error, "Failed to create commit");
        return;
    }
    
    // Push changes back to main repository
    var push_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "push", "origin", body.branch },
        .cwd = temp_dir,
    });
    defer push_result.deinit(allocator);
    
    if (push_result.exit_code != 0) {
        std.log.err("Failed to push changes: {s}", .{push_result.stderr});
        try json.writeError(r, allocator, .internal_server_error, "Failed to push changes");
        return;
    }
    
    // Get new file info
    const new_sha = try calculateGitBlobSha(allocator, content);
    defer allocator.free(new_sha);
    
    const commit_sha = try getLastCommitSha(&git_cmd, temp_dir);
    defer allocator.free(commit_sha);
    
    // Build response
    const response = CreateFileResponse{
        .content = .{
            .name = std.fs.path.basename(file_path),
            .path = file_path,
            .sha = new_sha,
            .size = content.len,
            .url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/contents/{s}", .{ owner_name, repo_name, file_path }),
            .html_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/blob/{s}/{s}", .{ owner_name, repo_name, body.branch, file_path }),
            .git_url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/git/blobs/{s}", .{ owner_name, repo_name, new_sha }),
            .download_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/raw/{s}/{s}", .{ owner_name, repo_name, body.branch, file_path }),
            .type = "file",
        },
        .commit = .{
            .sha = commit_sha,
            .author = .{
                .name = author_name,
                .email = author_email,
            },
            .committer = .{
                .name = committer_name,
                .email = committer_email,
            },
            .message = commit_message,
            .url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/git/commits/{s}", .{ owner_name, repo_name, commit_sha }),
        },
    };
    
    const status_code: u16 = if (is_update) 200 else 201;
    r.setStatus(@enumFromInt(status_code));
    try json.writeJson(r, allocator, response);
}

// DELETE /repos/{owner}/{repo}/contents/{path}
pub fn deleteFileHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Parse path parameters
    const path = r.path orelse return error.NoPath;
    var parts = try parseContentsPath(allocator, path);
    defer parts.deinit(allocator);
    
    const owner_name = parts.owner;
    const repo_name = parts.repo;
    const file_path = parts.file_path;
    
    // Parse request body
    const body_text = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    var parsed = std.json.parseFromSlice(DeleteFileRequest, allocator, body_text, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    const body = parsed.value;
    
    // Get repository (similar access control as create/update)
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get repository path
    const repo_path = try getRepositoryPath(allocator, &repo);
    defer allocator.free(repo_path);
    
    // Initialize git command
    const git_exe_path = ctx.config.repository.git_executable_path;
    var git_cmd = try GitCommand.init(allocator, git_exe_path);
    defer git_cmd.deinit(allocator);
    
    // Verify file exists and SHA matches
    const current_content = try getFileContent(&git_cmd, repo_path, body.branch, file_path);
    defer allocator.free(current_content);
    
    const current_sha = try calculateGitBlobSha(allocator, current_content);
    defer allocator.free(current_sha);
    
    if (!std.mem.eql(u8, current_sha, body.sha)) {
        try json.writeError(r, allocator, .conflict, "SHA mismatch - file was modified");
        return;
    }
    
    // Create temporary working directory
    const temp_dir = try std.fmt.allocPrint(allocator, "/tmp/plue_delete_{}", .{std.time.timestamp()});
    defer allocator.free(temp_dir);
    defer std.fs.cwd().deleteTree(temp_dir) catch {};
    
    // Clone repository to temp directory
    try cloneRepositoryForEdit(&git_cmd, repo_path, temp_dir, body.branch);
    
    // Remove file and stage deletion
    var rm_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "rm", file_path },
        .cwd = temp_dir,
    });
    defer rm_result.deinit(allocator);
    
    if (rm_result.exit_code != 0) {
        std.log.err("Failed to remove file: {s}", .{rm_result.stderr});
        try json.writeError(r, allocator, .internal_server_error, "Failed to remove file");
        return;
    }
    
    // Create commit
    const commit_message = body.message;
    const author_name = body.author.?.name;
    const author_email = body.author.?.email;
    const committer_name = body.committer.name;
    const committer_email = body.committer.email;
    
    var commit_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{
            "commit",
            "-m", commit_message,
            "--author", try std.fmt.allocPrint(allocator, "{s} <{s}>", .{ author_name, author_email }),
        },
        .cwd = temp_dir,
        .env = &.{
            .{ .name = "GIT_COMMITTER_NAME", .value = committer_name },
            .{ .name = "GIT_COMMITTER_EMAIL", .value = committer_email },
        },
    });
    defer commit_result.deinit(allocator);
    
    if (commit_result.exit_code != 0) {
        std.log.err("Failed to create commit: {s}", .{commit_result.stderr});
        try json.writeError(r, allocator, .internal_server_error, "Failed to create commit");
        return;
    }
    
    // Push changes
    var push_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "push", "origin", body.branch },
        .cwd = temp_dir,
    });
    defer push_result.deinit(allocator);
    
    if (push_result.exit_code != 0) {
        std.log.err("Failed to push changes: {s}", .{push_result.stderr});
        try json.writeError(r, allocator, .internal_server_error, "Failed to push changes");
        return;
    }
    
    // Get commit SHA
    const commit_sha = try getLastCommitSha(&git_cmd, temp_dir);
    defer allocator.free(commit_sha);
    
    // Return delete response
    const response = DeleteFileResponse{
        .content = null,
        .commit = .{
            .sha = commit_sha,
            .author = .{
                .name = author_name,
                .email = author_email,
            },
            .committer = .{
                .name = committer_name,
                .email = committer_email,
            },
            .message = commit_message,
            .url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/git/commits/{s}", .{ owner_name, repo_name, commit_sha }),
        },
    };
    
    try json.writeJson(r, allocator, response);
}

// Helper functions

const PathParts = struct {
    owner: []const u8,
    repo: []const u8,
    file_path: []const u8,
    
    pub fn deinit(self: *PathParts, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
        allocator.free(self.file_path);
    }
};

const RawPathParts = struct {
    owner: []const u8,
    repo: []const u8,
    ref: []const u8,
    file_path: []const u8,
    
    pub fn deinit(self: *RawPathParts, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
        allocator.free(self.ref);
        allocator.free(self.file_path);
    }
};

fn parseContentsPath(allocator: std.mem.Allocator, path: []const u8) !PathParts {
    // Parse "/repos/{owner}/{repo}/contents/{path}"
    const prefix = "/repos/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        return error.InvalidPath;
    }
    
    const remaining = path[prefix.len..];
    var parts = std.mem.splitScalar(u8, remaining, '/');
    
    const owner = parts.next() orelse return error.InvalidPath;
    const repo = parts.next() orelse return error.InvalidPath;
    const contents_part = parts.next() orelse return error.InvalidPath;
    
    if (!std.mem.eql(u8, contents_part, "contents")) {
        return error.InvalidPath;
    }
    
    // Rest is the file path
    var file_path = std.ArrayList(u8).init(allocator);
    defer file_path.deinit();
    
    while (parts.next()) |part| {
        if (file_path.items.len > 0) {
            try file_path.append('/');
        }
        try file_path.appendSlice(part);
    }
    
    return PathParts{
        .owner = try allocator.dupe(u8, owner),
        .repo = try allocator.dupe(u8, repo),
        .file_path = try file_path.toOwnedSlice(),
    };
}

fn parseRawPath(allocator: std.mem.Allocator, path: []const u8) !RawPathParts {
    // Parse "/repos/{owner}/{repo}/raw/{ref}/{path}"
    const prefix = "/repos/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        return error.InvalidPath;
    }
    
    const remaining = path[prefix.len..];
    var parts = std.mem.splitScalar(u8, remaining, '/');
    
    const owner = parts.next() orelse return error.InvalidPath;
    const repo = parts.next() orelse return error.InvalidPath;
    const raw_part = parts.next() orelse return error.InvalidPath;
    
    if (!std.mem.eql(u8, raw_part, "raw")) {
        return error.InvalidPath;
    }
    
    const ref = parts.next() orelse return error.InvalidPath;
    
    // Rest is the file path
    var file_path = std.ArrayList(u8).init(allocator);
    defer file_path.deinit();
    
    while (parts.next()) |part| {
        if (file_path.items.len > 0) {
            try file_path.append('/');
        }
        try file_path.appendSlice(part);
    }
    
    return RawPathParts{
        .owner = try allocator.dupe(u8, owner),
        .repo = try allocator.dupe(u8, repo),
        .ref = try allocator.dupe(u8, ref),
        .file_path = try file_path.toOwnedSlice(),
    };
}

fn getRepositoryPath(allocator: std.mem.Allocator, repo: *const Repository) ![]u8 {
    // Construct path: /var/lib/plue/repositories/{owner_id}/{repo_name}.git
    return try std.fmt.allocPrint(allocator, "/var/lib/plue/repositories/{}/{s}.git", .{ repo.owner_id, repo.name });
}

fn getObjectType(allocator: std.mem.Allocator, git_cmd: *GitCommand, repo_path: []const u8, ref: []const u8, path: []const u8) !ObjectType {
    const git_ref_path = if (path.len == 0) 
        try allocator.dupe(u8, ref)
    else
        try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ref, path });
    defer allocator.free(git_ref_path);
    
    var result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "cat-file", "-t", git_ref_path },
        .cwd = repo_path,
    });
    defer result.deinit(allocator);
    
    if (result.exit_code != 0) {
        return .not_found;
    }
    
    const obj_type = std.mem.trim(u8, result.stdout, " \n\r\t");
    if (std.mem.eql(u8, obj_type, "blob")) {
        return .file;
    } else if (std.mem.eql(u8, obj_type, "tree")) {
        return .directory;
    } else {
        return .not_found;
    }
}

fn returnFileContent(
    r: zap.Request,
    ctx: *Context,
    git_cmd: *GitCommand,
    repo_path: []const u8,
    ref: []const u8,
    path: []const u8,
    owner_name: []const u8,
    repo_name: []const u8,
) !void {
    const allocator = ctx.allocator;
    
    // Get file content
    const git_ref_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ref, path });
    defer allocator.free(git_ref_path);
    
    var show_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "show", git_ref_path },
        .cwd = repo_path,
    });
    defer show_result.deinit(allocator);
    
    // Get file size from ls-tree
    var ls_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "ls-tree", "-l", ref, path },
        .cwd = repo_path,
    });
    defer ls_result.deinit(allocator);
    
    const size = parseFileSize(ls_result.stdout) catch 0;
    
    // Determine if content is binary
    const is_binary = isBinaryContent(show_result.stdout);
    
    // Base64 encode if binary
    const encoding = if (is_binary) "base64" else "utf-8";
    const content = if (is_binary)
        try base64Encode(allocator, show_result.stdout)
    else
        try allocator.dupe(u8, show_result.stdout);
    defer if (is_binary) allocator.free(content);
    
    // Calculate SHA
    const sha = try calculateGitBlobSha(allocator, show_result.stdout);
    defer allocator.free(sha);
    
    // Build URLs
    const url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/contents/{s}", .{ owner_name, repo_name, path });
    defer allocator.free(url);
    
    const git_url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/git/blobs/{s}", .{ owner_name, repo_name, sha });
    defer allocator.free(git_url);
    
    const html_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/blob/{s}/{s}", .{ owner_name, repo_name, ref, path });
    defer allocator.free(html_url);
    
    const download_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/raw/{s}/{s}", .{ owner_name, repo_name, ref, path });
    defer allocator.free(download_url);
    
    const response = FileContent{
        .type = "file",
        .encoding = encoding,
        .size = size,
        .name = std.fs.path.basename(path),
        .path = path,
        .content = content,
        .sha = sha,
        .url = url,
        .git_url = git_url,
        .html_url = html_url,
        .download_url = download_url,
        ._links = .{
            .self = url,
            .git = git_url,
            .html = html_url,
        },
    };
    
    try json.writeJson(r, allocator, response);
}

fn returnDirectoryListing(
    r: zap.Request,
    ctx: *Context,
    git_cmd: *GitCommand,
    repo_path: []const u8,
    ref: []const u8,
    path: []const u8,
    owner_name: []const u8,
    repo_name: []const u8,
) !void {
    const allocator = ctx.allocator;
    
    // List directory contents
    const git_path = if (path.len == 0) "." else path;
    var ls_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "ls-tree", "-l", ref, git_path },
        .cwd = repo_path,
    });
    defer ls_result.deinit(allocator);
    
    var entries = std.ArrayList(ContentEntry).init(allocator);
    defer entries.deinit();
    
    // Parse ls-tree output
    var lines = std.mem.tokenizeAny(u8, ls_result.stdout, "\n");
    while (lines.next()) |line| {
        var entry = parseLsTreeLine(allocator, line) catch continue;
        defer entry.deinit(allocator);
        
        const entry_path = if (path.len > 0)
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, entry.name })
        else
            try allocator.dupe(u8, entry.name);
        defer allocator.free(entry_path);
        
        const entry_type = if (std.mem.eql(u8, entry.type, "blob")) "file" else if (std.mem.eql(u8, entry.type, "tree")) "dir" else "submodule";
        
        const url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/contents/{s}", .{ owner_name, repo_name, entry_path });
        defer allocator.free(url);
        
        const git_url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/git/{s}/{s}", .{
            owner_name, repo_name,
            if (std.mem.eql(u8, entry_type, "file")) "blobs" else "trees",
            entry.sha
        });
        defer allocator.free(git_url);
        
        const html_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/{s}/{s}/{s}", .{
            owner_name, repo_name,
            if (std.mem.eql(u8, entry_type, "file")) "blob" else "tree",
            ref, entry_path
        });
        defer allocator.free(html_url);
        
        const download_url = if (std.mem.eql(u8, entry_type, "file"))
            try std.fmt.allocPrint(allocator, "/{s}/{s}/raw/{s}/{s}", .{ owner_name, repo_name, ref, entry_path })
        else
            null;
        defer if (download_url) |du| allocator.free(du);
        
        try entries.append(ContentEntry{
            .type = try allocator.dupe(u8, entry_type),
            .size = entry.size orelse 0,
            .name = try allocator.dupe(u8, entry.name),
            .path = try allocator.dupe(u8, entry_path),
            .sha = try allocator.dupe(u8, entry.sha),
            .url = try allocator.dupe(u8, url),
            .git_url = try allocator.dupe(u8, git_url),
            .html_url = try allocator.dupe(u8, html_url),
            .download_url = if (download_url) |du| try allocator.dupe(u8, du) else null,
            ._links = .{
                .self = try allocator.dupe(u8, url),
                .git = try allocator.dupe(u8, git_url),
                .html = try allocator.dupe(u8, html_url),
            },
        });
    }
    
    try json.writeJson(r, allocator, entries.items);
}

fn parseLsTreeLine(allocator: std.mem.Allocator, line: []const u8) !LsTreeEntry {
    // Format: mode SP type SP sha TAB size TAB name
    // or:     mode SP type SP sha TAB name (for directories)
    var parts = std.mem.tokenizeAny(u8, line, " \t");
    
    const mode = parts.next() orelse return error.InvalidFormat;
    const obj_type = parts.next() orelse return error.InvalidFormat;
    const sha = parts.next() orelse return error.InvalidFormat;
    
    var size: ?u64 = null;
    var name: []const u8 = undefined;
    
    // Next part could be size or name
    const next = parts.next() orelse return error.InvalidFormat;
    if (std.fmt.parseInt(u64, next, 10)) |parsed_size| {
        size = parsed_size;
        name = parts.rest();
    } else |_| {
        name = next;
        // Append rest if there are more parts
        if (parts.rest().len > 0) {
            name = try std.fmt.allocPrint(allocator, "{s} {s}", .{ name, parts.rest() });
        }
    }
    
    return LsTreeEntry{
        .mode = try allocator.dupe(u8, mode),
        .type = try allocator.dupe(u8, obj_type),
        .sha = try allocator.dupe(u8, sha),
        .size = size,
        .name = try allocator.dupe(u8, name),
    };
}

fn parseFileSize(ls_tree_output: []const u8) !u64 {
    // Parse the size from ls-tree -l output
    var lines = std.mem.tokenizeAny(u8, ls_tree_output, "\n");
    if (lines.next()) |line| {
        var parts = std.mem.tokenizeAny(u8, line, " \t");
        _ = parts.next(); // mode
        _ = parts.next(); // type
        _ = parts.next(); // sha
        if (parts.next()) |size_str| {
            return std.fmt.parseInt(u64, size_str, 10) catch 0;
        }
    }
    return 0;
}

fn isBinaryContent(content: []const u8) bool {
    // Simple binary detection - look for null bytes or too many non-printable chars
    var non_printable: u32 = 0;
    const sample_size = @min(content.len, 1024);
    
    for (content[0..sample_size]) |byte| {
        if (byte == 0) return true; // Null byte indicates binary
        if (byte < 32 and byte != '\n' and byte != '\r' and byte != '\t') {
            non_printable += 1;
        }
    }
    
    // If more than 10% non-printable, consider binary
    return non_printable * 10 > sample_size;
}

fn base64Encode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const encoded_len = std.base64.standard.Encoder.calcSize(data.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, data);
    return encoded;
}

fn base64Decode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(data);
    const decoded = try allocator.alloc(u8, decoded_len);
    try std.base64.standard.Decoder.decode(decoded, data);
    return decoded;
}

fn fileExists(git_cmd: *GitCommand, repo_path: []const u8, ref: []const u8, path: []const u8) !bool {
    const allocator = std.heap.page_allocator; // Use page allocator for temp operations
    const git_ref_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ref, path });
    defer allocator.free(git_ref_path);
    
    var result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "cat-file", "-e", git_ref_path },
        .cwd = repo_path,
    });
    defer result.deinit(allocator);
    
    return result.exit_code == 0;
}

fn getFileContent(git_cmd: *GitCommand, repo_path: []const u8, ref: []const u8, path: []const u8) ![]u8 {
    const allocator = std.heap.page_allocator; // Use page allocator for temp operations
    const git_ref_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ref, path });
    defer allocator.free(git_ref_path);
    
    var result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "show", git_ref_path },
        .cwd = repo_path,
    });
    defer result.deinit(allocator);
    
    if (result.exit_code != 0) {
        return error.FileNotFound;
    }
    
    return try allocator.dupe(u8, result.stdout);
}

fn cloneRepositoryForEdit(git_cmd: *GitCommand, repo_path: []const u8, temp_dir: []const u8, branch: []const u8) !void {
    const allocator = std.heap.page_allocator; // Use page allocator for temp operations
    
    // Clone the repository
    var clone_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "clone", "--branch", branch, repo_path, temp_dir },
        .cwd = null,
    });
    defer clone_result.deinit(allocator);
    
    if (clone_result.exit_code != 0) {
        std.log.err("Failed to clone repository: {s}", .{clone_result.stderr});
        return error.FailedToClone;
    }
}

fn getLastCommitSha(git_cmd: *GitCommand, repo_path: []const u8) ![]u8 {
    const allocator = std.heap.page_allocator; // Use page allocator for temp operations
    
    var result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "rev-parse", "HEAD" },
        .cwd = repo_path,
    });
    defer result.deinit(allocator);
    
    if (result.exit_code != 0) {
        return error.FailedToGetCommitSha;
    }
    
    const trimmed = std.mem.trim(u8, result.stdout, " \n\r\t");
    return try allocator.dupe(u8, trimmed);
}

fn calculateGitBlobSha(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    // Git blob SHA is SHA1 of "blob {size}\0{content}"
    const header = try std.fmt.allocPrint(allocator, "blob {}\x00", .{content.len});
    defer allocator.free(header);
    
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(header);
    hasher.update(content);
    
    var hash: [20]u8 = undefined;
    hasher.final(&hash);
    
    return try std.fmt.allocPrint(allocator, "{}", .{std.fmt.fmtSliceHexLower(&hash)});
}

fn detectContentType(file_path: []const u8, content: []const u8) []const u8 {
    // Simple content type detection based on file extension
    const ext = std.fs.path.extension(file_path);
    
    if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) {
        return "text/html";
    } else if (std.mem.eql(u8, ext, ".css")) {
        return "text/css";
    } else if (std.mem.eql(u8, ext, ".js")) {
        return "application/javascript";
    } else if (std.mem.eql(u8, ext, ".json")) {
        return "application/json";
    } else if (std.mem.eql(u8, ext, ".xml")) {
        return "application/xml";
    } else if (std.mem.eql(u8, ext, ".png")) {
        return "image/png";
    } else if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) {
        return "image/jpeg";
    } else if (std.mem.eql(u8, ext, ".gif")) {
        return "image/gif";
    } else if (std.mem.eql(u8, ext, ".svg")) {
        return "image/svg+xml";
    } else if (isBinaryContent(content)) {
        return "application/octet-stream";
    } else {
        return "text/plain";
    }
}

// Phase 3: Advanced Features

// Branch and Tag structures
const BranchRef = struct {
    name: []const u8,
    commit: struct {
        sha: []const u8,
        url: []const u8,
    },
    protected: bool = false,
};

const TagRef = struct {
    name: []const u8,
    commit: struct {
        sha: []const u8,
        url: []const u8,
    },
    zipball_url: []const u8,
    tarball_url: []const u8,
};

// GET /repos/{owner}/{repo}/branches
pub fn listBranchesHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Parse path parameters
    const path = r.path orelse return error.NoPath;
    var parts = try parseRepositoryPath(allocator, path);
    defer parts.deinit(allocator);
    
    const owner_name = parts.owner;
    const repo_name = parts.repo;
    
    // Get repository
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get repository path
    const repo_path = try getRepositoryPath(allocator, &repo);
    defer allocator.free(repo_path);
    
    // Initialize git command
    const git_exe_path = ctx.config.repository.git_executable_path;
    var git_cmd = try GitCommand.init(allocator, git_exe_path);
    defer git_cmd.deinit(allocator);
    
    // List branches
    const branches = try listBranches(&git_cmd, allocator, repo_path, owner_name, repo_name);
    defer {
        for (branches) |*branch| {
            allocator.free(branch.name);
            allocator.free(branch.commit.sha);
            allocator.free(branch.commit.url);
        }
        allocator.free(branches);
    }
    
    try json.writeJson(r, allocator, branches);
}

// GET /repos/{owner}/{repo}/tags
pub fn listTagsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Parse path parameters
    const path = r.path orelse return error.NoPath;
    var parts = try parseRepositoryPath(allocator, path);
    defer parts.deinit(allocator);
    
    const owner_name = parts.owner;
    const repo_name = parts.repo;
    
    // Get repository (similar access control as branches)
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get repository path
    const repo_path = try getRepositoryPath(allocator, &repo);
    defer allocator.free(repo_path);
    
    // Initialize git command
    const git_exe_path = ctx.config.repository.git_executable_path;
    var git_cmd = try GitCommand.init(allocator, git_exe_path);
    defer git_cmd.deinit(allocator);
    
    // List tags
    const tags = try listTags(&git_cmd, allocator, repo_path, owner_name, repo_name);
    defer {
        for (tags) |*tag| {
            allocator.free(tag.name);
            allocator.free(tag.commit.sha);
            allocator.free(tag.commit.url);
            allocator.free(tag.zipball_url);
            allocator.free(tag.tarball_url);
        }
        allocator.free(tags);
    }
    
    try json.writeJson(r, allocator, tags);
}

// GET /repos/{owner}/{repo}/compare/{base}...{head}
pub fn compareCommitsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Parse path parameters
    const path = r.path orelse return error.NoPath;
    var parts = try parseComparePath(allocator, path);
    defer parts.deinit(allocator);
    
    const owner_name = parts.owner;
    const repo_name = parts.repo;
    const base_ref = parts.base;
    const head_ref = parts.head;
    
    // Get repository (similar access control)
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get repository path
    const repo_path = try getRepositoryPath(allocator, &repo);
    defer allocator.free(repo_path);
    
    // Initialize git command
    const git_exe_path = ctx.config.repository.git_executable_path;
    var git_cmd = try GitCommand.init(allocator, git_exe_path);
    defer git_cmd.deinit(allocator);
    
    // Generate comparison
    var comparison = try generateComparison(&git_cmd, allocator, repo_path, base_ref, head_ref, owner_name, repo_name);
    defer comparison.deinit(allocator);
    
    try json.writeJson(r, allocator, comparison);
}

// GET /repos/{owner}/{repo}/commits/{path}/history
pub fn getFileHistoryHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Parse path parameters
    const path = r.path orelse return error.NoPath;
    var parts = try parseFileHistoryPath(allocator, path);
    defer parts.deinit(allocator);
    
    const owner_name = parts.owner;
    const repo_name = parts.repo;
    const file_path = parts.file_path;
    
    // Get repository (similar access control)
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get repository path
    const repo_path = try getRepositoryPath(allocator, &repo);
    defer allocator.free(repo_path);
    
    // Initialize git command
    const git_exe_path = ctx.config.repository.git_executable_path;
    var git_cmd = try GitCommand.init(allocator, git_exe_path);
    defer git_cmd.deinit(allocator);
    
    // Get file history
    const history = try getFileHistory(&git_cmd, allocator, repo_path, file_path, owner_name, repo_name);
    defer {
        for (history) |*commit| {
            commit.deinit(allocator);
        }
        allocator.free(history);
    }
    
    try json.writeJson(r, allocator, history);
}

// Helper structures for advanced features
const CompareResult = struct {
    url: []const u8,
    html_url: []const u8,
    permalink_url: []const u8,
    diff_url: []const u8,
    patch_url: []const u8,
    base_commit: CommitInfo,
    merge_base_commit: CommitInfo,
    status: []const u8, // "identical", "ahead", "behind", "diverged"
    ahead_by: u32,
    behind_by: u32,
    total_commits: u32,
    commits: []CommitInfo,
    files: []FileChange,
    
    pub fn deinit(self: *CompareResult, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.html_url);
        allocator.free(self.permalink_url);
        allocator.free(self.diff_url);
        allocator.free(self.patch_url);
        self.base_commit.deinit(allocator);
        self.merge_base_commit.deinit(allocator);
        allocator.free(self.status);
        for (self.commits) |*commit| {
            commit.deinit(allocator);
        }
        allocator.free(self.commits);
        for (self.files) |*file| {
            file.deinit(allocator);
        }
        allocator.free(self.files);
    }
};

const CommitInfo = struct {
    sha: []const u8,
    url: []const u8,
    html_url: []const u8,
    author: struct {
        name: []const u8,
        email: []const u8,
        date: []const u8,
    },
    committer: struct {
        name: []const u8,
        email: []const u8,
        date: []const u8,
    },
    message: []const u8,
    
    pub fn deinit(self: *CommitInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.sha);
        allocator.free(self.url);
        allocator.free(self.html_url);
        allocator.free(self.author.name);
        allocator.free(self.author.email);
        allocator.free(self.author.date);
        allocator.free(self.committer.name);
        allocator.free(self.committer.email);
        allocator.free(self.committer.date);
        allocator.free(self.message);
    }
};

const FileChange = struct {
    sha: []const u8,
    filename: []const u8,
    status: []const u8, // "added", "removed", "modified", "renamed"
    additions: u32,
    deletions: u32,
    changes: u32,
    blob_url: []const u8,
    raw_url: []const u8,
    contents_url: []const u8,
    patch: []const u8,
    
    pub fn deinit(self: *FileChange, allocator: std.mem.Allocator) void {
        allocator.free(self.sha);
        allocator.free(self.filename);
        allocator.free(self.status);
        allocator.free(self.blob_url);
        allocator.free(self.raw_url);
        allocator.free(self.contents_url);
        allocator.free(self.patch);
    }
};

// Helper functions for Phase 3

const RepoPathParts = struct {
    owner: []const u8,
    repo: []const u8,
    
    pub fn deinit(self: *RepoPathParts, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
    }
};

const ComparePathParts = struct {
    owner: []const u8,
    repo: []const u8,
    base: []const u8,
    head: []const u8,
    
    pub fn deinit(self: *ComparePathParts, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
        allocator.free(self.base);
        allocator.free(self.head);
    }
};

const FileHistoryPathParts = struct {
    owner: []const u8,
    repo: []const u8,
    file_path: []const u8,
    
    pub fn deinit(self: *FileHistoryPathParts, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
        allocator.free(self.file_path);
    }
};

fn parseRepositoryPath(allocator: std.mem.Allocator, path: []const u8) !RepoPathParts {
    // Parse "/repos/{owner}/{repo}/*"
    const prefix = "/repos/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        return error.InvalidPath;
    }
    
    const remaining = path[prefix.len..];
    var parts = std.mem.splitScalar(u8, remaining, '/');
    
    const owner = parts.next() orelse return error.InvalidPath;
    const repo = parts.next() orelse return error.InvalidPath;
    
    return RepoPathParts{
        .owner = try allocator.dupe(u8, owner),
        .repo = try allocator.dupe(u8, repo),
    };
}

fn parseComparePath(allocator: std.mem.Allocator, path: []const u8) !ComparePathParts {
    // Parse "/repos/{owner}/{repo}/compare/{base}...{head}"
    const prefix = "/repos/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        return error.InvalidPath;
    }
    
    const remaining = path[prefix.len..];
    var parts = std.mem.splitScalar(u8, remaining, '/');
    
    const owner = parts.next() orelse return error.InvalidPath;
    const repo = parts.next() orelse return error.InvalidPath;
    const compare_part = parts.next() orelse return error.InvalidPath;
    
    if (!std.mem.eql(u8, compare_part, "compare")) {
        return error.InvalidPath;
    }
    
    const range = parts.next() orelse return error.InvalidPath;
    
    // Split on "..."
    if (std.mem.indexOf(u8, range, "...")) |dots_index| {
        const base = range[0..dots_index];
        const head = range[dots_index + 3..];
        
        return ComparePathParts{
            .owner = try allocator.dupe(u8, owner),
            .repo = try allocator.dupe(u8, repo),
            .base = try allocator.dupe(u8, base),
            .head = try allocator.dupe(u8, head),
        };
    } else {
        return error.InvalidPath;
    }
}

fn parseFileHistoryPath(allocator: std.mem.Allocator, path: []const u8) !FileHistoryPathParts {
    // Parse "/repos/{owner}/{repo}/commits/{path}/history"
    const prefix = "/repos/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        return error.InvalidPath;
    }
    
    const remaining = path[prefix.len..];
    var parts = std.mem.splitScalar(u8, remaining, '/');
    
    const owner = parts.next() orelse return error.InvalidPath;
    const repo = parts.next() orelse return error.InvalidPath;
    const commits_part = parts.next() orelse return error.InvalidPath;
    
    if (!std.mem.eql(u8, commits_part, "commits")) {
        return error.InvalidPath;
    }
    
    // Collect file path parts until "history"
    var file_path = std.ArrayList(u8).init(allocator);
    defer file_path.deinit();
    
    var found_history = false;
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, "history")) {
            found_history = true;
            break;
        }
        if (file_path.items.len > 0) {
            try file_path.append('/');
        }
        try file_path.appendSlice(part);
    }
    
    if (!found_history) {
        return error.InvalidPath;
    }
    
    return FileHistoryPathParts{
        .owner = try allocator.dupe(u8, owner),
        .repo = try allocator.dupe(u8, repo),
        .file_path = try file_path.toOwnedSlice(),
    };
}

fn listBranches(git_cmd: *GitCommand, allocator: std.mem.Allocator, repo_path: []const u8, owner_name: []const u8, repo_name: []const u8) ![]BranchRef {
    var result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads/" },
        .cwd = repo_path,
    });
    defer result.deinit(allocator);
    
    if (result.exit_code != 0) {
        return error.FailedToListBranches;
    }
    
    var branches = std.ArrayList(BranchRef).init(allocator);
    defer branches.deinit();
    
    var lines = std.mem.tokenizeAny(u8, result.stdout, "\n");
    while (lines.next()) |line| {
        var parts = std.mem.tokenizeAny(u8, line, " ");
        const name = parts.next() orelse continue;
        const sha = parts.next() orelse continue;
        
        try branches.append(BranchRef{
            .name = try allocator.dupe(u8, name),
            .commit = .{
                .sha = try allocator.dupe(u8, sha),
                .url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/git/commits/{s}", .{ owner_name, repo_name, sha }),
            },
            .protected = false, // TODO: Implement branch protection
        });
    }
    
    return branches.toOwnedSlice();
}

fn listTags(git_cmd: *GitCommand, allocator: std.mem.Allocator, repo_path: []const u8, owner_name: []const u8, repo_name: []const u8) ![]TagRef {
    var result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "for-each-ref", "--format=%(refname:short) %(objectname)", "refs/tags/" },
        .cwd = repo_path,
    });
    defer result.deinit(allocator);
    
    if (result.exit_code != 0) {
        return error.FailedToListTags;
    }
    
    var tags = std.ArrayList(TagRef).init(allocator);
    defer tags.deinit();
    
    var lines = std.mem.tokenizeAny(u8, result.stdout, "\n");
    while (lines.next()) |line| {
        var parts = std.mem.tokenizeAny(u8, line, " ");
        const name = parts.next() orelse continue;
        const sha = parts.next() orelse continue;
        
        try tags.append(TagRef{
            .name = try allocator.dupe(u8, name),
            .commit = .{
                .sha = try allocator.dupe(u8, sha),
                .url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/git/commits/{s}", .{ owner_name, repo_name, sha }),
            },
            .zipball_url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/zipball/{s}", .{ owner_name, repo_name, name }),
            .tarball_url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/tarball/{s}", .{ owner_name, repo_name, name }),
        });
    }
    
    return tags.toOwnedSlice();
}

fn generateComparison(git_cmd: *GitCommand, allocator: std.mem.Allocator, repo_path: []const u8, base_ref: []const u8, head_ref: []const u8, owner_name: []const u8, repo_name: []const u8) !CompareResult {
    // Get commit count
    var ahead_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "rev-list", "--count", try std.fmt.allocPrint(allocator, "{s}..{s}", .{ base_ref, head_ref }) },
        .cwd = repo_path,
    });
    defer ahead_result.deinit(allocator);
    
    var behind_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "rev-list", "--count", try std.fmt.allocPrint(allocator, "{s}..{s}", .{ head_ref, base_ref }) },
        .cwd = repo_path,
    });
    defer behind_result.deinit(allocator);
    
    const ahead_by = std.fmt.parseInt(u32, std.mem.trim(u8, ahead_result.stdout, " \n\r\t"), 10) catch 0;
    const behind_by = std.fmt.parseInt(u32, std.mem.trim(u8, behind_result.stdout, " \n\r\t"), 10) catch 0;
    
    // Determine status
    const status = if (ahead_by == 0 and behind_by == 0)
        "identical"
    else if (behind_by == 0)
        "ahead"
    else if (ahead_by == 0)
        "behind"
    else
        "diverged";
    
    // Get commits
    var log_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "log", "--pretty=format:%H|%an|%ae|%ad|%cn|%ce|%cd|%s", "--date=iso", try std.fmt.allocPrint(allocator, "{s}..{s}", .{ base_ref, head_ref }) },
        .cwd = repo_path,
    });
    defer log_result.deinit(allocator);
    
    var commits = std.ArrayList(CommitInfo).init(allocator);
    defer commits.deinit();
    
    var lines = std.mem.tokenizeAny(u8, log_result.stdout, "\n");
    while (lines.next()) |line| {
        var parts = std.mem.splitScalar(u8, line, '|');
        const sha = parts.next() orelse continue;
        const author_name = parts.next() orelse continue;
        const author_email = parts.next() orelse continue;
        const author_date = parts.next() orelse continue;
        const committer_name = parts.next() orelse continue;
        const committer_email = parts.next() orelse continue;
        const committer_date = parts.next() orelse continue;
        const message = parts.rest();
        
        try commits.append(CommitInfo{
            .sha = try allocator.dupe(u8, sha),
            .url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/git/commits/{s}", .{ owner_name, repo_name, sha }),
            .html_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/commit/{s}", .{ owner_name, repo_name, sha }),
            .author = .{
                .name = try allocator.dupe(u8, author_name),
                .email = try allocator.dupe(u8, author_email),
                .date = try allocator.dupe(u8, author_date),
            },
            .committer = .{
                .name = try allocator.dupe(u8, committer_name),
                .email = try allocator.dupe(u8, committer_email),
                .date = try allocator.dupe(u8, committer_date),
            },
            .message = try allocator.dupe(u8, message),
        });
    }
    
    // Get file changes (simplified)
    var files = std.ArrayList(FileChange).init(allocator);
    defer files.deinit();
    
    // For now, return empty files array - full diff implementation would be more complex
    
    return CompareResult{
        .url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/compare/{s}...{s}", .{ owner_name, repo_name, base_ref, head_ref }),
        .html_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/compare/{s}...{s}", .{ owner_name, repo_name, base_ref, head_ref }),
        .permalink_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/compare/{s}...{s}", .{ owner_name, repo_name, base_ref, head_ref }),
        .diff_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/compare/{s}...{s}.diff", .{ owner_name, repo_name, base_ref, head_ref }),
        .patch_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/compare/{s}...{s}.patch", .{ owner_name, repo_name, base_ref, head_ref }),
        .base_commit = try getCommitInfo(git_cmd, allocator, repo_path, base_ref, owner_name, repo_name),
        .merge_base_commit = try getCommitInfo(git_cmd, allocator, repo_path, base_ref, owner_name, repo_name), // Simplified - should get merge base
        .status = try allocator.dupe(u8, status),
        .ahead_by = ahead_by,
        .behind_by = behind_by,
        .total_commits = ahead_by,
        .commits = try commits.toOwnedSlice(),
        .files = try files.toOwnedSlice(),
    };
}

fn getFileHistory(git_cmd: *GitCommand, allocator: std.mem.Allocator, repo_path: []const u8, file_path: []const u8, owner_name: []const u8, repo_name: []const u8) ![]CommitInfo {
    var result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "log", "--pretty=format:%H|%an|%ae|%ad|%cn|%ce|%cd|%s", "--date=iso", "--", file_path },
        .cwd = repo_path,
    });
    defer result.deinit(allocator);
    
    if (result.exit_code != 0) {
        return error.FailedToGetFileHistory;
    }
    
    var commits = std.ArrayList(CommitInfo).init(allocator);
    defer commits.deinit();
    
    var lines = std.mem.tokenizeAny(u8, result.stdout, "\n");
    while (lines.next()) |line| {
        var parts = std.mem.splitScalar(u8, line, '|');
        const sha = parts.next() orelse continue;
        const author_name = parts.next() orelse continue;
        const author_email = parts.next() orelse continue;
        const author_date = parts.next() orelse continue;
        const committer_name = parts.next() orelse continue;
        const committer_email = parts.next() orelse continue;
        const committer_date = parts.next() orelse continue;
        const message = parts.rest();
        
        try commits.append(CommitInfo{
            .sha = try allocator.dupe(u8, sha),
            .url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/git/commits/{s}", .{ owner_name, repo_name, sha }),
            .html_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/commit/{s}", .{ owner_name, repo_name, sha }),
            .author = .{
                .name = try allocator.dupe(u8, author_name),
                .email = try allocator.dupe(u8, author_email),
                .date = try allocator.dupe(u8, author_date),
            },
            .committer = .{
                .name = try allocator.dupe(u8, committer_name),
                .email = try allocator.dupe(u8, committer_email),
                .date = try allocator.dupe(u8, committer_date),
            },
            .message = try allocator.dupe(u8, message),
        });
    }
    
    return commits.toOwnedSlice();
}

fn getCommitInfo(git_cmd: *GitCommand, allocator: std.mem.Allocator, repo_path: []const u8, ref: []const u8, owner_name: []const u8, repo_name: []const u8) !CommitInfo {
    var result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ "show", "--pretty=format:%H|%an|%ae|%ad|%cn|%ce|%cd|%s", "--no-patch", "--date=iso", ref },
        .cwd = repo_path,
    });
    defer result.deinit(allocator);
    
    if (result.exit_code != 0) {
        return error.FailedToGetCommitInfo;
    }
    
    const line = std.mem.trim(u8, result.stdout, " \n\r\t");
    var parts = std.mem.splitScalar(u8, line, '|');
    const sha = parts.next() orelse return error.InvalidCommitFormat;
    const author_name = parts.next() orelse return error.InvalidCommitFormat;
    const author_email = parts.next() orelse return error.InvalidCommitFormat;
    const author_date = parts.next() orelse return error.InvalidCommitFormat;
    const committer_name = parts.next() orelse return error.InvalidCommitFormat;
    const committer_email = parts.next() orelse return error.InvalidCommitFormat;
    const committer_date = parts.next() orelse return error.InvalidCommitFormat;
    const message = parts.rest();
    
    return CommitInfo{
        .sha = try allocator.dupe(u8, sha),
        .url = try std.fmt.allocPrint(allocator, "/api/v1/repos/{s}/{s}/git/commits/{s}", .{ owner_name, repo_name, sha }),
        .html_url = try std.fmt.allocPrint(allocator, "/{s}/{s}/commit/{s}", .{ owner_name, repo_name, sha }),
        .author = .{
            .name = try allocator.dupe(u8, author_name),
            .email = try allocator.dupe(u8, author_email),
            .date = try allocator.dupe(u8, author_date),
        },
        .committer = .{
            .name = try allocator.dupe(u8, committer_name),
            .email = try allocator.dupe(u8, committer_email),
            .date = try allocator.dupe(u8, committer_date),
        },
        .message = try allocator.dupe(u8, message),
    };
}

// Tests
test "parses contents path correctly" {
    const allocator = std.testing.allocator;
    
    var parts = try parseContentsPath(allocator, "/repos/owner/repo/contents/path/to/file.txt");
    defer parts.deinit(allocator);
    
    try std.testing.expectEqualStrings("owner", parts.owner);
    try std.testing.expectEqualStrings("repo", parts.repo);
    try std.testing.expectEqualStrings("path/to/file.txt", parts.file_path);
}

test "parses raw path correctly" {
    const allocator = std.testing.allocator;
    
    var parts = try parseRawPath(allocator, "/repos/owner/repo/raw/main/path/to/file.txt");
    defer parts.deinit(allocator);
    
    try std.testing.expectEqualStrings("owner", parts.owner);
    try std.testing.expectEqualStrings("repo", parts.repo);
    try std.testing.expectEqualStrings("main", parts.ref);
    try std.testing.expectEqualStrings("path/to/file.txt", parts.file_path);
}

test "detects binary content" {
    try std.testing.expect(isBinaryContent("\x00\x01\x02"));
    try std.testing.expect(!isBinaryContent("Hello, world!"));
}

test "calculates git blob SHA correctly" {
    const allocator = std.testing.allocator;
    
    const sha = try calculateGitBlobSha(allocator, "Hello, world!");
    defer allocator.free(sha);
    
    // Expected SHA1 for "blob 13\0Hello, world!"
    try std.testing.expectEqualStrings("5dd01c177f5d7d1be5346a5bc18a569a7410c2ef", sha);
}