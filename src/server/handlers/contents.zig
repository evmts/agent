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