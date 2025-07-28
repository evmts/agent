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