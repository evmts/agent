# 16: File Mentions & File Search

## Goal

Implement file mention system (@file syntax) and fuzzy file search popup.

## Context

- Users can reference files with @path/to/file
- Need fuzzy search for finding files
- File content is injected into messages
- Reference: codex file mention handling

## Tasks

### 1. Create File Search (src/utils/file_search.zig)

```zig
const std = @import("std");

pub const FileSearch = struct {
    allocator: std.mem.Allocator,
    root_dir: []const u8,
    results: std.ArrayList(SearchResult),
    cache: std.StringHashMap([]const u8),

    pub const SearchResult = struct {
        path: []const u8,
        relative_path: []const u8,
        is_directory: bool,
        score: u32,
    };

    pub fn init(allocator: std.mem.Allocator, root_dir: []const u8) FileSearch {
        return .{
            .allocator = allocator,
            .root_dir = root_dir,
            .results = std.ArrayList(SearchResult).init(allocator),
            .cache = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *FileSearch) void {
        self.results.deinit();
        self.cache.deinit();
    }

    /// Search for files matching the query
    pub fn search(self: *FileSearch, query: []const u8, max_results: usize) ![]const SearchResult {
        self.results.clearRetainingCapacity();

        if (query.len == 0) {
            // Return recent files or common files
            try self.addCommonFiles();
            return self.results.items[0..@min(max_results, self.results.items.len)];
        }

        // Walk directory tree
        try self.walkDirectory(self.root_dir, query, 0, 5); // Max depth 5

        // Sort by score
        std.sort.sort(SearchResult, self.results.items, {}, struct {
            fn compare(_: void, a: SearchResult, b: SearchResult) bool {
                return a.score > b.score;
            }
        }.compare);

        return self.results.items[0..@min(max_results, self.results.items.len)];
    }

    fn walkDirectory(self: *FileSearch, dir_path: []const u8, query: []const u8, depth: usize, max_depth: usize) !void {
        if (depth > max_depth) return;

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            // Skip hidden files and common ignore patterns
            if (entry.name[0] == '.') continue;
            if (std.mem.eql(u8, entry.name, "node_modules")) continue;
            if (std.mem.eql(u8, entry.name, "zig-cache")) continue;
            if (std.mem.eql(u8, entry.name, "zig-out")) continue;
            if (std.mem.eql(u8, entry.name, ".git")) continue;

            const full_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
            const relative_path = try self.makeRelative(full_path);

            const score = self.fuzzyMatch(entry.name, query);
            if (score > 0) {
                try self.results.append(.{
                    .path = full_path,
                    .relative_path = relative_path,
                    .is_directory = entry.kind == .directory,
                    .score = score,
                });
            }

            // Recurse into directories
            if (entry.kind == .directory) {
                try self.walkDirectory(full_path, query, depth + 1, max_depth);
            }
        }
    }

    fn fuzzyMatch(self: *FileSearch, name: []const u8, query: []const u8) u32 {
        _ = self;
        if (query.len == 0) return 0;

        // Exact match
        if (std.mem.eql(u8, name, query)) return 1000;

        // Starts with
        if (std.mem.startsWith(u8, name, query)) return 900;

        // Contains
        if (std.mem.indexOf(u8, name, query) != null) return 800;

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

    fn makeRelative(self: *FileSearch, path: []const u8) ![]const u8 {
        if (std.mem.startsWith(u8, path, self.root_dir)) {
            const rel = path[self.root_dir.len..];
            if (rel.len > 0 and rel[0] == '/') {
                return try self.allocator.dupe(u8, rel[1..]);
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
        };

        for (common_files) |file| {
            const full_path = try std.fs.path.join(self.allocator, &.{ self.root_dir, file });
            if (std.fs.cwd().access(full_path, .{})) {
                try self.results.append(.{
                    .path = full_path,
                    .relative_path = try self.allocator.dupe(u8, file),
                    .is_directory = false,
                    .score = 100,
                });
            } else |_| {}
        }
    }
};
```

### 2. Create File Search Widget (src/widgets/file_search.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const FileSearch = @import("../utils/file_search.zig").FileSearch;
const SearchResult = @import("../utils/file_search.zig").FileSearch.SearchResult;

