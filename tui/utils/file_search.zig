const std = @import("std");

/// Result of a file search
pub const SearchResult = struct {
    path: []const u8,
    relative_path: []const u8,
    is_directory: bool,
    score: u32,
};

/// File search with fuzzy matching
pub const FileSearch = struct {
    allocator: std.mem.Allocator,
    root_dir: []const u8,
    results: std.ArrayList(SearchResult),

    const IGNORE_DIRS = [_][]const u8{
        "node_modules",
        "zig-cache",
        "zig-out",
        ".git",
        ".zig-cache",
        "target",
        "__pycache__",
        ".venv",
        "venv",
        "dist",
        "build",
    };

    pub fn init(allocator: std.mem.Allocator, root_dir: []const u8) FileSearch {
        return .{
            .allocator = allocator,
            .root_dir = root_dir,
            .results = std.ArrayList(SearchResult).init(allocator),
        };
    }

    pub fn deinit(self: *FileSearch) void {
        for (self.results.items) |r| {
            self.allocator.free(r.path);
            self.allocator.free(r.relative_path);
        }
        self.results.deinit();
    }

    /// Search for files matching the query
    pub fn search(self: *FileSearch, query: []const u8, max_results: usize) ![]const SearchResult {
        // Clear previous results
        for (self.results.items) |r| {
            self.allocator.free(r.path);
            self.allocator.free(r.relative_path);
        }
        self.results.clearRetainingCapacity();

        if (query.len == 0) {
            try self.addCommonFiles();
        } else {
            try self.walkDirectory(self.root_dir, query, 0, 5);
        }

        // Sort by score (descending)
        std.mem.sort(SearchResult, self.results.items, {}, struct {
            fn cmp(_: void, a: SearchResult, b: SearchResult) bool {
                return a.score > b.score;
            }
        }.cmp);

        return self.results.items[0..@min(max_results, self.results.items.len)];
    }

    fn walkDirectory(self: *FileSearch, dir_path: []const u8, query: []const u8, depth: usize, max_depth: usize) !void {
        if (depth > max_depth) return;
        if (self.results.items.len >= 100) return; // Limit results

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            // Skip hidden files
            if (entry.name[0] == '.') continue;

            // Skip ignored directories
            if (self.shouldIgnore(entry.name)) continue;

            const full_path = std.fs.path.join(self.allocator, &.{ dir_path, entry.name }) catch continue;
            const relative_path = self.makeRelative(full_path) catch {
                self.allocator.free(full_path);
                continue;
            };

            const score = fuzzyMatch(entry.name, query);
            if (score > 0) {
                self.results.append(.{
                    .path = full_path,
                    .relative_path = relative_path,
                    .is_directory = entry.kind == .directory,
                    .score = score,
                }) catch {
                    self.allocator.free(full_path);
                    self.allocator.free(relative_path);
                    continue;
                };
            } else {
                self.allocator.free(full_path);
                self.allocator.free(relative_path);
            }

            // Recurse into directories
            if (entry.kind == .directory) {
                const sub_path = std.fs.path.join(self.allocator, &.{ dir_path, entry.name }) catch continue;
                defer self.allocator.free(sub_path);
                self.walkDirectory(sub_path, query, depth + 1, max_depth) catch {};
            }
        }
    }

    fn shouldIgnore(self: *FileSearch, name: []const u8) bool {
        _ = self;
        for (IGNORE_DIRS) |ignore| {
            if (std.mem.eql(u8, name, ignore)) return true;
        }
        return false;
    }

    fn makeRelative(self: *FileSearch, path: []const u8) ![]const u8 {
        if (std.mem.startsWith(u8, path, self.root_dir)) {
            var rel = path[self.root_dir.len..];
            if (rel.len > 0 and rel[0] == '/') {
                rel = rel[1..];
            }
            return try self.allocator.dupe(u8, rel);
        }
        return try self.allocator.dupe(u8, path);
    }

    fn addCommonFiles(self: *FileSearch) !void {
        const common_files = [_][]const u8{
            "README.md",
            "package.json",
            "build.zig",
            "Cargo.toml",
            "main.zig",
            "main.ts",
            "index.ts",
            "index.js",
            "pyproject.toml",
            "go.mod",
        };

        for (common_files) |file| {
            const full_path = std.fs.path.join(self.allocator, &.{ self.root_dir, file }) catch continue;

            // Check if file exists
            std.fs.cwd().access(full_path, .{}) catch {
                self.allocator.free(full_path);
                continue;
            };

            const relative = try self.allocator.dupe(u8, file);
            try self.results.append(.{
                .path = full_path,
                .relative_path = relative,
                .is_directory = false,
                .score = 100,
            });
        }
    }
};

/// Fuzzy match a name against a query, returning a score (0 = no match)
pub fn fuzzyMatch(name: []const u8, query: []const u8) u32 {
    if (query.len == 0) return 0;

    const name_lower = toLowerBuf(name);
    const query_lower = toLowerBuf(query);

    // Exact match
    if (std.mem.eql(u8, name_lower[0..name.len], query_lower[0..query.len])) return 1000;

    // Starts with
    if (name.len >= query.len and std.mem.eql(u8, name_lower[0..query.len], query_lower[0..query.len])) return 900;

    // Contains
    if (std.mem.indexOf(u8, name_lower[0..name.len], query_lower[0..query.len]) != null) return 800;

    // Fuzzy match - all query chars appear in order
    var qi: usize = 0;
    var score: u32 = 0;
    for (name) |char| {
        if (qi < query.len and toLower(char) == toLower(query[qi])) {
            qi += 1;
            score += 10;
        }
    }

    if (qi == query.len) {
        return score;
    }

    return 0;
}

fn toLower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

fn toLowerBuf(s: []const u8) [256]u8 {
    var buf: [256]u8 = undefined;
    const len = @min(s.len, 256);
    for (0..len) |i| {
        buf[i] = toLower(s[i]);
    }
    return buf;
}

test "fuzzy match exact" {
    const testing = std.testing;
    try testing.expectEqual(@as(u32, 1000), fuzzyMatch("main.zig", "main.zig"));
}

test "fuzzy match starts with" {
    const testing = std.testing;
    try testing.expectEqual(@as(u32, 900), fuzzyMatch("main.zig", "main"));
}

test "fuzzy match contains" {
    const testing = std.testing;
    try testing.expectEqual(@as(u32, 800), fuzzyMatch("my_main_file.zig", "main"));
}

test "fuzzy match chars in order" {
    const testing = std.testing;
    const score = fuzzyMatch("main.zig", "mz");
    try testing.expect(score > 0);
    try testing.expect(score < 800);
}

test "fuzzy match no match" {
    const testing = std.testing;
    try testing.expectEqual(@as(u32, 0), fuzzyMatch("main.zig", "xyz"));
}

test "fuzzy match case insensitive" {
    const testing = std.testing;
    try testing.expectEqual(@as(u32, 1000), fuzzyMatch("Main.zig", "main.zig"));
    try testing.expectEqual(@as(u32, 1000), fuzzyMatch("MAIN.ZIG", "main.zig"));
}
