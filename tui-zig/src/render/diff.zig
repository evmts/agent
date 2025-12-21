const std = @import("std");

/// Unified diff parser and data structures
/// Parses unified diff format (git diff output) into structured data

/// A complete diff with all hunks for one or more files
pub const Diff = struct {
    old_file: ?[]const u8,
    new_file: ?[]const u8,
    hunks: std.ArrayList(Hunk),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Diff {
        return .{
            .old_file = null,
            .new_file = null,
            .hunks = std.ArrayList(Hunk).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Diff) void {
        for (self.hunks.items) |*hunk| {
            hunk.deinit();
        }
        self.hunks.deinit(self.allocator);
        if (self.old_file) |path| {
            self.allocator.free(path);
        }
        if (self.new_file) |path| {
            self.allocator.free(path);
        }
    }

    /// Get diff statistics
    pub fn getStats(self: *const Diff) DiffStats {
        var stats = DiffStats{};
        for (self.hunks.items) |hunk| {
            for (hunk.lines.items) |line| {
                switch (line.kind) {
                    .addition => stats.additions += 1,
                    .deletion => stats.deletions += 1,
                    .context => {},
                    .header => {},
                }
            }
        }
        if (self.new_file != null or self.old_file != null) {
            stats.files_changed = 1;
        }
        return stats;
    }
};

/// Statistics about a diff
pub const DiffStats = struct {
    additions: u32 = 0,
    deletions: u32 = 0,
    files_changed: u32 = 0,
};

/// A single hunk in the diff (contiguous block of changes)
pub const Hunk = struct {
    old_start: u32,
    old_count: u32,
    new_start: u32,
    new_count: u32,
    lines: std.ArrayList(Line),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, old_start: u32, old_count: u32, new_start: u32, new_count: u32) Hunk {
        return .{
            .old_start = old_start,
            .old_count = old_count,
            .new_start = new_start,
            .new_count = new_count,
            .lines = std.ArrayList(Line).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Hunk) void {
        for (self.lines.items) |*line| {
            self.allocator.free(line.content);
        }
        self.lines.deinit(self.allocator);
    }
};

/// A single line in a diff hunk
pub const Line = struct {
    kind: Kind,
    content: []const u8,

    pub const Kind = enum {
        context, // unchanged line (space prefix)
        addition, // added line (+ prefix)
        deletion, // removed line (- prefix)
        header, // @@ hunk header
    };
};

/// Parse a unified diff from text
pub fn parse(allocator: std.mem.Allocator, diff_text: []const u8) !Diff {
    var diff = Diff.init(allocator);
    errdefer diff.deinit();

    var lines_iter = std.mem.splitScalar(u8, diff_text, '\n');
    var current_hunk: ?Hunk = null;

    while (lines_iter.next()) |line_raw| {
        // Trim trailing whitespace
        const line = std.mem.trimRight(u8, line_raw, " \t\r");
        if (line.len == 0) continue;

        // Parse file headers
        if (std.mem.startsWith(u8, line, "--- ")) {
            const path = std.mem.trimLeft(u8, line[4..], " \t");
            // Skip "a/" prefix if present (git diff format)
            const clean_path = if (std.mem.startsWith(u8, path, "a/"))
                path[2..]
            else if (std.mem.eql(u8, path, "/dev/null"))
                null
            else
                path;

            if (clean_path) |p| {
                diff.old_file = try allocator.dupe(u8, p);
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "+++ ")) {
            const path = std.mem.trimLeft(u8, line[4..], " \t");
            // Skip "b/" prefix if present (git diff format)
            const clean_path = if (std.mem.startsWith(u8, path, "b/"))
                path[2..]
            else if (std.mem.eql(u8, path, "/dev/null"))
                null
            else
                path;

            if (clean_path) |p| {
                diff.new_file = try allocator.dupe(u8, p);
            }
            continue;
        }

        // Parse hunk header: @@ -old_start,old_count +new_start,new_count @@
        if (std.mem.startsWith(u8, line, "@@")) {
            // Save previous hunk if exists
            if (current_hunk) |*hunk| {
                try diff.hunks.append(allocator, hunk.*);
            }

            // Parse header
            const header_info = try parseHunkHeader(line);
            current_hunk = Hunk.init(
                allocator,
                header_info.old_start,
                header_info.old_count,
                header_info.new_start,
                header_info.new_count,
            );

            // Add the header as a line
            if (current_hunk) |*hunk| {
                try hunk.lines.append(allocator, .{
                    .kind = .header,
                    .content = try allocator.dupe(u8, line),
                });
            }
            continue;
        }

        // Parse diff lines
        if (current_hunk) |*hunk| {
            if (line.len == 0) continue;

            const first_char = line[0];
            const content = if (line.len > 1) line[1..] else "";

            const kind: Line.Kind = switch (first_char) {
                '+' => .addition,
                '-' => .deletion,
                ' ' => .context,
                else => continue, // Skip unknown lines
            };

            try hunk.lines.append(allocator, .{
                .kind = kind,
                .content = try allocator.dupe(u8, content),
            });
        }
    }

    // Append final hunk
    if (current_hunk) |*hunk| {
        try diff.hunks.append(allocator, hunk.*);
    }

    return diff;
}

/// Hunk header info parsed from @@ line
const HunkHeader = struct {
    old_start: u32,
    old_count: u32,
    new_start: u32,
    new_count: u32,
};

/// Parse hunk header like "@@ -1,7 +1,6 @@"
fn parseHunkHeader(line: []const u8) !HunkHeader {
    // Find the ranges between @@ and @@
    var iter = std.mem.splitSequence(u8, line, "@@");
    _ = iter.next(); // Skip first empty part
    const range_part = iter.next() orelse return error.InvalidHunkHeader;

    // Split by space to get old and new ranges
    var range_iter = std.mem.splitScalar(u8, std.mem.trim(u8, range_part, " \t"), ' ');
    const old_range = range_iter.next() orelse return error.InvalidHunkHeader;
    const new_range = range_iter.next() orelse return error.InvalidHunkHeader;

    // Parse old range: -start,count or -start
    const old = try parseRange(old_range[1..]); // Skip '-'
    // Parse new range: +start,count or +start
    const new = try parseRange(new_range[1..]); // Skip '+'

    return .{
        .old_start = old.start,
        .old_count = old.count,
        .new_start = new.start,
        .new_count = new.count,
    };
}

const RangeInfo = struct {
    start: u32,
    count: u32,
};

/// Parse a range like "1,7" or "1"
fn parseRange(range: []const u8) !RangeInfo {
    var iter = std.mem.splitScalar(u8, range, ',');
    const start_str = iter.next() orelse return error.InvalidRange;
    const start = try std.fmt.parseInt(u32, start_str, 10);

    const count_str = iter.next();
    const count = if (count_str) |cs|
        try std.fmt.parseInt(u32, cs, 10)
    else
        1; // Default count is 1 if not specified

    return .{ .start = start, .count = count };
}

// Tests
test "parse simple diff" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/test.txt
        \\+++ b/test.txt
        \\@@ -1,3 +1,3 @@
        \\ line1
        \\-old line
        \\+new line
        \\ line3
    ;

    var diff = try parse(allocator, diff_text);
    defer diff.deinit();

    try std.testing.expectEqualStrings("test.txt", diff.old_file.?);
    try std.testing.expectEqualStrings("test.txt", diff.new_file.?);
    try std.testing.expectEqual(@as(usize, 1), diff.hunks.items.len);

    const hunk = diff.hunks.items[0];
    try std.testing.expectEqual(@as(u32, 1), hunk.old_start);
    try std.testing.expectEqual(@as(u32, 3), hunk.old_count);
    try std.testing.expectEqual(@as(u32, 1), hunk.new_start);
    try std.testing.expectEqual(@as(u32, 3), hunk.new_count);

    // Check lines (skip header)
    try std.testing.expectEqual(@as(usize, 5), hunk.lines.items.len); // header + 4 lines
    try std.testing.expectEqual(Line.Kind.header, hunk.lines.items[0].kind);
    try std.testing.expectEqual(Line.Kind.context, hunk.lines.items[1].kind);
    try std.testing.expectEqual(Line.Kind.deletion, hunk.lines.items[2].kind);
    try std.testing.expectEqual(Line.Kind.addition, hunk.lines.items[3].kind);
    try std.testing.expectEqual(Line.Kind.context, hunk.lines.items[4].kind);
}

