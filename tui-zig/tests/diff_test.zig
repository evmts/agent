const std = @import("std");
const diff = @import("../src/render/diff.zig");
const Diff = diff.Diff;
const DiffStats = diff.DiffStats;
const Line = diff.Line;

// Test: Basic diff parsing
test "parse simple unified diff" {
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

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("test.txt", parsed.old_file.?);
    try std.testing.expectEqualStrings("test.txt", parsed.new_file.?);
    try std.testing.expectEqual(@as(usize, 1), parsed.hunks.items.len);

    const hunk = parsed.hunks.items[0];
    try std.testing.expectEqual(@as(u32, 1), hunk.old_start);
    try std.testing.expectEqual(@as(u32, 3), hunk.old_count);
    try std.testing.expectEqual(@as(u32, 1), hunk.new_start);
    try std.testing.expectEqual(@as(u32, 3), hunk.new_count);
}

// Test: Multiple hunks
test "parse diff with multiple hunks" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/multi.txt
        \\+++ b/multi.txt
        \\@@ -1,3 +1,3 @@
        \\ line1
        \\-old line1
        \\+new line1
        \\ line3
        \\@@ -10,2 +10,3 @@
        \\ line10
        \\+added line
        \\ line11
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.hunks.items.len);

    const hunk1 = parsed.hunks.items[0];
    try std.testing.expectEqual(@as(u32, 1), hunk1.old_start);
    try std.testing.expectEqual(@as(u32, 3), hunk1.old_count);

    const hunk2 = parsed.hunks.items[1];
    try std.testing.expectEqual(@as(u32, 10), hunk2.old_start);
    try std.testing.expectEqual(@as(u32, 2), hunk2.old_count);
}

// Test: Line kinds
test "parse line kinds correctly" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/test.txt
        \\+++ b/test.txt
        \\@@ -1,4 +1,4 @@
        \\ context line
        \\-deleted line
        \\+added line
        \\ another context
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    const hunk = parsed.hunks.items[0];
    // Skip header (first line)
    try std.testing.expectEqual(Line.Kind.header, hunk.lines.items[0].kind);
    try std.testing.expectEqual(Line.Kind.context, hunk.lines.items[1].kind);
    try std.testing.expectEqual(Line.Kind.deletion, hunk.lines.items[2].kind);
    try std.testing.expectEqual(Line.Kind.addition, hunk.lines.items[3].kind);
    try std.testing.expectEqual(Line.Kind.context, hunk.lines.items[4].kind);
}

// Test: Statistics
test "calculate diff statistics" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/test.txt
        \\+++ b/test.txt
        \\@@ -1,5 +1,6 @@
        \\ line1
        \\-old line1
        \\-old line2
        \\+new line1
        \\+new line2
        \\+new line3
        \\ line3
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    const stats = parsed.getStats();
    try std.testing.expectEqual(@as(u32, 3), stats.additions);
    try std.testing.expectEqual(@as(u32, 2), stats.deletions);
    try std.testing.expectEqual(@as(u32, 1), stats.files_changed);
}

// Test: New file
test "parse new file diff" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- /dev/null
        \\+++ b/newfile.txt
        \\@@ -0,0 +1,3 @@
        \\+first line
        \\+second line
        \\+third line
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), parsed.old_file);
    try std.testing.expectEqualStrings("newfile.txt", parsed.new_file.?);

    const stats = parsed.getStats();
    try std.testing.expectEqual(@as(u32, 3), stats.additions);
    try std.testing.expectEqual(@as(u32, 0), stats.deletions);
}

// Test: Deleted file
test "parse deleted file diff" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/oldfile.txt
        \\+++ /dev/null
        \\@@ -1,3 +0,0 @@
        \\-first line
        \\-second line
        \\-third line
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("oldfile.txt", parsed.old_file.?);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.new_file);

    const stats = parsed.getStats();
    try std.testing.expectEqual(@as(u32, 0), stats.additions);
    try std.testing.expectEqual(@as(u32, 3), stats.deletions);
}

// Test: Empty diff
test "parse empty diff" {
    const allocator = std.testing.allocator;
    var parsed = try diff.parse(allocator, "");
    defer parsed.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), parsed.old_file);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.new_file);
    try std.testing.expectEqual(@as(usize, 0), parsed.hunks.items.len);

    const stats = parsed.getStats();
    try std.testing.expectEqual(@as(u32, 0), stats.additions);
    try std.testing.expectEqual(@as(u32, 0), stats.deletions);
    try std.testing.expectEqual(@as(u32, 0), stats.files_changed);
}

