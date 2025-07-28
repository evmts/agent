const std = @import("std");
const builtin = @import("builtin");

// Phase 1: Core Security Foundation - Tests First

test "rejects arguments starting with dash" {
    const allocator = std.testing.allocator;
    try std.testing.expect(!isSafeArgumentValue("-v"));
    try std.testing.expect(!isSafeArgumentValue("--version"));
    try std.testing.expect(isSafeArgumentValue("main"));
}

test "validates known git options" {
    try std.testing.expect(isValidGitOption("--version"));
    try std.testing.expect(isValidGitOption("--no-pager"));
    try std.testing.expect(!isValidGitOption("--random-flag"));
}

test "rejects broken git arguments" {
    // Test known problematic arguments
    try std.testing.expect(isBrokenGitArgument("--upload-archive"));  // Old syntax
    try std.testing.expect(isBrokenGitArgument("--output"));  // Can write arbitrary files
    try std.testing.expect(!isBrokenGitArgument("--version"));
}

test "sanitizes repository paths" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidRepository, validateRepositoryPath("../../../etc"));
    try std.testing.expectError(error.InvalidRepository, validateRepositoryPath("/etc/passwd"));
    try validateRepositoryPath("repos/user/project.git");
}

// Now implement the functions to make tests pass

fn isSafeArgumentValue(value: []const u8) bool {
    if (value.len == 0) return false;
    return value[0] != '-';
}

const VALID_GIT_OPTIONS = [_][]const u8{
    "--version",
    "--no-pager",
    "--bare",
    "--quiet",
    "-q",
    "--verbose",
    "-v",
    "--no-replace-objects",
    "--literal-pathspecs",
    "--glob-pathspecs",
    "--noglob-pathspecs",
    "--icase-pathspecs",
    "--no-optional-locks",
};

fn isValidGitOption(option: []const u8) bool {
    for (VALID_GIT_OPTIONS) |valid_opt| {
        if (std.mem.eql(u8, option, valid_opt)) {
            return true;
        }
    }
    return false;
}

const BROKEN_GIT_ARGS = [_][]const u8{
    "--upload-archive",  // Old syntax, security risk
    "--output",          // Can write to arbitrary files
    "--export-all",      // Exposes all refs
    "--receive-pack",    // Can be exploited
    "--exec",            // Arbitrary command execution
};

fn isBrokenGitArgument(arg: []const u8) bool {
    for (BROKEN_GIT_ARGS) |broken_arg| {
        if (std.mem.eql(u8, arg, broken_arg)) {
            return true;
        }
    }
    return false;
}

pub const GitError = error{
    GitNotFound,
    InvalidArgument,
    CommandInjection,
    Timeout,
    ProcessFailed,
    PermissionDenied,
    InvalidRepository,
    AuthenticationFailed,
    ChildProcessFailed,
    OutputTooLarge,
};

fn validateRepositoryPath(path: []const u8) GitError!void {
    // Check for directory traversal
    if (std.mem.indexOf(u8, path, "..") != null) {
        return error.InvalidRepository;
    }
    
    // Check for absolute paths
    if (path.len > 0 and path[0] == '/') {
        return error.InvalidRepository;
    }
    
    // Check path length (Git's limit is 1024)
    if (path.len > 1024) {
        return error.InvalidRepository;
    }
}

fn sanitizeGitUrl(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    // Remove credentials from URLs like https://user:pass@github.com/repo.git
    if (std.mem.indexOf(u8, url, "@")) |at_pos| {
        if (std.mem.startsWith(u8, url, "https://") or std.mem.startsWith(u8, url, "http://")) {
            const protocol_end = std.mem.indexOf(u8, url, "://").? + 3;
            const after_at = url[at_pos + 1..];
            
            var result = std.ArrayList(u8).init(allocator);
            try result.appendSlice(url[0..protocol_end]);
            try result.appendSlice(after_at);
            return result.toOwnedSlice();
        }
    }
    
    // If no credentials found, return a copy
    return allocator.dupe(u8, url);
}

test "sanitizes git urls with credentials" {
    const allocator = std.testing.allocator;
    
    const url1 = try sanitizeGitUrl(allocator, "https://user:pass@github.com/repo.git");
    defer allocator.free(url1);
    try std.testing.expectEqualStrings("https://github.com/repo.git", url1);
    
    const url2 = try sanitizeGitUrl(allocator, "git@github.com:owner/repo.git");
    defer allocator.free(url2);
    try std.testing.expectEqualStrings("git@github.com:owner/repo.git", url2);
}

// Phase 2: Git Executable Detection - Tests First

test "finds git executable" {
    const allocator = std.testing.allocator;
    const git_path = findGitExecutable(allocator) catch {
        std.log.warn("Git not available, skipping test", .{});
        return;
    };
    defer allocator.free(git_path);

    try std.testing.expect(git_path.len > 0);
    try std.testing.expect(std.mem.endsWith(u8, git_path, "git") or 
                          (builtin.os.tag == .windows and std.mem.endsWith(u8, git_path, "git.exe")));
}

test "detects git version" {
    const allocator = std.testing.allocator;
    const version = getGitVersion(allocator) catch {
        std.log.warn("Git not available, skipping test", .{});
        return;
    };
    defer allocator.free(version);

    try std.testing.expect(std.mem.indexOf(u8, version, "git version") != null);
}

// Global cache for git executable path
var g_git_path: ?[]const u8 = null;
var g_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

pub fn findGitExecutable(allocator: std.mem.Allocator) ![]const u8 {
    if (g_git_path) |path| return allocator.dupe(u8, path);
    
    // Check standard paths first
    const standard_paths = if (builtin.os.tag == .windows)
        [_][]const u8{ "C:\\Program Files\\Git\\bin\\git.exe", "C:\\Program Files (x86)\\Git\\bin\\git.exe" }
    else
        [_][]const u8{ "/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git" };
    
    for (standard_paths) |path| {
        const stat = std.fs.cwd().statFile(path) catch continue;
        if (stat.kind == .file) {
            g_git_path = try g_arena.allocator().dupe(u8, path);
            return allocator.dupe(u8, g_git_path.?);
        }
    }
    
    // Search PATH
    const path_env = std.process.getEnvVarOwned(allocator, "PATH") catch {
        return error.GitNotFound;
    };
    defer allocator.free(path_env);
    
    var it = std.mem.tokenize(u8, path_env, &[_]u8{std.fs.path.delimiter});
    while (it.next()) |dir| {
        const git_name = if (builtin.os.tag == .windows) "git.exe" else "git";
        const git_path = try std.fs.path.join(allocator, &.{ dir, git_name });
        defer allocator.free(git_path);
        
        // Check if executable exists
        const stat = std.fs.cwd().statFile(git_path) catch continue;
        if (stat.kind != .file) continue;
        
        // Check if executable on Unix
        if (builtin.os.tag.isDarwin() or builtin.os.tag == .linux) {
            if (stat.mode & 0o111 == 0) continue;
        }
        
        g_git_path = try g_arena.allocator().dupe(u8, git_path);
        return allocator.dupe(u8, g_git_path.?);
    }
    
    return error.GitNotFound;
}

fn getGitVersion(allocator: std.mem.Allocator) ![]u8 {
    const git_path = try findGitExecutable(allocator);
    defer allocator.free(git_path);
    
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ git_path, "--version" },
    });
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);
    
    if (result.term.Exited != 0) {
        return error.GitNotFound;
    }
    
    // Return a copy of stdout
    return allocator.dupe(u8, std.mem.trimRight(u8, result.stdout, "\n\r"));
}