test "get diff stats" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/test.txt
        \\+++ b/test.txt
        \\@@ -1,3 +1,4 @@
        \\ line1
        \\-old line1
        \\-old line2
        \\+new line1
        \\+new line2
        \\+new line3
        \\ line3
    ;

    var diff = try parse(allocator, diff_text);
    defer diff.deinit();

    const stats = diff.getStats();
    try std.testing.expectEqual(@as(u32, 3), stats.additions);
    try std.testing.expectEqual(@as(u32, 2), stats.deletions);
    try std.testing.expectEqual(@as(u32, 1), stats.files_changed);
}

test "parse empty diff" {
    const allocator = std.testing.allocator;
    var diff = try parse(allocator, "");
    defer diff.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), diff.old_file);
    try std.testing.expectEqual(@as(?[]const u8, null), diff.new_file);
    try std.testing.expectEqual(@as(usize, 0), diff.hunks.items.len);
}

test "parse new file" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- /dev/null
        \\+++ b/newfile.txt
        \\@@ -0,0 +1,2 @@
        \\+first line
        \\+second line
    ;

    var diff = try parse(allocator, diff_text);
    defer diff.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), diff.old_file);
    try std.testing.expectEqualStrings("newfile.txt", diff.new_file.?);

    const stats = diff.getStats();
    try std.testing.expectEqual(@as(u32, 2), stats.additions);
    try std.testing.expectEqual(@as(u32, 0), stats.deletions);
}

test "parse deleted file" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/oldfile.txt
        \\+++ /dev/null
        \\@@ -1,2 +0,0 @@
        \\-first line
        \\-second line
    ;

    var diff = try parse(allocator, diff_text);
    defer diff.deinit();

    try std.testing.expectEqualStrings("oldfile.txt", diff.old_file.?);
    try std.testing.expectEqual(@as(?[]const u8, null), diff.new_file);

    const stats = diff.getStats();
    try std.testing.expectEqual(@as(u32, 0), stats.additions);
    try std.testing.expectEqual(@as(u32, 2), stats.deletions);
}