// Test: Hunk with single line count (no comma)
test "parse hunk header with single line" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/test.txt
        \\+++ b/test.txt
        \\@@ -1 +1 @@
        \\-old
        \\+new
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    const hunk = parsed.hunks.items[0];
    try std.testing.expectEqual(@as(u32, 1), hunk.old_start);
    try std.testing.expectEqual(@as(u32, 1), hunk.old_count);
    try std.testing.expectEqual(@as(u32, 1), hunk.new_start);
    try std.testing.expectEqual(@as(u32, 1), hunk.new_count);
}

// Test: Binary file (should parse file headers but no hunks)
test "parse binary file marker" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/image.png
        \\+++ b/image.png
        \\Binary files differ
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("image.png", parsed.old_file.?);
    try std.testing.expectEqualStrings("image.png", parsed.new_file.?);
    try std.testing.expectEqual(@as(usize, 0), parsed.hunks.items.len);
}

// Test: Large line counts
test "parse diff with large line counts" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/big.txt
        \\+++ b/big.txt
        \\@@ -1234,567 +1234,568 @@
        \\ context
        \\+added
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    const hunk = parsed.hunks.items[0];
    try std.testing.expectEqual(@as(u32, 1234), hunk.old_start);
    try std.testing.expectEqual(@as(u32, 567), hunk.old_count);
    try std.testing.expectEqual(@as(u32, 1234), hunk.new_start);
    try std.testing.expectEqual(@as(u32, 568), hunk.new_count);
}

// Test: Content extraction
test "extract line content correctly" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/test.txt
        \\+++ b/test.txt
        \\@@ -1,2 +1,2 @@
        \\-old content here
        \\+new content here
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    const hunk = parsed.hunks.items[0];
    // Skip header
    try std.testing.expectEqualStrings("old content here", hunk.lines.items[1].content);
    try std.testing.expectEqualStrings("new content here", hunk.lines.items[2].content);
}

// Test: Whitespace in diff
test "handle whitespace in content" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/test.txt
        \\+++ b/test.txt
        \\@@ -1,2 +1,2 @@
        \\-    indented line
        \\+        more indented
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    const hunk = parsed.hunks.items[0];
    // Skip header
    try std.testing.expectEqualStrings("    indented line", hunk.lines.items[1].content);
    try std.testing.expectEqualStrings("        more indented", hunk.lines.items[2].content);
}

// Test: Realistic git diff
test "parse realistic git diff output" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\diff --git a/src/main.zig b/src/main.zig
        \\index abc123..def456 100644
        \\--- a/src/main.zig
        \\+++ b/src/main.zig
        \\@@ -10,7 +10,8 @@ const std = @import("std");
        \\
        \\ pub fn main() !void {
        \\     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\-    defer _ = gpa.deinit();
        \\+    defer {
        \\+        _ = gpa.deinit();
        \\+    }
        \\
        \\     const allocator = gpa.allocator();
        \\ }
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("src/main.zig", parsed.old_file.?);
    try std.testing.expectEqualStrings("src/main.zig", parsed.new_file.?);
    try std.testing.expectEqual(@as(usize, 1), parsed.hunks.items.len);

    const stats = parsed.getStats();
    try std.testing.expectEqual(@as(u32, 3), stats.additions);
    try std.testing.expectEqual(@as(u32, 1), stats.deletions);
}

// Test: Empty lines in hunk
test "parse hunks with empty lines" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/test.txt
        \\+++ b/test.txt
        \\@@ -1,4 +1,4 @@
        \\ line1
        \\-
        \\+
        \\ line4
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    const hunk = parsed.hunks.items[0];
    // Lines should include empty lines
    try std.testing.expectEqual(@as(usize, 5), hunk.lines.items.len); // header + 4 lines
}

// Test: No newline at end
test "parse diff without trailing newline" {
    const allocator = std.testing.allocator;
    const diff_text =
        \\--- a/test.txt
        \\+++ b/test.txt
        \\@@ -1,1 +1,1 @@
        \\-old
        \\+new
    ; // No newline at end

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.hunks.items.len);
    const hunk = parsed.hunks.items[0];
    // header + 2 lines
    try std.testing.expectEqual(@as(usize, 3), hunk.lines.items.len);
}

// Test: Complex multi-file scenario
test "parse only first file in multi-file diff" {
    const allocator = std.testing.allocator;
    // Note: Current implementation processes single file at a time
    // This test verifies it handles the first file correctly
    const diff_text =
        \\--- a/file1.txt
        \\+++ b/file1.txt
        \\@@ -1,2 +1,2 @@
        \\-old1
        \\+new1
        \\ keep1
    ;

    var parsed = try diff.parse(allocator, diff_text);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("file1.txt", parsed.old_file.?);
    try std.testing.expectEqualStrings("file1.txt", parsed.new_file.?);
}