pub const FileSearchWidget = struct {
    allocator: std.mem.Allocator,
    search: FileSearch,
    query: std.ArrayList(u8),
    results: []const SearchResult = &.{},
    selected_index: usize = 0,
    on_select: ?*const fn ([]const u8) void = null,
    on_close: ?*const fn () void = null,

    pub fn init(allocator: std.mem.Allocator, root_dir: []const u8) FileSearchWidget {
        return .{
            .allocator = allocator,
            .search = FileSearch.init(allocator, root_dir),
            .query = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *FileSearchWidget) void {
        self.search.deinit();
        self.query.deinit();
    }

    pub fn widget(self: *FileSearchWidget) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = FileSearchWidget.handleEvent,
            .drawFn = FileSearchWidget.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *FileSearchWidget = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.escape, .{})) {
                    if (self.on_close) |cb| cb();
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    if (self.results.len > 0) {
                        if (self.on_select) |cb| {
                            cb(self.results[self.selected_index].relative_path);
                        }
                    }
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.up, .{})) {
                    if (self.selected_index > 0) self.selected_index -= 1;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.down, .{})) {
                    if (self.selected_index < self.results.len - 1) self.selected_index += 1;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.backspace, .{})) {
                    if (self.query.items.len > 0) {
                        _ = self.query.pop();
                        try self.updateResults();
                    }
                    ctx.consumeAndRedraw();
                } else if (key.text) |text| {
                    try self.query.appendSlice(text);
                    try self.updateResults();
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn updateResults(self: *FileSearchWidget) !void {
        self.results = try self.search.search(self.query.items, 15);
        self.selected_index = 0;
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *FileSearchWidget = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        // Modal size
        const modal_width: u16 = @min(60, size.width -| 4);
        const modal_height: u16 = @min(20, size.height -| 4);
        const x = (size.width -| modal_width) / 2;
        const y = (size.height -| modal_height) / 2;

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Dim background
        for (0..size.height) |row| {
            for (0..size.width) |col| {
                surface.writeCell(@intCast(col), @intCast(row), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .bg = .{ .rgb = .{ 0, 0, 0 } }, .dim = true },
                });
            }
        }

        // Draw modal
        try self.drawModal(&surface, x, y, modal_width, modal_height);

        return surface;
    }

    fn drawModal(self: *FileSearchWidget, surface: *vxfw.Surface, x: u16, y: u16, width: u16, height: u16) !void {
        // Background
        for (0..height) |row| {
            for (0..width) |col| {
                surface.writeCell(@intCast(x + col), @intCast(y + row), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .bg = .{ .index = 0 } },
                });
            }
        }

        // Border
        self.drawBorder(surface, x, y, width, height);

        // Title
        const title = "Find File";
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(x + 2 + i), y, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true, .bg = .{ .index = 0 } },
            });
        }

        // Search input
        var col: u16 = x + 2;
        surface.writeCell(col, y + 1, .{
            .char = .{ .grapheme = "🔍", .width = 2 },
            .style = .{ .fg = .{ .index = 14 }, .bg = .{ .index = 0 } },
        });
        col += 3;

        for (self.query.items) |char| {
            surface.writeCell(col, y + 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 15 }, .bg = .{ .index = 0 } },
            });
            col += 1;
        }

        // Cursor
        surface.writeCell(col, y + 1, .{
            .char = .{ .grapheme = "▋", .width = 1 },
            .style = .{ .fg = .{ .index = 14 }, .bg = .{ .index = 0 } },
        });

        // Separator
        for (0..width - 2) |c| {
            surface.writeCell(@intCast(x + 1 + c), y + 2, .{
                .char = .{ .grapheme = "─", .width = 1 },
                .style = .{ .fg = .{ .index = 8 }, .bg = .{ .index = 0 } },
            });
        }

        // Results
        var row: u16 = y + 3;
        for (self.results, 0..) |result, i| {
            if (row >= y + height - 2) break;

            const is_selected = i == self.selected_index;
            const bg: vaxis.Color = if (is_selected) .{ .index = 8 } else .{ .index = 0 };

            // Fill background if selected
            if (is_selected) {
                for (1..width - 1) |c| {
                    surface.writeCell(@intCast(x + c), row, .{
                        .char = .{ .grapheme = " ", .width = 1 },
                        .style = .{ .bg = bg },
                    });
                }
            }

            col = x + 2;

            // Icon
            const icon = if (result.is_directory) "📁" else "📄";
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = icon, .width = 2 },
                .style = .{ .bg = bg },
            });
            col += 3;

            // Path
            for (result.relative_path) |char| {
                if (col >= x + width - 2) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = if (is_selected) .{ .index = 15 } else .{ .index = 7 }, .bg = bg },
                });
                col += 1;
            }

            row += 1;
        }

        // No results message
        if (self.results.len == 0 and self.query.items.len > 0) {
            const msg = "No files found";
            for (msg, 0..) |char, i| {
                surface.writeCell(@intCast(x + 2 + i), y + 4, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 }, .italic = true, .bg = .{ .index = 0 } },
                });
            }
        }

        // Hints
        const hints = "↑↓ navigate  Enter select  Esc cancel";
        for (hints, 0..) |char, i| {
            if (x + 1 + i >= x + width - 1) break;
            surface.writeCell(@intCast(x + 1 + i), y + height - 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 }, .bg = .{ .index = 0 } },
            });
        }
    }

    fn drawBorder(self: *FileSearchWidget, surface: *vxfw.Surface, x: u16, y: u16, width: u16, height: u16) void {
        _ = self;
        const style = vaxis.Cell.Style{ .fg = .{ .index = 14 }, .bg = .{ .index = 0 } };

        // Corners
        surface.writeCell(x, y, .{ .char = .{ .grapheme = "╭", .width = 1 }, .style = style });
        surface.writeCell(x + width - 1, y, .{ .char = .{ .grapheme = "╮", .width = 1 }, .style = style });
        surface.writeCell(x, y + height - 1, .{ .char = .{ .grapheme = "╰", .width = 1 }, .style = style });
        surface.writeCell(x + width - 1, y + height - 1, .{ .char = .{ .grapheme = "╯", .width = 1 }, .style = style });

        // Edges
        for (1..width - 1) |col| {
            surface.writeCell(@intCast(x + col), y, .{ .char = .{ .grapheme = "─", .width = 1 }, .style = style });
            surface.writeCell(@intCast(x + col), y + height - 1, .{ .char = .{ .grapheme = "─", .width = 1 }, .style = style });
        }
        for (1..height - 1) |row| {
            surface.writeCell(x, @intCast(y + row), .{ .char = .{ .grapheme = "│", .width = 1 }, .style = style });
            surface.writeCell(x + width - 1, @intCast(y + row), .{ .char = .{ .grapheme = "│", .width = 1 }, .style = style });
        }
    }
};
```

### 3. Create Mention Parser (src/utils/mentions.zig)

```zig
const std = @import("std");

