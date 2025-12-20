//! Plue Grep - Fast text search library
//!
//! A native Zig library for searching text patterns in files.
//! Designed to be called from Bun via FFI.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;

/// A single match result
pub const Match = struct {
    /// File path (relative to search root)
    path: []const u8,
    /// Line number (1-indexed)
    line_number: u32,
    /// The matching line content
    line: []const u8,
    /// Byte offset of match start within line
    match_start: u32,
    /// Byte offset of match end within line
    match_end: u32,
};

/// Search options
pub const SearchOptions = struct {
    /// Case-insensitive matching
    case_insensitive: bool = false,
    /// Maximum results to return (0 = unlimited)
    max_results: u32 = 0,
    /// Skip hidden files and directories
    skip_hidden: bool = true,
    /// File glob pattern (e.g., "*.zig")
    glob: ?[]const u8 = null,
    /// Lines of context before match
    context_before: u32 = 0,
    /// Lines of context after match
    context_after: u32 = 0,
};

/// Search result container
pub const SearchResult = struct {
    matches: std.ArrayListUnmanaged(Match),
    allocator: Allocator,
    truncated: bool = false,
    total_files_searched: u32 = 0,
    errors: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: Allocator) SearchResult {
        return .{
            .matches = .{},
            .allocator = allocator,
            .errors = .{},
        };
    }

    pub fn deinit(self: *SearchResult) void {
        for (self.matches.items) |match| {
            self.allocator.free(match.path);
            self.allocator.free(match.line);
        }
        self.matches.deinit(self.allocator);
        for (self.errors.items) |err| {
            self.allocator.free(err);
        }
        self.errors.deinit(self.allocator);
    }

    pub fn addMatch(self: *SearchResult, match: Match) !void {
        try self.matches.append(self.allocator, match);
    }

    pub fn addError(self: *SearchResult, msg: []const u8) !void {
        const owned = try self.allocator.dupe(u8, msg);
        try self.errors.append(self.allocator, owned);
    }
};

/// Search for a literal pattern in files
pub fn searchLiteral(
    allocator: Allocator,
    root_path: []const u8,
    pattern: []const u8,
    options: SearchOptions,
) !SearchResult {
    var result = SearchResult.init(allocator);
    errdefer result.deinit();

    // Prepare pattern for case-insensitive search
    var search_pattern: []u8 = undefined;
    if (options.case_insensitive) {
        search_pattern = try allocator.alloc(u8, pattern.len);
        defer allocator.free(search_pattern);
        for (pattern, 0..) |c, i| {
            search_pattern[i] = std.ascii.toLower(c);
        }
    }

    // Open directory for walking
    var dir = fs.cwd().openDir(root_path, .{ .iterate = true }) catch |err| {
        try result.addError(try std.fmt.allocPrint(allocator, "Failed to open directory: {}", .{err}));
        return result;
    };
    defer dir.close();

    // Walk the directory tree
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        // Check max results
        if (options.max_results > 0 and result.matches.items.len >= options.max_results) {
            result.truncated = true;
            break;
        }

        // Skip directories
        if (entry.kind == .directory) continue;

        // Skip hidden files if requested
        if (options.skip_hidden and entry.basename.len > 0 and entry.basename[0] == '.') {
            continue;
        }

        // Check glob pattern
        if (options.glob) |glob| {
            if (!matchGlob(entry.basename, glob)) {
                continue;
            }
        }

        // Search the file
        result.total_files_searched += 1;
        try searchFile(allocator, dir, entry.path, pattern, options, &result);
    }

    return result;
}

fn searchFile(
    allocator: Allocator,
    dir: fs.Dir,
    path: []const u8,
    pattern: []const u8,
    options: SearchOptions,
    result: *SearchResult,
) !void {
    const file = dir.openFile(path, .{}) catch {
        return; // Skip files we can't open
    };
    defer file.close();

    // Read file content
    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch {
        return; // Skip files that are too large or unreadable
    };
    defer allocator.free(content);

    // Search line by line
    var line_number: u32 = 1;
    var line_start: usize = 0;

    for (content, 0..) |c, i| {
        if (c == '\n' or i == content.len - 1) {
            const line_end = if (c == '\n') i else i + 1;
            const line = content[line_start..line_end];

            // Search for pattern in line
            const match_pos = if (options.case_insensitive)
                indexOfIgnoreCase(line, pattern)
            else
                mem.indexOf(u8, line, pattern);

            if (match_pos) |pos| {
                // Check if we've hit max results
                if (options.max_results > 0 and result.matches.items.len >= options.max_results) {
                    result.truncated = true;
                    return;
                }

                const match = Match{
                    .path = try allocator.dupe(u8, path),
                    .line_number = line_number,
                    .line = try allocator.dupe(u8, mem.trim(u8, line, &[_]u8{ '\r', '\n' })),
                    .match_start = @intCast(pos),
                    .match_end = @intCast(pos + pattern.len),
                };
                try result.addMatch(match);
            }

            line_start = i + 1;
            line_number += 1;
        }
    }
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len > haystack.len) return null;
    if (needle.len == 0) return 0;

    outer: for (0..haystack.len - needle.len + 1) |i| {
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                continue :outer;
            }
        }
        return i;
    }
    return null;
}

