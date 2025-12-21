# 11: Diff Renderer

## Goal

Implement unified diff rendering with color-coded additions, deletions, and context lines.

## Context

- File changes from agent are shown as diffs
- Standard unified diff format
- Reference: codex diff rendering, `/Users/williamcory/plue/tui/src/render/tools.ts`

## Diff Format

```diff
--- a/path/to/file.js
+++ b/path/to/file.js
@@ -10,7 +10,8 @@ function example() {
     context line
-    deleted line
+    added line
+    another added line
     more context
```

## Tasks

### 1. Create Diff Parser (src/render/diff.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const DiffRenderer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiffRenderer {
        return .{ .allocator = allocator };
    }

    /// Parse unified diff into structured format
    pub fn parse(self: *DiffRenderer, diff_text: []const u8) !Diff {
        var diff = Diff{
            .hunks = std.ArrayList(Hunk).init(self.allocator),
        };

        var lines = std.mem.split(u8, diff_text, "\n");
        var current_hunk: ?*Hunk = null;

        while (lines.next()) |line| {
            // File headers
            if (std.mem.startsWith(u8, line, "--- ")) {
                diff.old_file = try self.allocator.dupe(u8, line[4..]);
                continue;
            }
            if (std.mem.startsWith(u8, line, "+++ ")) {
                diff.new_file = try self.allocator.dupe(u8, line[4..]);
                continue;
            }

            // Hunk header
            if (std.mem.startsWith(u8, line, "@@ ")) {
                const hunk = try self.parseHunkHeader(line);
                try diff.hunks.append(hunk);
                current_hunk = &diff.hunks.items[diff.hunks.items.len - 1];
                continue;
            }

            // Diff lines
            if (current_hunk) |hunk| {
                if (line.len == 0) {
                    try hunk.lines.append(.{ .kind = .context, .content = "" });
                } else {
                    const kind: DiffLine.Kind = switch (line[0]) {
                        '+' => .addition,
                        '-' => .deletion,
                        else => .context,
                    };
                    const content = if (line.len > 1) line[1..] else "";
                    try hunk.lines.append(.{
                        .kind = kind,
                        .content = try self.allocator.dupe(u8, content),
                    });
                }
            }
        }

        return diff;
    }

    fn parseHunkHeader(self: *DiffRenderer, line: []const u8) !Hunk {
        // Parse @@ -old_start,old_count +new_start,new_count @@ context
        var hunk = Hunk{
            .lines = std.ArrayList(DiffLine).init(self.allocator),
        };

        // Find the range markers
        if (std.mem.indexOf(u8, line, "-")) |minus_idx| {
            const after_minus = line[minus_idx + 1 ..];
            if (std.mem.indexOf(u8, after_minus, ",")) |comma_idx| {
                hunk.old_start = std.fmt.parseInt(u32, after_minus[0..comma_idx], 10) catch 0;
                const after_comma = after_minus[comma_idx + 1 ..];
                if (std.mem.indexOf(u8, after_comma, " ")) |space_idx| {
                    hunk.old_count = std.fmt.parseInt(u32, after_comma[0..space_idx], 10) catch 0;
                }
            }
        }

        if (std.mem.indexOf(u8, line, "+")) |plus_idx| {
            const after_plus = line[plus_idx + 1 ..];
            if (std.mem.indexOf(u8, after_plus, ",")) |comma_idx| {
                hunk.new_start = std.fmt.parseInt(u32, after_plus[0..comma_idx], 10) catch 0;
                const after_comma = after_plus[comma_idx + 1 ..];
                if (std.mem.indexOf(u8, after_comma, " ")) |space_idx| {
                    hunk.new_count = std.fmt.parseInt(u32, after_comma[0..space_idx], 10) catch 0;
                }
            }
        }

        // Extract context after second @@
        const parts = std.mem.split(u8, line, "@@");
        _ = parts.next(); // Skip first
        _ = parts.next(); // Skip range
        if (parts.next()) |context| {
            hunk.context = try self.allocator.dupe(u8, std.mem.trim(u8, context, " "));
        }

        return hunk;
    }

    /// Render diff to terminal segments
    pub fn render(self: *DiffRenderer, diff: Diff, options: RenderOptions) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);

        // File header
        if (diff.new_file) |file| {
            const display_file = if (std.mem.startsWith(u8, file, "b/")) file[2..] else file;
            try segments.append(.{
                .text = try std.fmt.allocPrint(self.allocator, "─── {s} ───\n", .{display_file}),
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Stats
        const stats = diff.getStats();
        if (stats.additions > 0 or stats.deletions > 0) {
            try segments.append(.{
                .text = try std.fmt.allocPrint(
                    self.allocator,
                    "+{d} -{d}\n",
                    .{ stats.additions, stats.deletions },
                ),
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Hunks
        for (diff.hunks.items) |hunk| {
            try self.renderHunk(&segments, hunk, options);
        }

        return segments.toOwnedSlice();
    }

    fn renderHunk(
        self: *DiffRenderer,
        segments: *std.ArrayList(Segment),
        hunk: Hunk,
        options: RenderOptions,
    ) !void {
        // Hunk header
        try segments.append(.{
            .text = try std.fmt.allocPrint(
                self.allocator,
                "@@ -{d},{d} +{d},{d} @@ {s}\n",
                .{ hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count, hunk.context orelse "" },
            ),
            .style = .{ .fg = .{ .index = 14 }, .dim = true },
        });

        // Lines
        var old_line = hunk.old_start;
        var new_line = hunk.new_start;

        for (hunk.lines.items) |line| {
            // Line number gutter
            if (options.show_line_numbers) {
                const old_num = if (line.kind != .addition) old_line else 0;
                const new_num = if (line.kind != .deletion) new_line else 0;

                try segments.append(.{
                    .text = try std.fmt.allocPrint(
                        self.allocator,
                        "{d:>4} {d:>4} ",
                        .{ old_num, new_num },
                    ),
                    .style = .{ .fg = .{ .index = 8 }, .dim = true },
                });
            }

            // Diff marker and content
            switch (line.kind) {
                .addition => {
                    try segments.append(.{
                        .text = "+",
                        .style = .{ .fg = .{ .index = 10 }, .bold = true },
                    });
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, line.content),
                        .style = .{ .fg = .{ .index = 10 }, .bg = if (options.highlight_bg) .{ .rgb = .{ 0, 50, 0 } } else .default },
                    });
                },
                .deletion => {
                    try segments.append(.{
                        .text = "-",
                        .style = .{ .fg = .{ .index = 9 }, .bold = true },
                    });
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, line.content),
                        .style = .{ .fg = .{ .index = 9 }, .bg = if (options.highlight_bg) .{ .rgb = .{ 50, 0, 0 } } else .default },
                    });
                },
                .context => {
                    try segments.append(.{
                        .text = " ",
                        .style = .{},
                    });
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, line.content),
                        .style = .{ .fg = .{ .index = 8 } },
                    });
                },
            }

            try segments.append(.{ .text = "\n", .style = .{} });

            // Update line numbers
            if (line.kind != .addition) old_line += 1;
            if (line.kind != .deletion) new_line += 1;
        }
    }
};

