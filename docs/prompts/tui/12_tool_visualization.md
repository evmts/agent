# 12: Tool Call Visualization

## Goal

Implement rich visualization for tool calls including status indicators, argument display, duration tracking, and result previews.

## Context

- Tool calls are key part of agent interactions
- Need to show: tool name, arguments, status, duration, result
- Different tools need different visualizations (grep vs writeFile vs exec)
- Reference: codex ExecCell, `/Users/williamcory/plue/tui/src/render/tools.ts`

## Tasks

### 1. Create Tool Card Widget (src/widgets/tool_card.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const ToolCall = @import("../state/message.zig").ToolCall;
const DiffRenderer = @import("../render/diff.zig").DiffRenderer;
const SyntaxHighlighter = @import("../render/syntax.zig").SyntaxHighlighter;

pub const ToolCard = struct {
    allocator: std.mem.Allocator,
    tool_call: *const ToolCall,
    expanded: bool = false,
    syntax: SyntaxHighlighter,

    const ICONS = std.ComptimeStringMap([]const u8, .{
        .{ "grep", "🔍" },
        .{ "readFile", "📄" },
        .{ "writeFile", "✏️" },
        .{ "multiedit", "📝" },
        .{ "webFetch", "🌐" },
        .{ "unifiedExec", "💻" },
        .{ "bash", "💻" },
        .{ "github", "🐙" },
        .{ "closePtySession", "🚪" },
        .{ "listPtySessions", "📋" },
        .{ "writeStdin", "⌨️" },
    });

    pub fn init(allocator: std.mem.Allocator, tool_call: *const ToolCall) ToolCard {
        return .{
            .allocator = allocator,
            .tool_call = tool_call,
            .syntax = SyntaxHighlighter.init(allocator),
        };
    }

    pub fn widget(self: *ToolCard) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = ToolCard.handleEvent,
            .drawFn = ToolCard.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *ToolCard = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.enter, .{}) or key.matches(vaxis.Key.space, .{})) {
                    self.expanded = !self.expanded;
                    ctx.consumeAndRedraw();
                }
            },
            .mouse => |mouse| {
                if (mouse.type == .press and mouse.button == .left) {
                    self.expanded = !self.expanded;
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *ToolCard = @ptrCast(@alignCast(ptr));
        const tc = self.tool_call;
        const width = ctx.max.width orelse 80;

        // Calculate height based on expansion
        const collapsed_height: u16 = 2;
        const expanded_height: u16 = self.calculateExpandedHeight(width);
        const height = if (self.expanded) expanded_height else collapsed_height;

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), .{
            .width = width,
            .height = height,
        });

        // Draw header line
        try self.drawHeader(&surface, width);

        // Draw preview/result
        if (self.expanded) {
            try self.drawExpanded(&surface, width);
        } else {
            try self.drawPreview(&surface, width);
        }

        return surface;
    }

    fn drawHeader(self: *ToolCard, surface: *vxfw.Surface, width: u16) !void {
        const tc = self.tool_call;
        var col: u16 = 0;

        // Expansion indicator
        const expand_char = if (self.expanded) "▼" else "▶";
        surface.writeCell(col, 0, .{
            .char = .{ .grapheme = expand_char, .width = 1 },
            .style = .{ .fg = .{ .index = 8 } },
        });
        col += 2;

        // Icon
        const icon = ICONS.get(tc.name) orelse "🔧";
        surface.writeCell(col, 0, .{
            .char = .{ .grapheme = icon, .width = 2 },
            .style = .{ .fg = .{ .index = 14 } },
        });
        col += 3;

        // Status indicator
        const status = self.getStatusIndicator();
        surface.writeCell(col, 0, .{
            .char = .{ .grapheme = status.icon, .width = 1 },
            .style = .{ .fg = status.color },
        });
        col += 2;

        // Tool name
        for (tc.name) |char| {
            if (col >= width - 15) break;
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 15 }, .bold = true },
            });
            col += 1;
        }

        // Arguments preview
        const args_preview = self.getArgsPreview();
        col += 1;
        for (args_preview) |char| {
            if (col >= width - 12) break;
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
            col += 1;
        }

        // Duration (right-aligned)
        if (tc.duration_ms()) |ms| {
            const duration_str = self.formatDuration(ms);
            const dur_col = width -| @as(u16, @intCast(duration_str.len + 2));
            surface.writeCell(dur_col, 0, .{
                .char = .{ .grapheme = "(", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
            for (duration_str, 0..) |char, i| {
                surface.writeCell(@intCast(dur_col + 1 + i), 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
            }
            surface.writeCell(width - 1, 0, .{
                .char = .{ .grapheme = ")", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }
    }

    fn drawPreview(self: *ToolCard, surface: *vxfw.Surface, width: u16) !void {
        const tc = self.tool_call;
        var col: u16 = 4;

        // Result preview (truncated)
        if (tc.result) |result| {
            const preview = self.getResultPreview(result.output, width -| 6);
            const style = if (result.is_error)
                vaxis.Cell.Style{ .fg = .{ .index = 9 } }
            else
                vaxis.Cell.Style{ .fg = .{ .index = 8 }, .dim = true };

            for (preview) |char| {
                if (col >= width) break;
                surface.writeCell(col, 1, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = style,
                });
                col += 1;
            }
        } else if (tc.status == .running) {
            // Running indicator
            const running_text = "Processing...";
            for (running_text) |char| {
                surface.writeCell(col, 1, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 14 }, .italic = true },
                });
                col += 1;
            }
        }
    }

    fn drawExpanded(self: *ToolCard, surface: *vxfw.Surface, width: u16) !void {
        const tc = self.tool_call;
        var row: u16 = 1;

        // Arguments section
        row = try self.drawSection(surface, "Arguments", row, width);
        row = try self.drawArguments(surface, row, width);

        // Result section
        if (tc.result) |result| {
            row = try self.drawSection(surface, if (result.is_error) "Error" else "Result", row, width);
            row = try self.drawResult(surface, result.output, row, width, result.is_error);
        }
    }

    fn drawSection(self: *ToolCard, surface: *vxfw.Surface, title: []const u8, row: u16, width: u16) !u16 {
        _ = self;
        // Draw section header
        for (0..width) |col| {
            surface.writeCell(@intCast(col), row, .{
                .char = .{ .grapheme = "─", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(i + 1), row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        return row + 1;
    }

    fn drawArguments(self: *ToolCard, surface: *vxfw.Surface, start_row: u16, width: u16) !u16 {
        const tc = self.tool_call;

        // Parse and display JSON arguments
        const segments = try self.syntax.highlight(tc.args, "json");
        var row = start_row;
        var col: u16 = 2;

        for (segments) |segment| {
            for (segment.text) |char| {
                if (char == '\n') {
                    row += 1;
                    col = 2;
                    continue;
                }
                if (col >= width) {
                    row += 1;
                    col = 2;
                }
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = segment.style,
                });
                col += 1;
            }
        }

        return row + 1;
    }

    fn drawResult(self: *ToolCard, surface: *vxfw.Surface, output: []const u8, start_row: u16, width: u16, is_error: bool) !u16 {
        _ = self;
        var row = start_row;
        var col: u16 = 2;

        const style = if (is_error)
            vaxis.Cell.Style{ .fg = .{ .index = 9 } }
        else
            vaxis.Cell.Style{ .fg = .{ .index = 7 } };

        // Limit output display
        const max_lines: u16 = 20;
        var line_count: u16 = 0;

        for (output) |char| {
            if (line_count >= max_lines) {
                // Show truncation indicator
                const more = "... (truncated)";
                for (more) |c| {
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = &[_]u8{c}, .width = 1 },
                        .style = .{ .fg = .{ .index = 8 }, .italic = true },
                    });
                    col += 1;
                }
                break;
            }

            if (char == '\n') {
                row += 1;
                col = 2;
                line_count += 1;
                continue;
            }
            if (col >= width) {
                row += 1;
                col = 2;
            }
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
            col += 1;
        }

        return row + 1;
    }

    fn calculateExpandedHeight(self: *ToolCard, width: u16) u16 {
        const tc = self.tool_call;
        var height: u16 = 2; // Header + args header

        // Args lines
        height += countLines(tc.args, width -| 4);

        // Result lines
        if (tc.result) |result| {
            height += 1; // Result header
            height += @min(countLines(result.output, width -| 4), 20);
        }

        return height + 1;
    }

    fn countLines(text: []const u8, line_width: u16) u16 {
        if (line_width == 0) return 1;
        var lines: u16 = 1;
        var col: u16 = 0;

        for (text) |char| {
            if (char == '\n') {
                lines += 1;
                col = 0;
            } else {
                col += 1;
                if (col >= line_width) {
                    lines += 1;
                    col = 0;
                }
            }
        }
        return lines;
    }

    const StatusIndicator = struct {
        icon: []const u8,
        color: vaxis.Color,
    };

    fn getStatusIndicator(self: *ToolCard) StatusIndicator {
        return switch (self.tool_call.status) {
            .pending => .{ .icon = "○", .color = .{ .index = 8 } },
            .running => .{ .icon = "◐", .color = .{ .index = 14 } },
            .completed => .{ .icon = "●", .color = .{ .index = 10 } },
            .failed => .{ .icon = "✗", .color = .{ .index = 9 } },
            .declined => .{ .icon = "⊘", .color = .{ .index = 11 } },
        };
    }

    fn getArgsPreview(self: *ToolCard) []const u8 {
        const args = self.tool_call.args;
        const name = self.tool_call.name;

        // Tool-specific previews
        if (std.mem.eql(u8, name, "unifiedExec") or std.mem.eql(u8, name, "bash")) {
            // Try to extract command
            if (std.mem.indexOf(u8, args, "\"command\":")) |idx| {
                const start = std.mem.indexOf(u8, args[idx..], "\"") orelse return "...";
                const cmd_start = idx + start + 1;
                if (std.mem.indexOf(u8, args[cmd_start..], "\"")) |end| {
                    return args[cmd_start..][0..@min(end, 40)];
                }
            }
        } else if (std.mem.eql(u8, name, "grep")) {
            // Extract pattern
            if (std.mem.indexOf(u8, args, "\"pattern\":")) |_| {
                return "searching...";
            }
        } else if (std.mem.eql(u8, name, "readFile") or std.mem.eql(u8, name, "writeFile")) {
            // Extract path
            if (std.mem.indexOf(u8, args, "\"path\":")) |idx| {
                const start = std.mem.indexOf(u8, args[idx..], "\"") orelse return "...";
                const path_start = idx + start + 1;
                if (std.mem.indexOf(u8, args[path_start..], "\"")) |end| {
                    return args[path_start..][0..@min(end, 50)];
                }
            }
        }

        // Default: truncate args
        return if (args.len > 50) args[0..50] else args;
    }

    fn getResultPreview(self: *ToolCard, output: []const u8, max_len: u16) []const u8 {
        _ = self;
        // Get first line
        const newline = std.mem.indexOf(u8, output, "\n");
        const first_line = if (newline) |nl| output[0..nl] else output;

        return if (first_line.len > max_len)
            first_line[0..max_len]
        else
            first_line;
    }

    fn formatDuration(self: *ToolCard, ms: u64) []const u8 {
        _ = self;
        if (ms < 100) return "<0.1s";
        if (ms < 1000) return "<1s";
        if (ms < 10000) return "<10s";
        if (ms < 60000) return "<1m";
        return ">1m";
    }
};
```

### 2. Create Command Execution Widget (src/widgets/exec_output.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

/// Widget for displaying command execution output with ANSI support
pub const ExecOutput = struct {
    allocator: std.mem.Allocator,
    command: []const u8,
    working_dir: ?[]const u8 = null,
    output: std.ArrayList(u8),
    is_running: bool = false,
    exit_code: ?i32 = null,
    start_time: ?i64 = null,

    pub fn init(allocator: std.mem.Allocator, command: []const u8) ExecOutput {
        return .{
            .allocator = allocator,
            .command = command,
            .output = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *ExecOutput) void {
        self.output.deinit();
    }

    pub fn appendOutput(self: *ExecOutput, data: []const u8) !void {
        try self.output.appendSlice(data);
    }

    pub fn widget(self: *ExecOutput) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = ExecOutput.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *ExecOutput = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        var row: u16 = 0;

        // Command header
        row = self.drawCommandHeader(&surface, row, size.width);

        // Output with ANSI parsing
        row = self.drawOutput(&surface, row, size.width, size.height);

        // Footer with exit code
        if (self.exit_code != null and row < size.height) {
            self.drawFooter(&surface, row, size.width);
        }

        return surface;
    }

    fn drawCommandHeader(self: *ExecOutput, surface: *vxfw.Surface, row: u16, width: u16) u16 {
        var col: u16 = 0;

        // Prompt
        const prompt = "$ ";
        for (prompt) |char| {
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 10 }, .bold = true },
            });
            col += 1;
        }

        // Command
        for (self.command) |char| {
            if (col >= width) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 15 } },
            });
            col += 1;
        }

        // Running indicator
        if (self.is_running) {
            const indicator = " ⟳";
            for (indicator) |char| {
                if (col >= width) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 14 } },
                });
                col += 1;
            }
        }

        return row + 1;
    }

    fn drawOutput(self: *ExecOutput, surface: *vxfw.Surface, start_row: u16, width: u16, max_height: u16) u16 {
        var row = start_row;
        var col: u16 = 0;
        var current_style = vaxis.Cell.Style{};

        var i: usize = 0;
        const output = self.output.items;

        while (i < output.len and row < max_height - 1) {
            const char = output[i];

            // Handle ANSI escape sequences
            if (char == 0x1b and i + 1 < output.len and output[i + 1] == '[') {
                i += 2;
                const new_style = self.parseAnsiSequence(output[i..], &i);
                current_style = self.mergeStyles(current_style, new_style);
                continue;
            }

            // Handle newline
            if (char == '\n') {
                row += 1;
                col = 0;
                i += 1;
                continue;
            }

            // Handle carriage return
            if (char == '\r') {
                col = 0;
                i += 1;
                continue;
            }

            // Wrap
            if (col >= width) {
                row += 1;
                col = 0;
            }

            // Draw character
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = current_style,
            });
            col += 1;
            i += 1;
        }

        return row + 1;
    }

    fn parseAnsiSequence(self: *ExecOutput, data: []const u8, offset: *usize) vaxis.Cell.Style {
        _ = self;
        var style = vaxis.Cell.Style{};
        var num: u8 = 0;

        for (data, 0..) |char, i| {
            if (char >= '0' and char <= '9') {
                num = num * 10 + (char - '0');
            } else if (char == ';' or char == 'm') {
                // Apply SGR code
                switch (num) {
                    0 => style = .{}, // Reset
                    1 => style.bold = true,
                    2 => style.dim = true,
                    3 => style.italic = true,
                    4 => style.ul_style = .single,
                    7 => style.reverse = true,
                    9 => style.strikethrough = true,
                    30...37 => style.fg = .{ .index = num - 30 },
                    40...47 => style.bg = .{ .index = num - 40 },
                    90...97 => style.fg = .{ .index = num - 82 }, // Bright colors
                    else => {},
                }
                num = 0;

                if (char == 'm') {
                    offset.* += i + 1;
                    return style;
                }
            } else {
                offset.* += i + 1;
                return style;
            }
        }

        return style;
    }

    fn mergeStyles(self: *ExecOutput, base: vaxis.Cell.Style, new: vaxis.Cell.Style) vaxis.Cell.Style {
        _ = self;
        var result = base;
        if (new.fg != .default) result.fg = new.fg;
        if (new.bg != .default) result.bg = new.bg;
        if (new.bold) result.bold = true;
        if (new.dim) result.dim = true;
        if (new.italic) result.italic = true;
        if (new.reverse) result.reverse = true;
        if (new.strikethrough) result.strikethrough = true;
        if (new.ul_style != .off) result.ul_style = new.ul_style;
        return result;
    }

    fn drawFooter(self: *ExecOutput, surface: *vxfw.Surface, row: u16, width: u16) void {
        var col: u16 = 0;

        // Separator
        for (0..width) |c| {
            surface.writeCell(@intCast(c), row, .{
                .char = .{ .grapheme = "─", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Exit code
        if (self.exit_code) |code| {
            const is_success = code == 0;
            const icon = if (is_success) "✓" else "✗";
            const text = if (is_success) "Success" else "Failed";
            const color: vaxis.Color = if (is_success) .{ .index = 10 } else .{ .index = 9 };

            surface.writeCell(col, row, .{
                .char = .{ .grapheme = icon, .width = 1 },
                .style = .{ .fg = color },
            });
            col += 2;

            for (text) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = color },
                });
                col += 1;
            }

            if (code != 0) {
                const code_str = std.fmt.allocPrint(self.allocator, " (exit {d})", .{code}) catch "";
                for (code_str) |char| {
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = .{ .fg = .{ .index = 8 } },
                    });
                    col += 1;
                }
            }
        }
    }
};
```

## Acceptance Criteria

- [ ] Tool cards show icon, name, status, duration
- [ ] Expand/collapse with Enter or click
- [ ] Arguments displayed with JSON highlighting
- [ ] Results displayed with proper formatting
- [ ] Error results shown in red
- [ ] Truncation for long outputs
- [ ] Command execution shows $ prompt
- [ ] ANSI color codes parsed and displayed
- [ ] Exit code shown with success/failure indicator
- [ ] Running indicator for in-progress commands

## Files to Create

1. `tui-zig/src/widgets/tool_card.zig`
2. `tui-zig/src/widgets/exec_output.zig`

## Next

Proceed to `13_approval_overlays.md` for approval UI components.