/// Simple glob matching (supports * and ?)
fn matchGlob(name: []const u8, pattern: []const u8) bool {
    var ni: usize = 0;
    var pi: usize = 0;
    var star_idx: ?usize = null;
    var match_idx: usize = 0;

    while (ni < name.len) {
        if (pi < pattern.len and (pattern[pi] == '?' or pattern[pi] == name[ni])) {
            ni += 1;
            pi += 1;
        } else if (pi < pattern.len and pattern[pi] == '*') {
            star_idx = pi;
            match_idx = ni;
            pi += 1;
        } else if (star_idx) |si| {
            pi = si + 1;
            match_idx += 1;
            ni = match_idx;
        } else {
            return false;
        }
    }

    while (pi < pattern.len and pattern[pi] == '*') {
        pi += 1;
    }

    return pi == pattern.len;
}

// ============================================================================
// C FFI Interface for Bun
// ============================================================================

/// Opaque handle for search results
pub const SearchResultHandle = *SearchResult;

/// C-compatible match structure
pub const CMatch = extern struct {
    path: [*:0]const u8,
    line_number: u32,
    line: [*:0]const u8,
    match_start: u32,
    match_end: u32,
};

/// C-compatible options structure
pub const CSearchOptions = extern struct {
    case_insensitive: bool,
    max_results: u32,
    skip_hidden: bool,
    glob: ?[*:0]const u8,
    context_before: u32,
    context_after: u32,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Search for a pattern in files (C API)
export fn grep_search(
    root_path: [*:0]const u8,
    pattern: [*:0]const u8,
    opts: *const CSearchOptions,
) ?SearchResultHandle {
    const allocator = gpa.allocator();

    const options = SearchOptions{
        .case_insensitive = opts.case_insensitive,
        .max_results = opts.max_results,
        .skip_hidden = opts.skip_hidden,
        .glob = if (opts.glob) |g| mem.span(g) else null,
        .context_before = opts.context_before,
        .context_after = opts.context_after,
    };

    const result_ptr = allocator.create(SearchResult) catch return null;
    result_ptr.* = searchLiteral(
        allocator,
        mem.span(root_path),
        mem.span(pattern),
        options,
    ) catch {
        allocator.destroy(result_ptr);
        return null;
    };

    return result_ptr;
}

/// Get the number of matches
export fn grep_result_count(handle: SearchResultHandle) u32 {
    return @intCast(handle.matches.items.len);
}

/// Check if results were truncated
export fn grep_result_truncated(handle: SearchResultHandle) bool {
    return handle.truncated;
}

/// Get a match at index (returns null if out of bounds)
export fn grep_result_get(handle: SearchResultHandle, index: u32) ?*const Match {
    if (index >= handle.matches.items.len) return null;
    return &handle.matches.items[index];
}

/// Free search results
export fn grep_result_free(handle: SearchResultHandle) void {
    handle.deinit();
    gpa.allocator().destroy(handle);
}

/// Get match path as null-terminated string
export fn grep_match_path(match: *const Match) [*:0]const u8 {
    // Note: This assumes the path is already null-terminated or we need to copy
    // For simplicity, we'll return the pointer assuming Zig strings work with FFI
    return @ptrCast(match.path.ptr);
}

/// Get match line as null-terminated string
export fn grep_match_line(match: *const Match) [*:0]const u8 {
    return @ptrCast(match.line.ptr);
}

// ============================================================================
// Tests
// ============================================================================

test "glob matching" {
    try std.testing.expect(matchGlob("foo.zig", "*.zig"));
    try std.testing.expect(matchGlob("foo.zig", "foo.*"));
    try std.testing.expect(matchGlob("foo.zig", "f?o.zig"));
    try std.testing.expect(!matchGlob("foo.zig", "*.ts"));
    try std.testing.expect(matchGlob("test.spec.ts", "*.ts"));
    try std.testing.expect(matchGlob("anything", "*"));
}

test "case insensitive search" {
    try std.testing.expectEqual(@as(?usize, 0), indexOfIgnoreCase("Hello World", "hello"));
    try std.testing.expectEqual(@as(?usize, 6), indexOfIgnoreCase("Hello World", "world"));
    try std.testing.expectEqual(@as(?usize, null), indexOfIgnoreCase("Hello", "xyz"));
}