pub const Diff = struct {
    old_file: ?[]const u8 = null,
    new_file: ?[]const u8 = null,
    hunks: std.ArrayList(Hunk),

    pub fn getStats(self: Diff) Stats {
        var stats = Stats{};
        for (self.hunks.items) |hunk| {
            for (hunk.lines.items) |line| {
                switch (line.kind) {
                    .addition => stats.additions += 1,
                    .deletion => stats.deletions += 1,
                    .context => {},
                }
            }
        }
        return stats;
    }

    pub const Stats = struct {
        additions: u32 = 0,
        deletions: u32 = 0,
    };
};

pub const Hunk = struct {
    old_start: u32 = 0,
    old_count: u32 = 0,
    new_start: u32 = 0,
    new_count: u32 = 0,
    context: ?[]const u8 = null,
    lines: std.ArrayList(DiffLine),
};

pub const DiffLine = struct {
    kind: Kind,
    content: []const u8,

    pub const Kind = enum {
        addition,
        deletion,
        context,
    };
};

pub const Segment = struct {
    text: []const u8,
    style: vaxis.Cell.Style = .{},
};

pub const RenderOptions = struct {
    show_line_numbers: bool = false,
    highlight_bg: bool = true,
    max_context_lines: u32 = 3,
    word_diff: bool = false,
};
```

### 2. Create Diff Widget (src/widgets/diff_view.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const diff = @import("../render/diff.zig");
const DiffRenderer = diff.DiffRenderer;
const Diff = diff.Diff;
const Segment = diff.Segment;

pub const DiffView = struct {
    allocator: std.mem.Allocator,
    renderer: DiffRenderer,
    diff_text: ?[]const u8 = null,
    parsed_diff: ?Diff = null,
    rendered_segments: ?[]Segment = null,
    scroll_offset: usize = 0,
    show_line_numbers: bool = true,
    collapsed: bool = false,

    pub fn init(allocator: std.mem.Allocator) DiffView {
        return .{
            .allocator = allocator,
            .renderer = DiffRenderer.init(allocator),
        };
    }

    pub fn setDiff(self: *DiffView, diff_text: []const u8) !void {
        self.diff_text = diff_text;
        self.parsed_diff = try self.renderer.parse(diff_text);
        self.rendered_segments = try self.renderer.render(
            self.parsed_diff.?,
            .{ .show_line_numbers = self.show_line_numbers },
        );
        self.scroll_offset = 0;
    }

    pub fn widget(self: *DiffView) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = DiffView.handleEvent,
            .drawFn = DiffView.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *DiffView = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (key.matches('l', .{})) {
                    self.show_line_numbers = !self.show_line_numbers;
                    if (self.parsed_diff) |d| {
                        self.rendered_segments = try self.renderer.render(
                            d,
                            .{ .show_line_numbers = self.show_line_numbers },
                        );
                    }
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.space, .{})) {
                    self.collapsed = !self.collapsed;
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *DiffView = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        if (self.collapsed) {
            // Show collapsed summary
            const summary = if (self.parsed_diff) |d|
                try std.fmt.allocPrint(ctx.arena, "▶ {s} (+{d}/-{d})", .{
                    d.new_file orelse "file",
                    d.getStats().additions,
                    d.getStats().deletions,
                })
            else
                "▶ No diff";

            for (summary, 0..) |char, i| {
                if (i >= size.width) break;
                surface.writeCell(@intCast(i), 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 14 } },
                });
            }

            return surface;
        }

        // Render full diff
        if (self.rendered_segments) |segments| {
            var row: u16 = 0;
            var col: u16 = 0;

            for (segments) |segment| {
                for (segment.text) |char| {
                    if (row >= size.height) break;

                    if (char == '\n') {
                        row += 1;
                        col = 0;
                        continue;
                    }

                    if (col >= size.width) {
                        row += 1;
                        col = 0;
                    }

                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = segment.style,
                    });
                    col += 1;
                }
            }
        } else {
            // No diff to display
            const msg = "No diff available";
            for (msg, 0..) |char, i| {
                surface.writeCell(@intCast(i), 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 }, .italic = true },
                });
            }
        }

        return surface;
    }

    pub fn getHeight(self: *DiffView) u16 {
        if (self.collapsed) return 1;

        if (self.rendered_segments) |segments| {
            var height: u16 = 1;
            for (segments) |segment| {
                for (segment.text) |char| {
                    if (char == '\n') height += 1;
                }
            }
            return height;
        }

        return 1;
    }
};
```