pub const Mention = struct {
    start: usize,
    end: usize,
    path: []const u8,
};

/// Parse @mentions from text
pub fn parseMentions(allocator: std.mem.Allocator, text: []const u8) ![]Mention {
    var mentions = std.ArrayList(Mention).init(allocator);

    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '@') {
            const start = i;
            i += 1;

            // Read path (until whitespace or special char)
            while (i < text.len and isPathChar(text[i])) {
                i += 1;
            }

            if (i > start + 1) {
                try mentions.append(.{
                    .start = start,
                    .end = i,
                    .path = text[start + 1 .. i],
                });
            }
        } else {
            i += 1;
        }
    }

    return mentions.toOwnedSlice();
}

fn isPathChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or
        c == '/' or c == '.' or c == '-' or c == '_';
}

/// Expand @mentions in text to include file content
pub fn expandMentions(allocator: std.mem.Allocator, text: []const u8, root_dir: []const u8) ![]const u8 {
    const mentions = try parseMentions(allocator, text);
    if (mentions.len == 0) return try allocator.dupe(u8, text);

    var result = std.ArrayList(u8).init(allocator);
    var last_end: usize = 0;

    for (mentions) |mention| {
        // Add text before mention
        try result.appendSlice(text[last_end..mention.start]);

        // Read file content
        const full_path = try std.fs.path.join(allocator, &.{ root_dir, mention.path });
        const content = readFile(allocator, full_path) catch |_| {
            try result.appendSlice("@");
            try result.appendSlice(mention.path);
            try result.appendSlice(" (file not found)");
            last_end = mention.end;
            continue;
        };

        // Add expanded content
        try result.appendSlice("@");
        try result.appendSlice(mention.path);
        try result.appendSlice("\n```\n");
        try result.appendSlice(content);
        try result.appendSlice("\n```\n");

        last_end = mention.end;
    }

    // Add remaining text
    try result.appendSlice(text[last_end..]);

    return result.toOwnedSlice();
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > 1024 * 1024) {
        return error.FileTooLarge;
    }

    return try file.readToEndAlloc(allocator, 1024 * 1024);
}

/// Get @mention at cursor position (for autocomplete)
pub fn getMentionAtCursor(text: []const u8, cursor: usize) ?struct { start: usize, prefix: []const u8 } {
    // Look backwards from cursor for @
    var start = cursor;
    while (start > 0) {
        start -= 1;
        if (text[start] == '@') {
            return .{
                .start = start,
                .prefix = text[start + 1 .. cursor],
            };
        }
        if (!isPathChar(text[start]) and text[start] != '@') {
            break;
        }
    }
    return null;
}
```

## Acceptance Criteria

- [ ] File search walks directory tree
- [ ] Fuzzy matching scores results
- [ ] Ignores hidden files and node_modules
- [ ] Search widget shows modal with results
- [ ] Type to search, arrows to navigate
- [ ] Enter selects file
- [ ] ESC closes popup
- [ ] @mentions parsed from text
- [ ] File content injected with code blocks
- [ ] Autocomplete triggers on @ in composer
- [ ] Non-existent files show error

## Files to Create

1. `tui-zig/src/utils/file_search.zig`
2. `tui-zig/src/widgets/file_search.zig`
3. `tui-zig/src/utils/mentions.zig`

## Next

Proceed to `17_testing_polish.md` for final testing and polish.
