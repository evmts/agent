const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const ToolCall = @import("../state/message.zig").ToolCall;
const ToolCallStatus = @import("../state/message.zig").ToolCallStatus;

/// Widget for displaying a tool call with status, arguments, and results
pub const ToolCard = struct {
    allocator: std.mem.Allocator,
    tool_call: *const ToolCall,
    expanded: bool = false,

    const ICONS = std.StaticStringMap([]const u8).initComptime(.{
        .{ "grep", "search" },
        .{ "readFile", "file" },
        .{ "writeFile", "edit" },
        .{ "multiedit", "edit" },
        .{ "webFetch", "web" },
        .{ "unifiedExec", "term" },
        .{ "bash", "term" },
        .{ "github", "git" },
        .{ "closePtySession", "exit" },
        .{ "listPtySessions", "list" },
        .{ "writeStdin", "input" },
        .{ "glob", "find" },
        .{ "read", "file" },
        .{ "edit", "edit" },
        .{ "write", "write" },
    });

    pub fn init(allocator: std.mem.Allocator, tool_call: *const ToolCall) ToolCard {
        return .{
            .allocator = allocator,
            .tool_call = tool_call,
        };
    }

    pub fn widget(self: *ToolCard) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = ToolCard.handleEvent,
            .drawFn = ToolCard.draw,
        };
    }

    fn handleEvent(userdata: ?*anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) void {
        const self: *ToolCard = @ptrCast(@alignCast(userdata orelse return));

        switch (event) {
            .key_press => |key| {
                if (key.codepoint == vaxis.Key.enter or key.codepoint == ' ') {
                    self.expanded = !self.expanded;
                    ctx.request_redraw = true;
                }
            },
            .mouse => |mouse| {
                if (mouse.type == .press and mouse.button == .left) {
                    self.expanded = !self.expanded;
                    ctx.request_redraw = true;
                }
            },
            else => {},
        }
    }

    fn draw(userdata: ?*anyopaque, ctx: vxfw.DrawContext) vxfw.DrawResult {
        const self: *ToolCard = @ptrCast(@alignCast(userdata orelse return .{ .surface = null }));
        const tc = self.tool_call;
        const width: u31 = @intCast(ctx.max.width orelse 80);

        // Calculate height based on expansion
        const collapsed_height: u31 = 2;
        const expanded_height: u31 = self.calculateExpandedHeight(width);
        const height: u31 = if (self.expanded) expanded_height else collapsed_height;

        var surface = vxfw.Surface.init(ctx.arena, self.widget(), @intCast(width), @intCast(height)) catch return .{ .surface = null };

        // Draw header line
        self.drawHeader(&surface, @intCast(width));

        // Draw preview/result
        if (self.expanded) {
            self.drawExpanded(&surface, @intCast(width));
        } else {
            self.drawPreview(&surface, @intCast(width));
        }

        return .{ .surface = surface };
    }

    fn drawHeader(self: *ToolCard, surface: *vxfw.Surface, width: u16) void {
        const tc = self.tool_call;
        var col: u16 = 0;

        // Expansion indicator
        const expand_char: []const u8 = if (self.expanded) "v" else ">";
        surface.writeCell(col, 0, .{
            .char = .{ .grapheme = expand_char, .width = 1 },
            .style = .{ .fg = .{ .index = 8 } },
        });
        col += 2;

        // Icon/label
        const icon = ICONS.get(tc.name) orelse "tool";
        for (icon) |char| {
            if (col >= width -| 15) break;
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 } },
            });
            col += 1;
        }
        col += 1;

        // Status indicator
        const status = self.getStatusIndicator();
        surface.writeCell(col, 0, .{
            .char = .{ .grapheme = status.icon, .width = 1 },
            .style = .{ .fg = status.color },
        });
        col += 2;

        // Tool name
        for (tc.name) |char| {
            if (col >= width -| 15) break;
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
            if (col >= width -| 12) break;
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
            for (duration_str, 0..) |char, i| {
                surface.writeCell(dur_col + @as(u16, @intCast(i)), 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
            }
        }
    }

    fn drawPreview(self: *ToolCard, surface: *vxfw.Surface, width: u16) void {
        const tc = self.tool_call;
        var col: u16 = 4;

        // Result preview (truncated)
        if (tc.result) |result| {
            const preview = self.getResultPreview(result.output, width -| 6);
            const style: vaxis.Cell.Style = if (result.is_error)
                .{ .fg = .{ .index = 9 } }
            else
                .{ .fg = .{ .index = 8 }, .dim = true };

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

    fn drawExpanded(self: *ToolCard, surface: *vxfw.Surface, width: u16) void {
        const tc = self.tool_call;
        var row: u16 = 1;

        // Arguments section header
        self.drawSectionHeader(surface, "Arguments", row, width);
        row += 1;

        // Draw arguments (JSON)
        row = self.drawContent(surface, tc.args, row, width, .{ .fg = .{ .index = 7 } });

        // Result section
        if (tc.result) |result| {
            const title = if (result.is_error) "Error" else "Result";
            self.drawSectionHeader(surface, title, row, width);
            row += 1;

            const style: vaxis.Cell.Style = if (result.is_error)
                .{ .fg = .{ .index = 9 } }
            else
                .{ .fg = .{ .index = 7 } };

            _ = self.drawContent(surface, result.output, row, width, style);
        }
    }

    fn drawSectionHeader(self: *ToolCard, surface: *vxfw.Surface, title: []const u8, row: u16, width: u16) void {
        _ = self;
        // Draw section header line
        for (0..width) |col| {
            surface.writeCell(@intCast(col), row, .{
                .char = .{ .grapheme = "-", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        for (title, 0..) |char, i| {
            surface.writeCell(@as(u16, @intCast(i + 1)), row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }
    }

    fn drawContent(self: *ToolCard, surface: *vxfw.Surface, text: []const u8, start_row: u16, width: u16, style: vaxis.Cell.Style) u16 {
        _ = self;
        var row = start_row;
        var col: u16 = 2;
        const max_lines: u16 = 20;
        var line_count: u16 = 0;

        for (text) |char| {
            if (line_count >= max_lines) {
                // Show truncation indicator
                const more = "... (truncated)";
                for (more) |c| {
                    if (col < width) {
                        surface.writeCell(col, row, .{
                            .char = .{ .grapheme = &[_]u8{c}, .width = 1 },
                            .style = .{ .fg = .{ .index = 8 }, .italic = true },
                        });
                        col += 1;
                    }
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

    fn calculateExpandedHeight(self: *ToolCard, width: u16) u31 {
        const tc = self.tool_call;
        var height: u31 = 2; // Header + args header

        // Args lines
        height += countLines(tc.args, width -| 4);

        // Result lines
        if (tc.result) |result| {
            height += 1; // Result header
            height += @min(countLines(result.output, width -| 4), 20);
        }

        return height + 1;
    }

    fn countLines(text: []const u8, line_width: u16) u31 {
        if (line_width == 0) return 1;
        var lines: u31 = 1;
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
            .pending => .{ .icon = "o", .color = .{ .index = 8 } },
            .running => .{ .icon = "*", .color = .{ .index = 14 } },
            .completed => .{ .icon = "+", .color = .{ .index = 10 } },
            .failed => .{ .icon = "x", .color = .{ .index = 9 } },
            .declined => .{ .icon = "-", .color = .{ .index = 11 } },
        };
    }

    fn getArgsPreview(self: *ToolCard) []const u8 {
        const args = self.tool_call.args;
        const name = self.tool_call.name;

        // Tool-specific previews
        if (std.mem.eql(u8, name, "unifiedExec") or std.mem.eql(u8, name, "bash")) {
            // Try to extract command
            if (std.mem.indexOf(u8, args, "\"command\":")) |idx| {
                const after = args[idx + 11 ..];
                if (std.mem.indexOf(u8, after, "\"")) |end| {
                    return after[0..@min(end, 40)];
                }
            }
        } else if (std.mem.eql(u8, name, "readFile") or std.mem.eql(u8, name, "writeFile") or
            std.mem.eql(u8, name, "read") or std.mem.eql(u8, name, "write"))
        {
            // Extract path
            if (std.mem.indexOf(u8, args, "\"path\":")) |idx| {
                const after = args[idx + 8 ..];
                if (std.mem.indexOf(u8, after, "\"")) |end| {
                    return after[0..@min(end, 50)];
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