### 3. Create Side-by-Side Diff (src/widgets/side_by_side_diff.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const diff = @import("../render/diff.zig");
const Diff = diff.Diff;
const Hunk = diff.Hunk;

pub const SideBySideDiff = struct {
    allocator: std.mem.Allocator,
    parsed_diff: ?Diff = null,
    scroll_offset: usize = 0,
    gutter_width: u16 = 5,

    pub fn init(allocator: std.mem.Allocator) SideBySideDiff {
        return .{ .allocator = allocator };
    }

    pub fn setDiff(self: *SideBySideDiff, parsed_diff: Diff) void {
        self.parsed_diff = parsed_diff;
        self.scroll_offset = 0;
    }

    pub fn widget(self: *SideBySideDiff) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = SideBySideDiff.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *SideBySideDiff = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        if (self.parsed_diff == null) {
            return surface;
        }

        const parsed = self.parsed_diff.?;
        const half_width = (size.width - 1) / 2;

        // Draw separator
        for (0..size.height) |row| {
            surface.writeCell(half_width, @intCast(row), .{
                .char = .{ .grapheme = "│", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Draw headers
        const old_header = parsed.old_file orelse "(old)";
        const new_header = parsed.new_file orelse "(new)";

        self.drawText(&surface, old_header, 0, 0, half_width, .{ .fg = .{ .index = 9 }, .bold = true });
        self.drawText(&surface, new_header, half_width + 1, 0, half_width, .{ .fg = .{ .index = 10 }, .bold = true });

        // Draw hunks
        var row: u16 = 1;
        for (parsed.hunks.items) |hunk| {
            row = self.drawHunkSideBySide(&surface, hunk, row, half_width, size.height);
            if (row >= size.height) break;
        }

        return surface;
    }

    fn drawHunkSideBySide(
        self: *SideBySideDiff,
        surface: *vxfw.Surface,
        hunk: Hunk,
        start_row: u16,
        half_width: u16,
        max_height: u16,
    ) u16 {
        var row = start_row;
        var old_lines = std.ArrayList(struct { num: u32, text: []const u8 }).init(self.allocator);
        var new_lines = std.ArrayList(struct { num: u32, text: []const u8 }).init(self.allocator);
        defer old_lines.deinit();
        defer new_lines.deinit();

        var old_num = hunk.old_start;
        var new_num = hunk.new_start;

        // Separate old and new lines
        for (hunk.lines.items) |line| {
            switch (line.kind) {
                .deletion => {
                    old_lines.append(.{ .num = old_num, .text = line.content }) catch {};
                    old_num += 1;
                },
                .addition => {
                    new_lines.append(.{ .num = new_num, .text = line.content }) catch {};
                    new_num += 1;
                },
                .context => {
                    // Align both sides
                    while (old_lines.items.len < new_lines.items.len) {
                        old_lines.append(.{ .num = 0, .text = "" }) catch {};
                    }
                    while (new_lines.items.len < old_lines.items.len) {
                        new_lines.append(.{ .num = 0, .text = "" }) catch {};
                    }

                    // Draw accumulated
                    for (old_lines.items, new_lines.items) |old, new| {
                        if (row >= max_height) break;

                        // Left side (old/deleted)
                        self.drawDiffLine(surface, old.num, old.text, 0, row, half_width, true);

                        // Right side (new/added)
                        self.drawDiffLine(surface, new.num, new.text, half_width + 1, row, half_width, false);

                        row += 1;
                    }

                    old_lines.clearRetainingCapacity();
                    new_lines.clearRetainingCapacity();

                    // Draw context line on both sides
                    if (row < max_height) {
                        self.drawContextLine(surface, old_num, new_num, line.content, 0, row, half_width);
                        row += 1;
                    }

                    old_num += 1;
                    new_num += 1;
                },
            }
        }

        // Draw remaining lines
        const max_remaining = @max(old_lines.items.len, new_lines.items.len);
        for (0..max_remaining) |i| {
            if (row >= max_height) break;

            if (i < old_lines.items.len) {
                const old = old_lines.items[i];
                self.drawDiffLine(surface, old.num, old.text, 0, row, half_width, true);
            }

            if (i < new_lines.items.len) {
                const new = new_lines.items[i];
                self.drawDiffLine(surface, new.num, new.text, half_width + 1, row, half_width, false);
            }

            row += 1;
        }

        return row;
    }

    fn drawDiffLine(
        self: *SideBySideDiff,
        surface: *vxfw.Surface,
        line_num: u32,
        text: []const u8,
        start_col: u16,
        row: u16,
        width: u16,
        is_deletion: bool,
    ) void {
        const style = if (is_deletion)
            vaxis.Cell.Style{ .fg = .{ .index = 9 } }
        else
            vaxis.Cell.Style{ .fg = .{ .index = 10 } };

        // Line number
        var col = start_col;
        if (line_num > 0) {
            const num_str = std.fmt.allocPrint(self.allocator, "{d:>4} ", .{line_num}) catch "     ";
            for (num_str) |char| {
                if (col >= start_col + width) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
                col += 1;
            }
        } else {
            col += self.gutter_width;
        }

        // Text
        for (text) |char| {
            if (col >= start_col + width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
            col += 1;
        }
    }

    fn drawContextLine(
        self: *SideBySideDiff,
        surface: *vxfw.Surface,
        old_num: u32,
        new_num: u32,
        text: []const u8,
        start_col: u16,
        row: u16,
        width: u16,
    ) void {
        const half = width;
        const style = vaxis.Cell.Style{ .fg = .{ .index = 7 } };

        // Left side
        self.drawText(
            surface,
            std.fmt.allocPrint(self.allocator, "{d:>4} {s}", .{ old_num, text }) catch text,
            start_col,
            row,
            half,
            style,
        );

        // Right side
        self.drawText(
            surface,
            std.fmt.allocPrint(self.allocator, "{d:>4} {s}", .{ new_num, text }) catch text,
            half + 1,
            row,
            half,
            style,
        );
    }

    fn drawText(
        self: *SideBySideDiff,
        surface: *vxfw.Surface,
        text: []const u8,
        start_col: u16,
        row: u16,
        max_width: u16,
        style: vaxis.Cell.Style,
    ) void {
        _ = self;
        var col = start_col;
        for (text) |char| {
            if (col >= start_col + max_width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
            col += 1;
        }
    }
};
```

## Acceptance Criteria

- [ ] Unified diff parsing works correctly
- [ ] Additions shown in green with + prefix
- [ ] Deletions shown in red with - prefix
- [ ] Context lines shown in gray
- [ ] Hunk headers parsed and displayed
- [ ] File headers shown with change stats
- [ ] Line numbers optional (toggle with 'l')
- [ ] Collapse/expand with space key
- [ ] Side-by-side view available
- [ ] Proper line number alignment
- [ ] Background highlighting optional

## Files to Create

1. `tui-zig/src/render/diff.zig`
2. `tui-zig/src/widgets/diff_view.zig`
3. `tui-zig/src/widgets/side_by_side_diff.zig`

## Next

Proceed to `12_tool_visualization.md` for tool call display components.
